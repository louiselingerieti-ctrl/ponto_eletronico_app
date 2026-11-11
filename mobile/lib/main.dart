import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'integration/backend/backend_auth_gateway.dart';
import 'integration/backend/backend_config.dart';
import 'integration/backend/session_store.dart';
import 'integration/google/google_id_token_source.dart';

/// App do colaborador Casa do Futuro.
/// - Com --dart-define=API_BASE_URL=https://…: login REAL no backend
///   (Android). Sem isso: modo DEMONSTRAÇÃO.
/// - Com --dart-define=GOOGLE_SERVER_CLIENT_ID=… também: botão "Entrar com
///   Google" (só para conta já cadastrada pelo RH).
/// - Detecções, áreas e solicitações continuam SIMULADAS nos dois modos
///   (rotas ainda não existem no backend). Não pede localização e não gera
///   ponto oficial.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final base = BackendConfig.baseUrl;
  final googleClientId = BackendConfig.googleServerClientId;
  final services = AppServices(
    auth: base == null ? null : BackendAuthGateway(baseUrl: base, store: SecureSessionStore()),
    google: googleClientId == null ? null : PluginGoogleIdTokenSource(serverClientId: googleClientId),
  );
  runApp(CasaFuturoApp(services: services));
  unawaited(services.init());
}
