import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

/// Chave de 32 bytes da base local. Em produção virá do armazenamento seguro
/// do SO (Keystore/Keychain) via [KeyProvider] — ainda não implementado.
/// Nunca aparece em `toString`, log ou mensagem de erro.
final class EncryptionKey {
  EncryptionKey._(this._bytes);

  factory EncryptionKey.fromBytes(List<int> bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('a chave deve ter exatamente 32 bytes');
    }
    if (bytes.every((b) => b == 0)) {
      throw ArgumentError('chave nula recusada');
    }
    if (bytes.any((b) => b < 0 || b > 255)) {
      throw ArgumentError('byte fora do intervalo');
    }
    return EncryptionKey._(Uint8List.fromList(bytes));
  }

  final Uint8List _bytes;

  String get _hex =>
      _bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  String toString() => 'EncryptionKey(***)';
}

/// Fonte da chave (armazenamento seguro). Deve lançar se a chave não puder ser
/// obtida; nunca devolver uma chave substituta.
abstract interface class KeyProvider {
  EncryptionKey obtainKey();
}

/// A base cifrada não pôde ser aberta ou verificada. Nada foi gravado.
final class EncryptionUnavailable implements Exception {
  const EncryptionUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'EncryptionUnavailable: $reason';
}

/// Única porta de entrada para a base que guarda eventos e configuração.
///
/// Não existe modo sem cifra: sem chave válida, sem SQLite3MultipleCiphers
/// ativo ou com arquivo legível em claro, a abertura falha antes de qualquer
/// gravação. Também não aceita base em memória (não é persistência).
final class EncryptedDatabase {
  EncryptedDatabase._(this._db, this.path);

  static const _plainHeader = 'SQLite format 3\u0000';

  final Database _db;
  final String path;
  int _depth = 0;
  int _savepoint = 0;

  /// [obtainKey] é obrigatório e chamado antes de tocar no arquivo; se lançar,
  /// nada é aberto nem criado.
  static EncryptedDatabase open(String path, EncryptionKey Function() obtainKey) {
    if (path.isEmpty || path == ':memory:' || path.startsWith('file:')) {
      throw ArgumentError('é exigido um caminho de arquivo comum');
    }
    final EncryptionKey key;
    try {
      key = obtainKey();
    } catch (e) {
      throw EncryptionUnavailable('chave indisponível (${e.runtimeType})');
    }

    final existed = File(path).existsSync() && File(path).lengthSync() > 0;
    if (existed && _hasPlainHeader(path)) {
      throw const EncryptionUnavailable('arquivo existente não está cifrado');
    }

    final Database db;
    try {
      db = sqlite3.open(path);
    } on SqliteException catch (e) {
      throw EncryptionUnavailable('falha ao abrir (${e.resultCode})');
    }
    try {
      // Precisa ser o primeiro comando da conexão.
      db.execute("PRAGMA hexkey = '${key._hex}';");
      // Prova de que a biblioteca de cifra está carregada: sem ela, a
      // PRAGMA acima seria ignorada em silêncio e o arquivo ficaria em claro.
      db.select('SELECT sqlite3mc_version() AS v;');
      final cipher = db.select('PRAGMA cipher;');
      if (cipher.isEmpty || '${cipher.first.values.first}'.isEmpty) {
        throw const EncryptionUnavailable('cifra não informada');
      }
      // Falha com chave errada ou arquivo corrompido.
      db.select('SELECT count(*) FROM sqlite_master;');
      db.execute('PRAGMA journal_mode = WAL;');
      db.execute('PRAGMA synchronous = FULL;');
      db.execute('PRAGMA foreign_keys = ON;');
      db.execute('PRAGMA busy_timeout = 5000;');
    } on EncryptionUnavailable {
      db.close();
      rethrow;
    } on SqliteException catch (e) {
      db.close();
      throw EncryptionUnavailable('verificação da cifra falhou (${e.resultCode})');
    }
    return EncryptedDatabase._(db, path);
  }

  /// Depois de criar o esquema: força a escrita no arquivo principal e confere
  /// que o cabeçalho não é o de um SQLite em claro.
  void verifyAtRest() {
    _db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    if (_hasPlainHeader(path)) {
      throw const EncryptionUnavailable('arquivo gravado em claro');
    }
  }

  static bool _hasPlainHeader(String path) {
    final f = File(path);
    if (!f.existsSync() || f.lengthSync() < 16) return false;
    final raf = f.openSync();
    try {
      final head = raf.readSync(16);
      return String.fromCharCodes(head) == _plainHeader;
    } finally {
      raf.closeSync();
    }
  }

  /// Transação com aninhamento por SAVEPOINT: casos de uso podem compor
  /// operações de repositórios diferentes num único commit.
  T tx<T>(T Function() body) {
    if (_depth == 0) {
      _db.execute('BEGIN IMMEDIATE;');
      _depth++;
      try {
        final r = body();
        _db.execute('COMMIT;');
        return r;
      } catch (_) {
        _db.execute('ROLLBACK;');
        rethrow;
      } finally {
        _depth--;
      }
    }
    final name = 'sp${++_savepoint}';
    _db.execute('SAVEPOINT $name;');
    _depth++;
    try {
      final r = body();
      _db.execute('RELEASE $name;');
      return r;
    } catch (_) {
      _db.execute('ROLLBACK TO $name; RELEASE $name;');
      rethrow;
    } finally {
      _depth--;
    }
  }

  bool get inTransaction => _depth > 0;

  void execute(String sql, [List<Object?> params = const []]) =>
      _db.execute(sql, params);

  ResultSet select(String sql, [List<Object?> params = const []]) =>
      _db.select(sql, params);

  int get updatedRows => _db.updatedRows;

  void close() => _db.close();
}
