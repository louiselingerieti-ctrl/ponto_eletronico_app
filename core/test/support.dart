import 'dart:io';
import 'dart:math';

import 'package:presenca_core/presenca_core.dart';

/// Dados SINTÉTICOS: ids fictícios e coordenadas perto de 0,0.
const linkA = '00000000-0000-4000-8000-00000000e001';
const linkDeOutraConta = '00000000-0000-4000-8000-00000000e999';
const areaCentro = '00000000-0000-4000-8000-0000000000f1';

class FakeClock implements Clock {
  FakeClock(this._now);
  DateTime _now;
  @override
  DateTime now() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

DeviceClock deviceClock(DateTime at, {int elapsedMs = 1000}) => DeviceClock(
      detectedAt: at,
      elapsedRealtimeMs: elapsedMs,
      bootId: 'boot-sintetico-1',
      timeZone: 'America/Sao_Paulo',
      quality: ClockQuality.uncertain,
    );

AreaTransitionDraft transition(
  Transition t,
  DateTime at, {
  String link = linkA,
  DateTime? observedAt,
  LocationFix? location,
}) =>
    AreaTransitionDraft(
      employmentLinkId: link,
      configRevision: 'cfg-sintetica-1',
      appVersion: '0.1.0-poc',
      clock: deviceClock(at),
      areaId: areaCentro,
      areaRevision: 1,
      transition: t,
      observedAt: observedAt,
      location: location,
    );

/// Backoff determinístico (sem jitter aleatório) para os testes.
Backoff deterministicBackoff() => Backoff(random: _MaxRandom());

class _MaxRandom implements Random {
  @override
  double nextDouble() => 1.0;
  @override
  bool nextBool() => true;
  @override
  int nextInt(int max) => max - 1;
}

class TempDb {
  TempDb() : dir = Directory.systemTemp.createTempSync('presenca_core_');
  final Directory dir;
  String get path => '${dir.path}${Platform.pathSeparator}fila.db';
  void dispose() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}
