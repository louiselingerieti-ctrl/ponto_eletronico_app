import 'dart:convert';

import 'package:sqlite3/sqlite3.dart' show Row;
import 'package:uuid/uuid.dart';

import '../application/ports.dart';
import '../domain/presence_event.dart';
import '../domain/queued_event.dart';
import 'encrypted_database.dart';

/// Fila local (outbox) sobre [EncryptedDatabase]. Não existe construtor sem
/// cifra: a instância vem de `LocalStore.open`.
class SqliteEventQueue implements EventQueue {
  SqliteEventQueue(this._db);

  final EncryptedDatabase _db;
  static const _uuid = Uuid();

  static void migrate(EncryptedDatabase db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS outbox (
        event_id           TEXT PRIMARY KEY,
        seq                INTEGER NOT NULL UNIQUE CHECK (seq >= 1),
        payload            TEXT NOT NULL,
        state              TEXT NOT NULL CHECK (state IN
                             ('savedLocally','sending','received','conflict','rejected')),
        attempts           INTEGER NOT NULL DEFAULT 0,
        saved_at_us        INTEGER NOT NULL,
        next_attempt_us    INTEGER,
        lease_token        TEXT,
        lease_until_us     INTEGER,
        receipt_id         TEXT,
        server_received_us INTEGER,
        outcome_code       TEXT,
        capture_flags      TEXT NOT NULL DEFAULT ''
      ) STRICT;
      CREATE INDEX IF NOT EXISTS outbox_pending
        ON outbox (state, next_attempt_us, seq);
      -- Conteúdo, ID e sequência são imutáveis depois de gravados.
      CREATE TRIGGER IF NOT EXISTS outbox_immutable
        BEFORE UPDATE OF event_id, seq, payload, saved_at_us ON outbox
        BEGIN SELECT RAISE(ABORT, 'evento imutável'); END;
      CREATE TRIGGER IF NOT EXISTS outbox_no_delete
        BEFORE DELETE ON outbox
        BEGIN SELECT RAISE(ABORT, 'retenção local pendente (D-PRIV)'); END;
    ''');
    db.execute(
        "INSERT OR IGNORE INTO meta (key, value) VALUES ('next_sequence', '1')");
  }

  String _meta(String key) =>
      _db.select('SELECT value FROM meta WHERE key = ?', [key]).first['value']
          as String;

  String? _metaOrNull(String key) {
    final r = _db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  void _setMeta(String key, String? value) {
    if (value == null) {
      _db.execute('DELETE FROM meta WHERE key = ?', [key]);
    } else {
      _db.execute(
          'INSERT INTO meta (key, value) VALUES (?, ?) '
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [key, value]);
    }
  }

  @override
  QueuedEvent append(PresenceEventDraft draft,
      {required DateTime now, Set<String> captureFlags = const {}}) {
    return _db.tx(() {
      final seq = int.parse(_meta('next_sequence'));
      final eventId = _uuid.v4();
      final payload = jsonEncode(
          draft.toContractJson(eventId: eventId, installationSequence: seq));
      final savedUs = now.toUtc().microsecondsSinceEpoch;
      _db.execute(
        'INSERT INTO outbox (event_id, seq, payload, state, saved_at_us, '
        "next_attempt_us, capture_flags) VALUES (?, ?, ?, 'savedLocally', ?, ?, ?)",
        [eventId, seq, payload, savedUs, savedUs, (captureFlags.toList()..sort()).join(',')],
      );
      _setMeta('next_sequence', '${seq + 1}');
      return _byId(eventId)!;
    });
  }

  @override
  LeasedBatch lease({
    required int max,
    required DateTime now,
    required DateTime leaseUntil,
  }) {
    return _db.tx(() {
      final token = _uuid.v4();
      final rows = _db.select(
        "SELECT event_id FROM outbox WHERE state = 'savedLocally' "
        'AND (next_attempt_us IS NULL OR next_attempt_us <= ?) '
        'ORDER BY seq LIMIT ?',
        [now.toUtc().microsecondsSinceEpoch, max],
      );
      final ids = [for (final r in rows) r['event_id'] as String];
      for (final id in ids) {
        _db.execute(
          "UPDATE outbox SET state = 'sending', attempts = attempts + 1, "
          'lease_token = ?, lease_until_us = ? WHERE event_id = ?',
          [token, leaseUntil.toUtc().microsecondsSinceEpoch, id],
        );
      }
      return LeasedBatch(token, [for (final id in ids) _byId(id)!]);
    });
  }

  @override
  void settle({
    required String token,
    required Map<String, EventOutcome> outcomes,
    required DateTime retryAt,
  }) {
    _db.tx(() {
      for (final id in _idsOf(token)) {
        final o = outcomes[id];
        if (o == null) {
          _backToQueue(id, token, retryAt);
          continue;
        }
        final state = switch (o.kind) {
          OutcomeKind.accepted || OutcomeKind.duplicate => 'received',
          OutcomeKind.conflict => 'conflict',
          OutcomeKind.rejected => 'rejected',
        };
        _db.execute(
          'UPDATE outbox SET state = ?, lease_token = NULL, lease_until_us = NULL, '
          'next_attempt_us = NULL, receipt_id = ?, server_received_us = ?, '
          "outcome_code = ? WHERE event_id = ? AND state = 'sending' AND lease_token = ?",
          [
            state,
            o.receiptId,
            o.receivedAt?.toUtc().microsecondsSinceEpoch,
            o.code ?? (o.kind == OutcomeKind.duplicate ? 'duplicate' : null),
            id,
            token,
          ],
        );
      }
    });
  }

  @override
  void release(String token, {required DateTime retryAt}) {
    _db.tx(() {
      for (final id in _idsOf(token)) {
        _backToQueue(id, token, retryAt);
      }
    });
  }

  List<String> _idsOf(String token) => [
        for (final r in _db.select(
            "SELECT event_id FROM outbox WHERE lease_token = ? AND state = 'sending'",
            [token]))
          r['event_id'] as String,
      ];

  void _backToQueue(String id, String token, DateTime retryAt) {
    _db.execute(
      "UPDATE outbox SET state = 'savedLocally', lease_token = NULL, "
      'lease_until_us = NULL, next_attempt_us = ? '
      "WHERE event_id = ? AND state = 'sending' AND lease_token = ?",
      [retryAt.toUtc().microsecondsSinceEpoch, id, token],
    );
  }

  @override
  int recoverExpiredLeases(DateTime now) {
    return _db.tx(() {
      _db.execute(
        "UPDATE outbox SET state = 'savedLocally', lease_token = NULL, "
        "lease_until_us = NULL WHERE state = 'sending' AND lease_until_us <= ?",
        [now.toUtc().microsecondsSinceEpoch],
      );
      return _db.updatedRows;
    });
  }

  @override
  List<QueuedEvent> all() => [
        for (final r in _db.select('SELECT * FROM outbox ORDER BY seq')) _map(r),
      ];

  @override
  DateTime? nextAttemptAt() {
    final v = _db
        .select("SELECT min(next_attempt_us) AS v FROM outbox "
            "WHERE state = 'savedLocally'")
        .first['v'] as int?;
    return v == null ? null : DateTime.fromMicrosecondsSinceEpoch(v, isUtc: true);
  }

  @override
  int consecutiveFailures() => int.parse(_metaOrNull('delivery_failures') ?? '0');

  @override
  void setConsecutiveFailures(int n) =>
      _db.tx(() => _setMeta('delivery_failures', '$n'));

  @override
  DeliveryHalt? deliveryHalt() {
    final reason = _metaOrNull('delivery_halt');
    if (reason == null) return null;
    return DeliveryHalt(
      DeliveryHaltReason.values.byName(reason),
      DateTime.fromMicrosecondsSinceEpoch(
          int.parse(_meta('delivery_halt_at_us')), isUtc: true),
      detail: _metaOrNull('delivery_halt_detail'),
    );
  }

  @override
  void haltDelivery(DeliveryHalt halt) => _db.tx(() {
        _setMeta('delivery_halt', halt.reason.name);
        _setMeta('delivery_halt_at_us', '${halt.at.toUtc().microsecondsSinceEpoch}');
        _setMeta('delivery_halt_detail', halt.detail);
      });

  @override
  void clearHalt() => _db.tx(() {
        _setMeta('delivery_halt', null);
        _setMeta('delivery_halt_at_us', null);
        _setMeta('delivery_halt_detail', null);
      });

  @override
  Set<String> captureFlagsOf(String eventId) {
    final r = _db.select(
        'SELECT capture_flags FROM outbox WHERE event_id = ?', [eventId]);
    if (r.isEmpty) return const {};
    final s = r.first['capture_flags'] as String;
    return s.isEmpty ? const {} : s.split(',').toSet();
  }

  QueuedEvent? _byId(String id) {
    final rows = _db.select('SELECT * FROM outbox WHERE event_id = ?', [id]);
    return rows.isEmpty ? null : _map(rows.first);
  }

  static DateTime? _ts(Object? us) => us == null
      ? null
      : DateTime.fromMicrosecondsSinceEpoch(us as int, isUtc: true);

  static QueuedEvent _map(Row r) => QueuedEvent(
        eventId: r['event_id'] as String,
        installationSequence: r['seq'] as int,
        payloadJson: r['payload'] as String,
        state: DeliveryState.values.byName(r['state'] as String),
        attempts: r['attempts'] as int,
        savedAt: _ts(r['saved_at_us'])!,
        nextAttemptAt: _ts(r['next_attempt_us']),
        receiptId: r['receipt_id'] as String?,
        serverReceivedAt: _ts(r['server_received_us']),
        outcomeCode: r['outcome_code'] as String?,
      );
}
