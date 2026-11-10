import '../domain/clock_quality.dart';
import '../domain/presence_config.dart';
import 'ports.dart';

enum ApplyStage { persisted, applied, applyFailed }

class StoredConfig {
  const StoredConfig({
    required this.config,
    required this.rawJson,
    required this.receivedAt,
    required this.persistedAt,
    required this.stage,
    this.appliedAt,
    this.applyDetail,
    this.supersededAt,
    this.applyEventId,
    this.expiredEventId,
  });

  final PresenceConfig config;
  final String rawJson;
  final DateTime receivedAt;
  final DateTime persistedAt;
  final ApplyStage stage;
  final DateTime? appliedAt;
  final String? applyDetail;
  final DateTime? supersededAt;
  final String? applyEventId;
  final String? expiredEventId;
}

class Revocation {
  const Revocation(this.employmentLinkId, this.revokedAt, this.reason);
  final String employmentLinkId;
  final DateTime revokedAt;
  final String reason;
}

/// Configuração e revogações por vínculo.
abstract interface class ConfigRepository {
  StoredConfig? current(String linkId);
  StoredConfig? byRevision(String linkId, String revision);
  List<StoredConfig> history(String linkId);

  /// Grava como atual e marca a anterior como substituída (mesma transação).
  void insertCurrent(
    PresenceConfig c, {
    required String rawJson,
    required DateTime receivedAt,
    required DateTime persistedAt,
    required ServerTimeReference? reference,
  });

  void setApplyResult(String linkId, String revision,
      {required ApplyStage stage, required DateTime at, String? detail, String? eventId});

  void setExpiredEvent(String linkId, String revision, String eventId);
  ServerTimeReference? latestClockReference();
  Revocation? activeRevocation(String linkId);
  void revoke(String linkId, {required String reason, required DateTime at});
  void liftRevocation(String linkId, {required DateTime at});
}

/// Persistência local usada pelos casos de uso.
///
/// Implementações:
/// - `LocalStore` (`presenca_core_native.dart`): SQLite **sempre cifrado**,
///   a única aceita para dados reais;
/// - `InMemoryLabPersistence` (`presenca_lab.dart`): SÓ para laboratório e
///   testes; não persiste, não cifra e se apaga ao recarregar.
abstract interface class LocalPersistence {
  /// Transação atômica; pode ser aninhada (savepoint).
  T tx<T>(T Function() body);
  EventQueue get queue;
  ConfigRepository get configs;
  String get installationId;

  /// `true` somente quando os dados ficam cifrados em disco.
  bool get isEncryptedAtRest;
}
