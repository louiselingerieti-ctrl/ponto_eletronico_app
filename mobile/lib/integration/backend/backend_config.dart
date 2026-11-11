import 'package:flutter/foundation.dart' show kIsWeb;

/// Endereço do backend REAL, definido no build:
///   flutter build apk --dart-define=API_BASE_URL=https://(endereço-do-servidor)
/// Sem ele, o app abre em modo DEMONSTRAÇÃO (nada real, nada enviado).
/// Na web o login real fica desligado: o cookie de sessão entre domínios
/// depende de configuração do backend que ainda não existe.
abstract final class BackendConfig {
  static const _raw = String.fromEnvironment('API_BASE_URL');

  static Uri? get baseUrl {
    if (kIsWeb || _raw.isEmpty) return null;
    final u = Uri.tryParse(_raw);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
    return u;
  }

  static bool get realLogin => baseUrl != null;
}
