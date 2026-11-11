import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Onde o cookie de sessão fica guardado. Nunca guarda a senha.
abstract interface class SessionStore {
  Future<String?> read();
  Future<void> write(String cookie);
  Future<void> clear();
}

/// Armazenamento seguro do SO (Android: Keystore). O conteúdo não vai para
/// backup na nuvem nem para logs.
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  static const _key = 'cdf.session.cookie';

  @override
  Future<String?> read() => _s.read(key: _key);

  @override
  Future<void> write(String cookie) => _s.write(key: _key, value: cookie);

  @override
  Future<void> clear() => _s.delete(key: _key);
}

/// Só para testes.
class MemorySessionStore implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String cookie) async => value = cookie;
  @override
  Future<void> clear() async => value = null;
}
