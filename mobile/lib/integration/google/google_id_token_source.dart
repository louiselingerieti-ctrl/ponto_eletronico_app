import 'package:google_sign_in/google_sign_in.dart';

import '../../features/session/session_models.dart';

/// Identidade do Google pelo plugin oficial (Android: Credential Manager).
///
/// O app só pede a IDENTIDADE: nenhum escopo extra, nenhum acesso a dados do
/// Google. O ID token sai com público (aud) = [serverClientId], que é o client
/// ID "Aplicativo da Web" configurado na API; é ela quem valida o token.
/// O token nunca é guardado nem registrado em log.
///
/// Pré-requisito no Google Cloud (mesmo projeto do client da API): um client
/// OAuth do tipo Android com o pacote do app e o SHA-1 da chave que assina o
/// APK. Sem ele o Google recusa (clientConfigurationError).
class PluginGoogleIdTokenSource implements GoogleIdTokenSource {
  PluginGoogleIdTokenSource({required this.serverClientId});

  final String serverClientId;
  Future<void>? _ready;

  Future<void> _init() => _ready ??= GoogleSignIn.instance.initialize(serverClientId: serverClientId);

  @override
  Future<String?> idToken() async {
    try {
      await _init();
      final google = GoogleSignIn.instance;
      if (!google.supportsAuthenticate()) throw const AuthException(AuthFailure.googleUnavailable);
      final account = await google.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) throw const AuthException(AuthFailure.googleUnavailable);
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      // Inicialização que falhou pode ser tentada de novo no próximo toque.
      _ready = null;
      throw const AuthException(AuthFailure.googleUnavailable);
    } on AuthException {
      rethrow;
    } catch (_) {
      _ready = null;
      throw const AuthException(AuthFailure.googleUnavailable);
    }
  }

  @override
  Future<void> signOut() async {
    await _init();
    await GoogleSignIn.instance.signOut();
  }
}
