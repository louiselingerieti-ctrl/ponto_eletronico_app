import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'integration/backend/backend_auth_gateway.dart';
import 'features/punch/punch_controller.dart';
import 'integration/backend/backend_config.dart';
import 'integration/backend/backend_punch_gateway.dart';
import 'integration/backend/session_store.dart';
import 'integration/device/camera_selfie.dart';
import 'integration/device/geolocator_location_source.dart';
import 'integration/device/local_punch_reminders.dart';
import 'integration/google/google_id_token_source.dart';

/// App do colaborador Casa do Futuro.
/// - Com --dart-define=API_BASE_URL=https://…: login REAL no backend
///   (Android). Sem isso: modo DEMONSTRAÇÃO.
/// - Com --dart-define=GOOGLE_SERVER_CLIENT_ID=… também: botão "Entrar com
///   Google" (só para conta já cadastrada pelo RH).
/// - No modo real, o PONTO é de verdade: localização (uma leitura, só na
///   hora do registro) + selfie, com aviso no horário da escala.
/// - Histórico de detecções, áreas e solicitações continuam SIMULADOS nos
///   dois modos. O registro ainda não é ponto oficial para fins legais.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final base = BackendConfig.baseUrl;
  final googleClientId = BackendConfig.googleServerClientId;
  final store = SecureSessionStore();
  final services = AppServices(
    auth: base == null ? null : BackendAuthGateway(baseUrl: base, store: store),
    punch: base == null
        ? null
        : PunchDeps(
            gateway: BackendPunchGateway(baseUrl: base, store: store),
            location: const GeolocatorLocationSource(),
            camera: CameraSelfie(),
            reminders: LocalPunchReminders(),
          ),
    google: googleClientId == null ? null : PluginGoogleIdTokenSource(serverClientId: googleClientId),
  );
  runApp(CasaFuturoApp(services: services));
  unawaited(services.init());
}
