import 'package:uuid/uuid.dart';

import '../application/persistence.dart';

import 'encrypted_database.dart';
import 'sqlite_config_store.dart';
import 'sqlite_event_queue.dart';

/// Base local do app: fila de eventos + configuração, SEMPRE cifrada.
///
/// Não há forma de obter a fila ou a configuração sem passar por aqui, e não
/// há parâmetro para desligar a cifra. Falha de chave ou de cifra impede a
/// abertura — e, portanto, qualquer gravação.
class LocalStore implements LocalPersistence {
  LocalStore._(this.db, this.queue, this.configs);

  final EncryptedDatabase db;
  @override
  final SqliteEventQueue queue;
  @override
  final SqliteConfigStore configs;

  @override
  T tx<T>(T Function() body) => db.tx(body);

  /// Verificado na abertura (`EncryptedDatabase.open` + `verifyAtRest`).
  @override
  bool get isEncryptedAtRest => true;

  /// 1 = prova de conceito anterior (fa53e9c), sem cifra obrigatória e sem
  /// lease_token. Não há migração: base v1 é recusada com mensagem explícita.
  static const schemaVersion = 2;

  /// [installationId] só é usado na criação; depois vale o gravado.
  static LocalStore open(
    String path, {
    required EncryptionKey Function() obtainKey,
    String? installationId,
  }) {
    final db = EncryptedDatabase.open(path, obtainKey);
    try {
      db.tx(() {
        db.execute('''
          CREATE TABLE IF NOT EXISTS meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
          ) STRICT;
        ''');
        db.execute(
            "INSERT OR IGNORE INTO meta (key, value) VALUES ('installation_id', ?)",
            [installationId ?? const Uuid().v4()]);
        final v = db.select("SELECT value FROM meta WHERE key = 'schema_version'");
        if (v.isNotEmpty && v.first['value'] != '$schemaVersion') {
          throw StateError('versão de esquema local sem migração: ${v.first['value']}');
        }
        db.execute("INSERT OR IGNORE INTO meta (key, value) "
            "VALUES ('schema_version', '$schemaVersion')");
        SqliteEventQueue.migrate(db);
        SqliteConfigStore.migrate(db);
      });
      db.verifyAtRest();
    } catch (_) {
      db.close();
      rethrow;
    }
    return LocalStore._(db, SqliteEventQueue(db), SqliteConfigStore(db));
  }

  @override
  String get installationId => db
      .select("SELECT value FROM meta WHERE key = 'installation_id'")
      .first['value'] as String;

  void close() => db.close();
}
