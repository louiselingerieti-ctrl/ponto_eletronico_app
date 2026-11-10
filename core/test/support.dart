import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:presenca_core/presenca_core_native.dart';

// ================================================================
//  APOIO EXCLUSIVO DE TESTE — dados e chaves SINTÉTICOS.
//  Não existe armazenamento em claro: os testes usam a MESMA base
//  cifrada do app, com uma chave sintética gerada aqui.
// ================================================================

const linkA = '00000000-0000-4000-8000-00000000e001';
const linkB = '00000000-0000-4000-8000-00000000e002';
const linkDeOutraConta = '00000000-0000-4000-8000-00000000e999';
const areaCentro = '00000000-0000-4000-8000-0000000000f1';
const areaAnexo = '00000000-0000-4000-8000-0000000000f2';

/// Chave SINTÉTICA, só para teste.
EncryptionKey syntheticKey([int seed = 7]) =>
    EncryptionKey.fromBytes(List<int>.generate(32, (i) => (i * 31 + seed) % 256));

LocalStore openStore(String path, {int seed = 7, String? installationId}) =>
    LocalStore.open(path,
        obtainKey: () => syntheticKey(seed), installationId: installationId);

class FakeClock implements Clock {
  FakeClock(this._now);
  DateTime _now;
  @override
  DateTime now() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

DeviceClock deviceClock(DateTime at, {int? elapsedMs = 1000, String? bootId = 'boot-1'}) =>
    DeviceClock(
      detectedAt: at,
      elapsedRealtimeMs: elapsedMs,
      bootId: bootId,
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
      configRevision: 'cfg-1',
      appVersion: '0.1.0-poc',
      clock: deviceClock(at),
      areaId: areaCentro,
      areaRevision: 1,
      transition: t,
      observedAt: observedAt,
      location: location,
    );

/// Configuração sintética no formato do rascunho `presenca-v1`.
Map<String, Object?> configJson({
  String link = linkA,
  String revision = 'cfg-1',
  DateTime? serverTime,
  DateTime? validUntil,
  List<Map<String, Object?>>? areas,
}) {
  final st = serverTime ?? DateTime.utc(2026, 11, 10, 11);
  return {
    'employmentLinkId': link,
    'configRevision': revision,
    'policyRevision': 'pol-1',
    'serverTime': st.toIso8601String(),
    'validUntil': (validUntil ?? st.add(const Duration(hours: 24))).toIso8601String(),
    'areas': areas ?? [areaJson(areaCentro)],
    'detection': {'maxFixAgeSeconds': 120, 'maxAccuracyMeters': 100, 'dwellSeconds': 0},
    'manualPunch': {'allowed': false, 'reasonRequired': true, 'locationRequired': false},
    'offline': {'maxEventAgeHours': 24, 'maxQueuedEvents': 500},
  };
}

Map<String, Object?> areaJson(String id, {int revision = 1, String? validTo}) => {
      'areaId': id,
      'revision': revision,
      'label': 'Unidade Sintética',
      'kind': 'establishment',
      'center': {'latitude': 0.0012, 'longitude': 0.0034},
      'radiusMeters': 150,
      'validFrom': '2026-11-01T03:00:00.000Z',
      'validTo': validTo,
    };

String encode(Map<String, Object?> m) => jsonEncode(m);

/// Limiares PROVISÓRIOS, só para teste (D-CLK-1 pendente).
const testClockPolicy = ClockQualityPolicy(
    tolerance: Duration(seconds: 5), maxReferenceAge: Duration(hours: 12));

ClockStamper stamperFor(LocalStore s) => ClockStamper(
    configs: s.configs, policy: testClockPolicy, timeZone: () => 'America/Sao_Paulo');

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

class TempDir {
  TempDir() : dir = Directory.systemTemp.createTempSync('presenca_core_');
  final Directory dir;
  String get path => '${dir.path}${Platform.pathSeparator}local.db';
  void dispose() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}
