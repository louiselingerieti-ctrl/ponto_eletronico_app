import 'dart:convert';

import 'package:sqlite3/sqlite3.dart' show Row;

import '../application/persistence.dart';
import '../domain/clock_quality.dart';
import '../domain/presence_config.dart';
import 'encrypted_database.dart';

/// Configuração de presença e revogações por vínculo, na base cifrada.
class SqliteConfigStore implements ConfigRepository {
  SqliteConfigStore(this._db);
  final EncryptedDatabase _db;

  static void migrate(EncryptedDatabase db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS presence_config (
        employment_link_id TEXT NOT NULL,
        config_revision    TEXT NOT NULL,
        payload            TEXT NOT NULL,
        server_time_us     INTEGER NOT NULL,
        valid_until_us     INTEGER NOT NULL,
        received_at_us     INTEGER NOT NULL,
        persisted_at_us    INTEGER NOT NULL,
        stage              TEXT NOT NULL CHECK (stage IN ('persisted','applied','applyFailed')),
        applied_at_us      INTEGER,
        apply_detail       TEXT,
        apply_event_id     TEXT,
        expired_event_id   TEXT,
        superseded_at_us   INTEGER,
        ref_elapsed_ms     INTEGER,
        ref_boot_id        TEXT,
        ref_rtt_ms         INTEGER,
        PRIMARY KEY (employment_link_id, config_revision)
      ) STRICT;
      CREATE UNIQUE INDEX IF NOT EXISTS presence_config_current
        ON presence_config (employment_link_id) WHERE superseded_at_us IS NULL;
      CREATE TABLE IF NOT EXISTS link_revocation (
        id                 INTEGER PRIMARY KEY,
        employment_link_id TEXT NOT NULL,
        revoked_at_us      INTEGER NOT NULL,
        reason             TEXT NOT NULL,
        lifted_at_us       INTEGER
      ) STRICT;
      CREATE UNIQUE INDEX IF NOT EXISTS link_revocation_active
        ON link_revocation (employment_link_id) WHERE lifted_at_us IS NULL;
    ''');
  }

  @override
  StoredConfig? current(String linkId) => _one(
      'SELECT * FROM presence_config WHERE employment_link_id = ? '
      'AND superseded_at_us IS NULL',
      [linkId]);

  @override
  StoredConfig? byRevision(String linkId, String revision) => _one(
      'SELECT * FROM presence_config WHERE employment_link_id = ? AND config_revision = ?',
      [linkId, revision]);

  @override
  List<StoredConfig> history(String linkId) => [
        for (final r in _db.select(
            'SELECT * FROM presence_config WHERE employment_link_id = ? '
            'ORDER BY server_time_us',
            [linkId]))
          _map(r),
      ];

  /// Grava como atual e marca a anterior como substituída (mesma transação).
  @override
  void insertCurrent(
    PresenceConfig c, {
    required String rawJson,
    required DateTime receivedAt,
    required DateTime persistedAt,
    required ServerTimeReference? reference,
  }) {
    _db.tx(() {
      _db.execute(
          'UPDATE presence_config SET superseded_at_us = ? '
          'WHERE employment_link_id = ? AND superseded_at_us IS NULL',
          [_us(persistedAt), c.employmentLinkId]);
      _db.execute(
        'INSERT INTO presence_config (employment_link_id, config_revision, payload, '
        'server_time_us, valid_until_us, received_at_us, persisted_at_us, stage, '
        'ref_elapsed_ms, ref_boot_id, ref_rtt_ms) '
        "VALUES (?, ?, ?, ?, ?, ?, ?, 'persisted', ?, ?, ?)",
        [
          c.employmentLinkId, c.configRevision, rawJson, _us(c.serverTime),
          _us(c.validUntil), _us(receivedAt), _us(persistedAt),
          reference?.elapsedAtReceiptMs, reference?.bootId,
          reference?.roundTrip.inMilliseconds,
        ],
      );
    });
  }

  @override
  void setApplyResult(String linkId, String revision,
      {required ApplyStage stage, required DateTime at, String? detail, String? eventId}) {
    _db.execute(
      'UPDATE presence_config SET stage = ?, applied_at_us = ?, apply_detail = ?, '
      'apply_event_id = ? WHERE employment_link_id = ? AND config_revision = ?',
      [stage.name, stage == ApplyStage.applied ? _us(at) : null, detail, eventId,
        linkId, revision],
    );
  }

  @override
  void setExpiredEvent(String linkId, String revision, String eventId) {
    _db.execute(
      'UPDATE presence_config SET expired_event_id = ? '
      'WHERE employment_link_id = ? AND config_revision = ? AND expired_event_id IS NULL',
      [eventId, linkId, revision],
    );
  }

  /// Referência de horário mais recente obtida de uma configuração.
  @override
  ServerTimeReference? latestClockReference() {
    final r = _db.select(
        'SELECT server_time_us, ref_elapsed_ms, ref_boot_id, ref_rtt_ms '
        'FROM presence_config WHERE ref_elapsed_ms IS NOT NULL '
        'AND ref_boot_id IS NOT NULL ORDER BY persisted_at_us DESC LIMIT 1');
    if (r.isEmpty) return null;
    final row = r.first;
    return ServerTimeReference(
      serverTime: _ts(row['server_time_us'])!,
      elapsedAtReceiptMs: row['ref_elapsed_ms'] as int,
      bootId: row['ref_boot_id'] as String,
      roundTrip: Duration(milliseconds: row['ref_rtt_ms'] as int),
    );
  }

  @override
  Revocation? activeRevocation(String linkId) {
    final r = _db.select(
        'SELECT * FROM link_revocation WHERE employment_link_id = ? AND lifted_at_us IS NULL',
        [linkId]);
    if (r.isEmpty) return null;
    return Revocation(linkId, _ts(r.first['revoked_at_us'])!, r.first['reason'] as String);
  }

  @override
  void revoke(String linkId, {required String reason, required DateTime at}) {
    _db.tx(() {
      if (activeRevocation(linkId) != null) return;
      _db.execute(
          'INSERT INTO link_revocation (employment_link_id, revoked_at_us, reason) '
          'VALUES (?, ?, ?)',
          [linkId, _us(at), reason]);
    });
  }

  @override
  void liftRevocation(String linkId, {required DateTime at}) {
    _db.execute(
        'UPDATE link_revocation SET lifted_at_us = ? '
        'WHERE employment_link_id = ? AND lifted_at_us IS NULL',
        [_us(at), linkId]);
  }

  StoredConfig? _one(String sql, List<Object?> p) {
    final r = _db.select(sql, p);
    return r.isEmpty ? null : _map(r.first);
  }

  static int _us(DateTime t) => t.toUtc().microsecondsSinceEpoch;
  static DateTime? _ts(Object? us) => us == null
      ? null
      : DateTime.fromMicrosecondsSinceEpoch(us as int, isUtc: true);

  static StoredConfig _map(Row r) {
    final raw = r['payload'] as String;
    return StoredConfig(
      // Já validada na gravação; reparse garante o mesmo modelo.
      config: PresenceConfig.parse(jsonDecode(raw),
          expectedLinkId: r['employment_link_id'] as String),
      rawJson: raw,
      receivedAt: _ts(r['received_at_us'])!,
      persistedAt: _ts(r['persisted_at_us'])!,
      stage: ApplyStage.values.byName(r['stage'] as String),
      appliedAt: _ts(r['applied_at_us']),
      applyDetail: r['apply_detail'] as String?,
      supersededAt: _ts(r['superseded_at_us']),
      applyEventId: r['apply_event_id'] as String?,
      expiredEventId: r['expired_event_id'] as String?,
    );
  }
}
