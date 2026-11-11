/// Armazenamento real do app: SQLite com SQLite3MultipleCiphers, SEMPRE
/// cifrado (sem modo em claro). Requer `dart:io`/FFI: não compila para a web.
library;

export 'presenca_core.dart';
export 'src/adapters/encrypted_database.dart'
    show EncryptionKey, EncryptionUnavailable, KeyProvider, EncryptedDatabase;
export 'src/adapters/local_store.dart';
export 'src/adapters/sqlite_config_store.dart';
export 'src/adapters/sqlite_event_queue.dart';
