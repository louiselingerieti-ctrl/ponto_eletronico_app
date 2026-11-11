import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'integration/backend/backend_auth_gateway.dart';
import 'integration/backend/backend_config.dart';
import 'integration/backend/session_store.dart';

/// App do colaborador Casa do Futuro.
/// - Com --dart-define=API_BASE_URL=https://…: login REAL no backend
///   (Android). Sem isso: modo DEMONSTRAÇÃO.
/// - Detecções, áreas e solicitações continuam SIMULADAS nos dois modos
///   (rotas ainda não existem no backend). Não pede localização e não gera
///   ponto oficial.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final base = BackendConfig.baseUrl;
  final services = AppServices(
    auth: base == null ? null : BackendAuthGateway(baseUrl: base, store: SecureSessionStore()),
  );
  runApp(CasaFuturoApp(services: services));
  unawaited(services.init());
}
