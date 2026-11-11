/// Qualidade do relógio do aparelho.
///
/// Princípios:
/// - O horário do aparelho (`wall`) é PRESERVADO como informado. Nada aqui
///   corrige, estima ou substitui horários.
/// - `trusted` só com evidência: referência do servidor no MESMO boot,
///   relógio monotônico consistente, referência recente e desvio, somado à
///   incerteza da referência, dentro da tolerância.
/// - Sem evidência suficiente o resultado é `uncertain`, nunca `trusted`.
/// - O servidor reavalia por conta própria; o rótulo do app é só indício.
library;

import 'package:meta/meta.dart';

import 'presence_event.dart';

/// Leitura dos relógios no instante em que o app tomou conhecimento de algo.
/// `elapsedRealtimeMs` e `bootId` ficam `null` quando a plataforma não os
/// fornece — nunca são inventados.
@immutable
class ClockSample {
  const ClockSample({required this.wall, this.elapsedRealtimeMs, this.bootId});

  final DateTime wall;
  final int? elapsedRealtimeMs;
  final String? bootId;
}

/// Referência obtida de uma resposta do servidor (`serverTime` da
/// configuração). O servidor gerou o horário em algum ponto entre o envio e o
/// recebimento: a incerteza é o tempo de ida e volta.
@immutable
class ServerTimeReference {
  const ServerTimeReference({
    required this.serverTime,
    required this.elapsedAtReceiptMs,
    required this.bootId,
    required this.roundTrip,
  });

  final DateTime serverTime;
  final int elapsedAtReceiptMs;
  final String bootId;
  final Duration roundTrip;
}

/// Limiares da avaliação. PROVISÓRIOS e sem valor padrão: dependem de
/// decisão (D-CLK-1) e de alinhamento com o backend, que reavalia.
@immutable
class ClockQualityPolicy {
  const ClockQualityPolicy({
    required this.tolerance,
    required this.maxReferenceAge,
  });

  final Duration tolerance;
  final Duration maxReferenceAge;
}

enum ClockReason {
  noReference,
  noMonotonic,
  noBootId,
  bootChanged,
  monotonicRegressed,
  referenceTooOld,
  withinTolerance,
  exceedsTolerance,
  inconclusive,
}

@immutable
class ClockAssessment {
  const ClockAssessment(this.quality, this.reasons, {this.deviation, this.bound});

  final ClockQuality quality;
  final Set<ClockReason> reasons;

  /// Relógio do aparelho menos o horário estimado do servidor.
  final Duration? deviation;

  /// Incerteza da estimativa (ida e volta da referência).
  final Duration? bound;
}

ClockAssessment assessClock(
  ClockSample sample,
  ServerTimeReference? ref,
  ClockQualityPolicy policy,
) {
  if (ref == null) {
    return const ClockAssessment(ClockQuality.uncertain, {ClockReason.noReference});
  }
  final missing = <ClockReason>{
    if (sample.elapsedRealtimeMs == null) ClockReason.noMonotonic,
    if (sample.bootId == null) ClockReason.noBootId,
  };
  if (missing.isNotEmpty) return ClockAssessment(ClockQuality.uncertain, missing);
  if (sample.bootId != ref.bootId) {
    // Reinício invalida a comparação monotônica.
    return const ClockAssessment(ClockQuality.uncertain, {ClockReason.bootChanged});
  }
  final sinceRefMs = sample.elapsedRealtimeMs! - ref.elapsedAtReceiptMs;
  if (sinceRefMs < 0) {
    return const ClockAssessment(
        ClockQuality.uncertain, {ClockReason.monotonicRegressed});
  }
  final estimatedServer = ref.serverTime.add(Duration(milliseconds: sinceRefMs));
  final deviation = sample.wall.difference(estimatedServer);
  final bound = ref.roundTrip;
  if (Duration(milliseconds: sinceRefMs) > policy.maxReferenceAge) {
    return ClockAssessment(ClockQuality.uncertain, const {ClockReason.referenceTooOld},
        deviation: deviation, bound: bound);
  }
  final absDev = deviation.abs();
  if (absDev + bound <= policy.tolerance) {
    return ClockAssessment(ClockQuality.trusted, const {ClockReason.withinTolerance},
        deviation: deviation, bound: bound);
  }
  if (absDev - bound > policy.tolerance) {
    return ClockAssessment(
        ClockQuality.driftSuspected, const {ClockReason.exceedsTolerance},
        deviation: deviation, bound: bound);
  }
  return ClockAssessment(ClockQuality.uncertain, const {ClockReason.inconclusive},
      deviation: deviation, bound: bound);
}

/// Salto do relógio de parede entre duas leituras do MESMO boot (troca
/// manual de hora, por exemplo). `null` = não dá para afirmar nada.
Duration? wallClockJump(ClockSample a, ClockSample b, Duration tolerance) {
  if (a.bootId == null || a.bootId != b.bootId) return null;
  if (a.elapsedRealtimeMs == null || b.elapsedRealtimeMs == null) return null;
  final mono = Duration(milliseconds: b.elapsedRealtimeMs! - a.elapsedRealtimeMs!);
  if (mono.isNegative) return null;
  final wall = b.wall.difference(a.wall);
  final jump = wall - mono;
  return jump.abs() > tolerance ? jump : Duration.zero;
}

/// Monta o `DeviceClock` do contrato preservando a leitura original.
DeviceClock stampDeviceClock(
  ClockSample sample,
  ClockAssessment assessment, {
  required String timeZone,
}) =>
    DeviceClock(
      detectedAt: sample.wall,
      elapsedRealtimeMs: sample.elapsedRealtimeMs,
      bootId: sample.bootId,
      timeZone: timeZone,
      quality: assessment.quality,
    );
