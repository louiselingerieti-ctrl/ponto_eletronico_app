import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../application/ports.dart';
import '../domain/presence_event.dart';
import '../domain/queued_event.dart';

/// Fila local em SQLite (outbox). Cifra opcional via SQLite3MultipleCiphers
/// (`hexKey`). A chave em produção viria do armazenamento seguro do SO
/// (Keystore/Keychain) — fora do escopo desta prova de conceito.
///
/// Durabilidade: WAL + `synchronous=FULL`, para que o commit que precede a
/// mensagem "registrado no aparelho" sobreviva a queda de energia.
class SqliteEventQueue implements EventQueue {
  SqliteEventQueue._(this._db);

  /// [installationId] só é usado na primeira abertura; depois vale o gravado.
  factory SqliteEventQueue.open(
    String path, {
    String? hexKey,
    String? installationId,
  }) {
    final db = sqlite3.open(path);
    try {
      if (hexKey != null) {
        if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hexKey)) {
          throw ArgumentError('hexKey deve ter 32 bytes em hexadecimal');
        }
        // Precisa ser o primeiro comando na conexão.
        db.execute("PRAGMA hexkey = '$hexKey';");
      }
      // Falha aqui com chave errada ou ausente em arquivo cifrado.
      db.select('SELECT count(*) FROM sqlite_master;');
      db.execute('PRAGMA journal_mode = WAL;');
      db.execute('PRAGMA synchronous = FULL;');
      db.execute('PRAGMA foreign_keys = ON;');
      _migrate(db, installationId ?? const Uuid().v4());
    } catch (_) {
      db.close();
      rethrow;
    }
    return SqliteEventQueue._(db);
  }

  final Database _db;
  static const _uuid = Uuid();

  static void _migrate(Database db, String installationId) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      ) STRICT;
      CREATE TABLE IF NOT EXISTS outbox (
        event_id           TEXT PRIMARY KEY,
        seq                INTEGER NOT NULL UNIQUE CHECK (seq >= 1),
        payload            TEXT NOT NULL,
        state              TEXT NOT NULL CHECK (state IN
                             ('savedLocally','sending','received','conflict','rejected')),
        attempts           INTEGER NOT NULL DEFAULT 0,
        saved_at_us        INTEGER NOT NULL,
        next_attempt_us    INTEGER,
        lease_until_us     INTEGER,
        receipt_id         TEXT,
        server_received_us INTEGER,
        outcome_code       TEXT
      ) STRICT;
      CREATE INDEX IF NOT EXISTS outbox_pending
        ON outbox (state, next_attempt_us, seq);
    ''');
    db.execute(
        "INSERT OR IGNORE INTO meta (key, value) VALUES ('installation_id', ?)",
        [installationId]);
    db.execute(
        "INSERT OR IGNORE INTO meta (key, value) VALUES ('next_sequence', '1')");
    db.execute(
        "INSERT OR IGNORE INTO meta (key, value) VALUES ('schema_version', '1')");
  }

  String get installationId => _db
      .select("SELECT value FROM meta WHERE key = 'installation_id'")
      .first['value'] as String;

  void close() => _db.close();

  T _tx<T>(T Function() body) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      final r = body();
      _db.execute('COMMIT;');
      return r;
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  QueuedEvent append(PresenceEventDraft draft, {required DateTime now}) {
    return _tx(() {
      final seq = int.parse(_db
          .select("SELECT value FROM meta WHERE key = 'next_sequence'")
          .first['value'] as String);
      final eventId = _uuid.v4();
      final payload = jsonEncode(
          draft.toContractJson(eventId: eventId, installationSequence: seq));
      final savedUs = now.toUtc().microsecondsSinceEpoch;
      _db.execute(
        'INSERT INTO outbox (event_id, seq, payload, state, saved_at_us, next_attempt_us) '
        "VALUES (?, ?, ?, 'savedLocally', ?, ?)",
        [eventId, seq, payload, savedUs, savedUs],
      );
      _db.execute("UPDATE meta SET value = ? WHERE key = 'next_sequence'",
          ['${seq + 1}']);
      return _byId(eventId)!;
    });
  }

  @override
  List<QueuedEvent> lease({
    required int max,
    required DateTime now,
    required DateTime leaseUntil,
  }) {
    return _tx(() {
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
          'lease_until_us = ? WHERE event_id = ?',
          [leaseUntil.toUtc().microsecondsSinceEpoch, id],
        );
      }
      return [for (final id in ids) _byId(id)!];
    });
  }

  @override
  void settle({
    required List<String> leasedIds,
    required Map<String, EventOutcome> outcomes,
    required DateTime retryAt,
  }) {
    _tx(() {
      for (final id in leasedIds) {
        final o = outcomes[id];
        if (o == null) {
          _backToQueue(id, retryAt);
          continue;
        }
        final state = switch (o.kind) {
          OutcomeKind.accepted || OutcomeKind.duplicate => 'received',
          OutcomeKind.conflict => 'conflict',
          OutcomeKind.rejected => 'rejected',
        };
        _db.execute(
          'UPDATE outbox SET state = ?, lease_until_us = NULL, next_attempt_us = NULL, '
          'receipt_id = ?, server_received_us = ?, outcome_code = ? '
          "WHERE event_id = ? AND state = 'sending'",
          [
            state,
            o.receiptId,
            o.receivedAt?.toUtc().microsecondsSinceEpoch,
            o.code ?? (o.kind == OutcomeKind.duplicate ? 'duplicate' : null),
            id,
          ],
        );
      }
    });
  }

  @override
  void release(List<String> leasedIds, {required DateTime retryAt}) {
    _tx(() {
      for (final id in leasedIds) {
        _backToQueue(id, retryAt);
      }
    });
  }

  void _backToQueue(String id, DateTime retryAt) {
    _db.execute(
      "UPDATE outbox SET state = 'savedLocally', lease_until_us = NULL, "
      "next_attempt_us = ? WHERE event_id = ? AND state = 'sending'",
      [retryAt.toUtc().microsecondsSinceEpoch, id],
    );
  }

  @override
  int recoverExpiredLeases(DateTime now) {
    return _tx(() {
      _db.execute(
        "UPDATE outbox SET state = 'savedLocally', lease_until_us = NULL "
        "WHERE state = 'sending' AND lease_until_us <= ?",
        [now.toUtc().microsecondsSinceEpoch],
      );
      return _db.updatedRows;
    });
  }

  @override
  List<QueuedEvent> all() => [
        for (final r in _db.select('SELECT * FROM outbox ORDER BY seq'))
          _map(r),
      ];

  @override
  DateTime? nextAttemptAt() {
    final v = _db.select(
        "SELECT min(next_attempt_us) AS v FROM outbox WHERE state = 'savedLocally'")
        .first['v'] as int?;
    return v == null ? null : DateTime.fromMicrosecondsSinceEpoch(v, isUtc: true);
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
