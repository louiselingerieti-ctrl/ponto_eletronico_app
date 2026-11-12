import '../registration/registration_models.dart';
import 'punch_controller.dart';

/// + Registrar no modo REAL: GPS, câmera e servidor de verdade, pelo
/// [PunchController].
class PunchRegistrationPort implements RegistrationPort {
  PunchRegistrationPort(this._punch, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final PunchController _punch;
  final DateTime Function() _now;

  @override
  bool get simulated => false;

  @override
  DateTime now() => _now();

  @override
  Duration get evidenceValidity => _punch.evidenceValidity;

  @override
  Future<LocationCheck> validateLocation() => _punch.validateLocation();

  @override
  Future<PhotoResult> takePhoto() => _punch.takePhoto();

  @override
  Future<CommitOutcome> commit(RegistrationDraft draft) => _punch.commit(draft);
}
