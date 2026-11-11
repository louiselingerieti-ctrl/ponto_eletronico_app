import 'package:presenca_core/presenca_core_native.dart';
import 'package:presenca_core/presenca_lab.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final server = DateTime.utc(2026, 11, 10, 11);
  final ref = ServerTimeReference(
      serverTime: server, elapsedAtReceiptMs: 1000000, bootId: 'boot-1',
      roundTrip: const Duration(milliseconds: 400));

  ClockSample at(Duration afterRef, {Duration skew = Duration.zero, String? boot = 'boot-1',
          bool mono = true}) =>
      ClockSample(
        wall: server.add(afterRef).add(skew),
        elapsedRealtimeMs: mono ? 1000000 + afterRef.inMilliseconds : null,
        bootId: boot,
      );

  ClockQuality q(ClockSample s, [ServerTimeReference? r]) =>
      assessClock(s, r, testClockPolicy).quality;

  test('sem referência do servidor: incerto (nunca confiável por padrão)', () {
    final a = assessClock(at(Duration.zero), null, testClockPolicy);
    expect(a.quality, ClockQuality.uncertain);
    expect(a.reasons, {ClockReason.noReference});
  });

  test('sem monotônico ou sem boot: incerto', () {
    expect(assessClock(at(Duration.zero, mono: false), ref, testClockPolicy).reasons,
        {ClockReason.noMonotonic});
    expect(assessClock(at(Duration.zero, boot: null), ref, testClockPolicy).reasons,
        {ClockReason.noBootId});
  });

  test('boot diferente: incerto (reinício invalida a comparação)', () {
    expect(assessClock(at(const Duration(minutes: 5), boot: 'boot-2'), ref, testClockPolicy)
        .reasons, {ClockReason.bootChanged});
  });

  test('monotônico regrediu no mesmo boot: incerto', () {
    final s = ClockSample(wall: server, elapsedRealtimeMs: 10, bootId: 'boot-1');
    expect(assessClock(s, ref, testClockPolicy).reasons, {ClockReason.monotonicRegressed});
  });

  test('mesmo boot e desvio + incerteza dentro da tolerância: confiável', () {
    final a = assessClock(at(const Duration(hours: 1), skew: const Duration(seconds: 2)),
        ref, testClockPolicy);
    expect(a.quality, ClockQuality.trusted);
    expect(a.deviation, const Duration(seconds: 2));
    expect(a.bound, const Duration(milliseconds: 400));
  });

  test('relógio adiantado 2 h: suspeita de desvio', () {
    expect(q(at(const Duration(hours: 1), skew: const Duration(hours: 2)), ref),
        ClockQuality.driftSuspected);
  });

  test('desvio na faixa da incerteza: inconclusivo → incerto', () {
    final a = assessClock(
        at(const Duration(minutes: 1), skew: const Duration(milliseconds: 4800)),
        ref, testClockPolicy);
    expect(a.quality, ClockQuality.uncertain);
    expect(a.reasons, {ClockReason.inconclusive});
  });

  test('referência velha demais: incerto mesmo sem desvio', () {
    expect(assessClock(at(const Duration(hours: 13)), ref, testClockPolicy).reasons,
        {ClockReason.referenceTooOld});
  });

  test('o carimbo preserva exatamente a leitura do aparelho', () {
    final s = at(const Duration(hours: 1), skew: const Duration(hours: 2));
    final c = stampDeviceClock(s, assessClock(s, ref, testClockPolicy),
        timeZone: 'America/Sao_Paulo');
    expect(c.detectedAt, s.wall); // não "corrige" o relógio
    expect(c.elapsedRealtimeMs, s.elapsedRealtimeMs);
    expect(c.bootId, 'boot-1');
    expect(c.quality, ClockQuality.driftSuspected);
  });

  test('salto do relógio de parede no mesmo boot', () {
    final a = at(Duration.zero);
    final b = ClockSample(
        wall: a.wall.add(const Duration(hours: 1, minutes: 1)),
        elapsedRealtimeMs: a.elapsedRealtimeMs! + 60000, bootId: 'boot-1');
    expect(wallClockJump(a, b, const Duration(seconds: 5)), const Duration(hours: 1));
    expect(wallClockJump(a, at(const Duration(minutes: 1)), const Duration(seconds: 5)),
        Duration.zero);
    expect(wallClockJump(a, at(Duration.zero, boot: 'boot-2'), const Duration(seconds: 5)),
        isNull);
  });
}
