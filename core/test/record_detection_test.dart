import 'dart:convert';

import 'package:presenca_core/presenca_core_native.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 10, 11);
  late TempDir tmp;
  late LocalStore store;
  late ConfigLifecycle lc;

  setUp(() {
    tmp = TempDir();
    store = openStore(tmp.path);
    lc = ConfigLifecycle(store: store, stamper: stamperFor(store), appVersion: 't');
  });
  tearDown(() {
    store.close();
    tmp.dispose();
  });

  RecordDetection recorder(PendingPolicies p) => RecordDetection(
      store: store, stamper: stamperFor(store), policies: p, appVersion: '0.1.0-poc');

  PendingPolicies all(PendingCaseHandling h) =>
      PendingPolicies(expiredConfig: h, revokedLink: h, afterAuthLoss: h);

  void saveApplied({String link = linkA, String rev = 'cfg-1', DateTime? serverTime}) {
    lc.persist(
        lc.receive(encode(configJson(link: link, revision: rev, serverTime: serverTime)),
            expectedLinkId: link, receivedAt: t0),
        now: t0);
    lc.confirmApplied(link, rev,
        registeredAreaIds: {areaCentro},
        sample: ClockSample(wall: t0, elapsedRealtimeMs: 1, bootId: 'boot-1'));
  }

  GeofenceCallback cb({
    String link = linkA,
    String rev = 'cfg-1',
    String area = areaCentro,
    int areaRev = 1,
    DateTime? at,
    DateTime? observedAt,
  }) =>
      GeofenceCallback(
        employmentLinkId: link, configRevision: rev, areaId: area, areaRevision: areaRev,
        transition: Transition.enter, observedAt: observedAt,
        sample: ClockSample(wall: at ?? t0.add(const Duration(minutes: 5))),
      );

  int transitions() => store.queue.all()
      .where((e) => (jsonDecode(e.payloadJson) as Map)['kind'] == 'area_transition')
      .length;

  group('atribuição explícita', () {
    test('vínculo sem configuração: recusado', () {
      expect((recorder(all(PendingCaseHandling.recordAndFlag))(cb()) as Refused).reason,
          RefusalReason.unknownLink);
    });

    test('revisão desconhecida ou área fora da configuração: recusado', () {
      saveApplied();
      final r = recorder(all(PendingCaseHandling.recordAndFlag));
      expect((r(cb(rev: 'cfg-x')) as Refused).reason, RefusalReason.unknownConfigRevision);
      expect((r(cb(area: areaAnexo)) as Refused).reason, RefusalReason.areaNotInConfig);
      expect((r(cb(areaRev: 9)) as Refused).reason, RefusalReason.areaNotInConfig);
      expect(transitions(), 0);
    });

    test('pessoa com dois vínculos: o evento vai só para o vínculo do geofence', () {
      saveApplied();
      saveApplied(link: linkB, rev: 'cfg-b');
      final out = recorder(all(PendingCaseHandling.recordAndFlag))(cb()) as Recorded;
      expect((jsonDecode(out.event.payloadJson) as Map)['employmentLinkId'], linkA);
      expect(transitions(), 1);
    });

    test('caminho normal: gravado sem marcações locais e sem horário inventado', () {
      saveApplied();
      final out = recorder(all(PendingCaseHandling.refuse))(cb()) as Recorded;
      expect(out.flags, isEmpty);
      final json = jsonDecode(out.event.payloadJson) as Map;
      expect(json['observedAt'], isNull);
      expect(json['observedAtSource'], 'none');
      expect((json['clock'] as Map)['elapsedRealtimeMs'], isNull);
      expect((json['clock'] as Map)['quality'], 'uncertain');
    });

    test('configuração persistida mas não confirmada: gravado com marcação local', () {
      lc.persist(lc.receive(encode(configJson()), expectedLinkId: linkA, receivedAt: t0),
          now: t0);
      final out = recorder(all(PendingCaseHandling.refuse))(cb()) as Recorded;
      expect(out.flags, {CaptureFlag.configNotConfirmed});
      expect(store.queue.captureFlagsOf(out.event.eventId), {CaptureFlag.configNotConfirmed});
      // A marcação local não entra no payload do contrato.
      expect(out.event.payloadJson.contains('config_not_confirmed'), isFalse);
    });

    test('geofence ainda da revisão substituída: fato preservado e marcado', () {
      saveApplied();
      saveApplied(rev: 'cfg-2', serverTime: t0.add(const Duration(minutes: 1)));
      final out = recorder(all(PendingCaseHandling.refuse))(cb(rev: 'cfg-1')) as Recorded;
      expect(out.flags, contains(CaptureFlag.configSuperseded));
      expect((jsonDecode(out.event.payloadJson) as Map)['configRevision'], 'cfg-1');
    });
  });

  group('decisões pendentes: o núcleo executa só a opção escolhida explicitamente', () {
    final later = t0.add(const Duration(hours: 30));

    test('D-CFG-1 configuração vencida', () {
      saveApplied();
      final refused = recorder(all(PendingCaseHandling.refuse))(cb(at: later)) as Refused;
      expect(refused.reason, RefusalReason.pendingDecision);
      expect(refused.decision, PendingDecision.expiredConfig);
      expect(transitions(), 0);
      final rec = recorder(all(PendingCaseHandling.recordAndFlag))(cb(at: later)) as Recorded;
      expect(rec.flags, {CaptureFlag.configExpired});
    });

    test('D-LINK-1 vínculo revogado', () {
      saveApplied();
      lc.revoke(linkA, reason: 'presence_disabled', at: t0);
      expect((recorder(all(PendingCaseHandling.refuse))(cb()) as Refused).decision,
          PendingDecision.revokedLink);
      expect((recorder(all(PendingCaseHandling.recordAndFlag))(cb()) as Recorded).flags,
          {CaptureFlag.linkRevoked});
    });

    test('D-AUTH-2 depois de perder a sessão (envio parado por 401)', () {
      saveApplied();
      store.queue.haltDelivery(DeliveryHalt(DeliveryHaltReason.unauthenticated, t0));
      expect((recorder(all(PendingCaseHandling.refuse))(cb()) as Refused).decision,
          PendingDecision.afterAuthLoss);
      expect((recorder(all(PendingCaseHandling.recordAndFlag))(cb()) as Recorded).flags,
          {CaptureFlag.afterAuthLoss});
    });

    test('parada por defeito interno não é perda de sessão', () {
      saveApplied();
      store.queue.haltDelivery(DeliveryHalt(DeliveryHaltReason.internalDefect, t0));
      expect(recorder(all(PendingCaseHandling.refuse))(cb()), isA<Recorded>());
    });
  });
}
