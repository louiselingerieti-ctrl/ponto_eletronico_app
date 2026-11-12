import '../features/punch/punch_models.dart';
import '../features/registration/registration_models.dart';
import 'demo_backend.dart';

/// ================================================================
///  + REGISTRAR SIMULADO — demonstração, dados fictícios.
/// ================================================================
/// Não lê GPS, não abre câmera e não fala com o servidor. A "localização" é
/// validada na Loja Centro (ou recusada se a permissão simulada estiver
/// desligada), a "foto" é uma ilustração e o ponto fica só em memória.
class DemoRegistrationPort implements RegistrationPort {
  DemoRegistrationPort(this._backend);

  /// Lido a cada uso: a demonstração é recriada a cada saída da conta.
  final DemoBackend Function() _backend;

  static const _wait = Duration(milliseconds: 900);

  @override
  bool get simulated => true;

  @override
  DateTime now() => _backend().now();

  @override
  Duration get evidenceValidity => const Duration(minutes: 5);

  @override
  Future<LocationCheck> validateLocation() async {
    await Future<void>.delayed(_wait);
    final b = _backend();
    if (!b.locationGranted) return const LocationCheck.failed(LocationFailure.denied);
    return LocationCheck.ok(ValidatedLocation(
      areaName: b.profile.areaLabel,
      companyName: b.profile.company,
      at: b.now(),
      suggested: b.nextManualIsEntry ? PunchKind.entry : PunchKind.exit,
    ));
  }

  @override
  Future<PhotoResult> takePhoto() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return PhotoResult.ok(CapturedPhoto(at: _backend().now()));
  }

  /// Demonstração: não há configurações reais a abrir.
  @override
  Future<void> openAppSettings() async {}

  @override
  Future<CommitOutcome> commit(RegistrationDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final b = _backend();
    final p = b.addManualPunch(isEntry: draft.kind == PunchKind.entry, area: draft.location.areaName, clientId: draft.attemptId);
    return CommitOutcome.ok(RegistrationReceipt(kind: draft.kind, recordedAt: p.at, areaName: p.area, received: false));
  }
}
