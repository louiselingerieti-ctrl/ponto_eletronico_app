import 'dart:convert';

import 'package:presenca_core/presenca_lab.dart';

/// ================================================================
///  CENÁRIO FICTÍCIO — exclusivo do laboratório.
/// ================================================================
/// Pessoa, empresa, vínculo, área e parâmetros são inventados. Nenhum valor
/// aqui é decisão aprovada (raio, tolerância, validade e backoff são
/// pendentes; ver docs/diagnostico-e-plano.md).
abstract final class LabScenario {
  static const appVersion = '0.1.0-lab';
  static const timeZone = 'America/Sao_Paulo';

  static const personName = 'Pessoa Fictícia 01';
  static const companyName = 'Empresa Sintética Ltda';
  static const linkId = '00000000-0000-4000-8000-00000000e001';

  static const areaId = '00000000-0000-4000-8000-0000000000f1';
  static const areaLabel = 'Unidade Sintética Centro';
  static const areaRadiusMeters = 150; // fictício
  static const configRevision = 'cfg-1';

  /// Fictício: tolerância e idade da referência do relógio (D-CLK-1).
  static const clockPolicy = ClockQualityPolicy(
      tolerance: Duration(seconds: 5), maxReferenceAge: Duration(hours: 12));

  /// Fictício: 5 s dobrando até 30 min.
  static Backoff backoff() =>
      Backoff(base: const Duration(seconds: 5), cap: const Duration(minutes: 30));

  /// Configuração no formato do rascunho `presenca-v1`, com dados fictícios
  /// e coordenadas perto de 0,0 (não correspondem a nenhum local real).
  static String configJson(DateTime serverTime) => jsonEncode({
        'employmentLinkId': linkId,
        'configRevision': configRevision,
        'policyRevision': 'pol-lab-1',
        'serverTime': serverTime.toUtc().toIso8601String(),
        'validUntil': serverTime.toUtc().add(const Duration(hours: 24)).toIso8601String(),
        'areas': [
          {
            'areaId': areaId,
            'revision': 1,
            'label': areaLabel,
            'kind': 'establishment',
            'center': {'latitude': 0.0012, 'longitude': 0.0034},
            'radiusMeters': areaRadiusMeters,
            'validFrom': '2026-01-01T00:00:00.000Z',
            'validTo': null,
          }
        ],
        'detection': {'maxFixAgeSeconds': 120, 'maxAccuracyMeters': 100, 'dwellSeconds': 0},
        'manualPunch': {'allowed': false, 'reasonRequired': true, 'locationRequired': false},
        'offline': {'maxEventAgeHours': 24, 'maxQueuedEvents': 500},
      });
}
