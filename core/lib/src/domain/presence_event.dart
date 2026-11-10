/// Eventos de presença do contrato `presenca-v1` (RASCUNHO do backend,
/// `docs/contratos/presenca-v1.openapi.yaml`, schemaVersion 1).
///
/// Presença NÃO é marcação de jornada. Nada aqui classifica início, fim ou
/// intervalo; isso depende de política versionada no backend (D-JOR-1).
///
/// `manual_punch` fica fora desta prova de conceito: a política da
/// contingência manual ainda não foi definida (D-JOR-2).
library;

import 'package:meta/meta.dart';

const int contractSchemaVersion = 1;

enum Transition { enter, exit, dwell }

enum ObservedAtSource { osTriggeringFix, none }

enum LocationProvider { gps, network, fused, unknown }

enum ClockQuality { trusted, driftSuspected, uncertain }

enum DetectionStatus {
  geofencesRegistered,
  geofenceRegistrationFailed,
  locationPermissionDenied,
  backgroundLocationRevoked,
  locationServicesDisabled,
  batteryRestrictionDetected,
  appRestarted,
  configApplied,
  configExpired,
  clockChangeDetected,
}

/// Leitura de localização informada pelo SO junto com a transição.
/// Nunca é construída pelo app a partir de estimativa: se o SO não deu a
/// leitura, o evento vai sem `location`.
@immutable
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.provider,
    this.fixedAt,
    this.mockReported,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final LocationProvider provider;

  /// Instante da leitura segundo o SO. `null` se o SO não informa.
  final DateTime? fixedAt;

  /// Sinal do SO de localização simulada. `null` = SO não informa.
  /// É indício, não prova.
  final bool? mockReported;

  Map<String, Object?> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'fixedAt': fixedAt?.toUtc().toIso8601String(),
        'provider': provider.name,
        'mockReported': mockReported,
      };
}

/// Relógio do aparelho no momento em que o APP tomou conhecimento.
/// Não é prova de horário (o relógio pode estar alterado).
@immutable
class DeviceClock {
  const DeviceClock({
    required this.detectedAt,
    required this.elapsedRealtimeMs,
    required this.bootId,
    required this.timeZone,
    required this.quality,
  });

  /// Relógio de parede do aparelho, exatamente como lido. Nunca corrigido.
  final DateTime detectedAt;

  /// `null` quando a plataforma não fornece. ALINHAR: o rascunho
  /// `presenca-v1` exige os dois campos; o app não os inventa.
  final int? elapsedRealtimeMs;
  final String? bootId;
  final String timeZone;
  final ClockQuality quality;

  Map<String, Object?> toJson() => {
        'detectedAt': detectedAt.toUtc().toIso8601String(),
        'elapsedRealtimeMs': elapsedRealtimeMs,
        'bootId': bootId,
        'timeZone': timeZone,
        'quality': _qualityWire[quality],
      };

  static const _qualityWire = {
    ClockQuality.trusted: 'trusted',
    ClockQuality.driftSuspected: 'drift_suspected',
    ClockQuality.uncertain: 'uncertain',
  };
}

/// Dados de um evento antes de ser salvo. `eventId` e `installationSequence`
/// são atribuídos pela fila, dentro da mesma transação que o persiste.
sealed class PresenceEventDraft {
  const PresenceEventDraft({
    required this.employmentLinkId,
    required this.configRevision,
    required this.appVersion,
    required this.clock,
  });

  final String employmentLinkId;
  final String configRevision;
  final String appVersion;
  final DeviceClock clock;

  String get kind;

  Map<String, Object?> kindFieldsToJson();

  /// Forma de fio completa (contrato v1). Gerada UMA vez, na gravação; o
  /// reenvio usa exatamente os mesmos bytes, para o servidor responder
  /// `duplicate` e não `conflict`.
  Map<String, Object?> toContractJson({
    required String eventId,
    required int installationSequence,
  }) =>
      {
        'eventId': eventId,
        'schemaVersion': contractSchemaVersion,
        'kind': kind,
        'installationSequence': installationSequence,
        'employmentLinkId': employmentLinkId,
        'configRevision': configRevision,
        'appVersion': appVersion,
        'clock': clock.toJson(),
        ...kindFieldsToJson(),
      };
}

final class AreaTransitionDraft extends PresenceEventDraft {
  AreaTransitionDraft({
    required super.employmentLinkId,
    required super.configRevision,
    required super.appVersion,
    required super.clock,
    required this.areaId,
    required this.areaRevision,
    required this.transition,
    this.observedAt,
    this.location,
  }) {
    if (areaRevision < 1) {
      throw ArgumentError.value(areaRevision, 'areaRevision', 'deve ser >= 1');
    }
  }

  final String areaId;
  final int areaRevision;
  final Transition transition;

  /// Melhor instante observado que o SO forneceu (a leitura que disparou a
  /// transição). NÃO é o instante de cruzamento da borda e nunca é estimado.
  final DateTime? observedAt;
  final LocationFix? location;

  @override
  String get kind => 'area_transition';

  @override
  Map<String, Object?> kindFieldsToJson() => {
        'areaId': areaId,
        'areaRevision': areaRevision,
        'transition': transition.name,
        'observedAt': observedAt?.toUtc().toIso8601String(),
        'observedAtSource': observedAt == null ? 'none' : 'os_triggering_fix',
        // Omitido quando não há leitura: nunca enviar coordenada inventada.
        if (location != null) 'location': location!.toJson(),
      };
}

final class DetectionStatusDraft extends PresenceEventDraft {
  const DetectionStatusDraft({
    required super.employmentLinkId,
    required super.configRevision,
    required super.appVersion,
    required super.clock,
    required this.status,
    this.detail,
  });

  final DetectionStatus status;
  final String? detail;

  @override
  String get kind => 'detection_status';

  @override
  Map<String, Object?> kindFieldsToJson() => {
        'status': _snake(status.name),
        'detail': detail,
      };
}

String _snake(String camel) => camel.replaceAllMapped(
    RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
