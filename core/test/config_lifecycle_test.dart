import 'dart:convert';

import 'package:presenca_core/presenca_core_native.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 10, 11);
  late TempDir tmp;
  late LocalStore store;
  late ConfigLifecycle lc;

  ConfigLifecycle make(LocalStore s) =>
      ConfigLifecycle(store: s, stamper: stamperFor(s), appVersion: '0.1.0-poc');

  setUp(() {
    tmp = TempDir();
    store = openStore(tmp.path);
    lc = make(store);
  });
  tearDown(() {
    store.close();
    tmp.dispose();
  });

  ConfigReceived recv(Map<String, Object?> json,
          {String link = linkA, ServerTimeReference? ref}) =>
      lc.receive(encode(json), expectedLinkId: link, receivedAt: t0, reference: ref);

  PersistResult save(Map<String, Object?> json, {String link = linkA}) =>
      lc.persist(recv(json, link: link), now: t0);

  ClockSample sample(DateTime at) =>
      ClockSample(wall: at, elapsedRealtimeMs: 5000, bootId: 'boot-1');

  List<Map<String, Object?>> statusEvents() => [
        for (final e in store.queue.all())
          if ((jsonDecode(e.payloadJson) as Map)['kind'] == 'detection_status')
            (jsonDecode(e.payloadJson) as Map).cast<String, Object?>()
      ];

  group('recebida: validação estrita, sem gravar', () {
    void rejects(Map<String, Object?> json, String fragment, {String link = linkA}) {
      expect(
          () => recv(json, link: link),
          throwsA(isA<ConfigValidationError>()
              .having((e) => e.errors.join('|'), 'errors', contains(fragment))));
    }

    test('vínculo diferente do solicitado', () =>
        rejects(configJson(link: linkB), 'diferente do vínculo'));
    test('campo desconhecido', () =>
        rejects(configJson()..['extra'] = 1, 'campo desconhecido "extra"'));
    test('raio abaixo do mínimo do contrato', () => rejects(
        configJson(areas: [areaJson(areaCentro)..['radiusMeters'] = 10]), 'radiusMeters'));
    test('validUntil não posterior a serverTime', () =>
        rejects(configJson(validUntil: DateTime.utc(2026, 11, 10, 10)), 'validUntil'));
    test('horário sem fuso', () =>
        rejects(configJson()..['serverTime'] = '2026-11-10T11:00:00', 'serverTime'));
    test('área repetida', () => rejects(
        configJson(areas: [areaJson(areaCentro), areaJson(areaCentro)]), 'repetido'));
    test('mais de 20 áreas', () => rejects(
        configJson(areas: [for (var i = 0; i < 21; i++) areaJson('a$i')]), 'acima de 20'));

    test('recebida não persiste nada', () {
      recv(configJson());
      store.close();
      store = openStore(tmp.path);
      expect(store.configs.current(linkA), isNull);
    });
  });

  group('persistida', () {
    test('sobrevive a reinício e ainda NÃO está aplicada', () {
      expect(save(configJson()), isA<ConfigPersisted>());
      store.close();
      store = openStore(tmp.path);
      lc = make(store);
      final a = lc.assess(linkA, now: t0);
      expect(a.status, ConfigStatus.persisted);
      expect(a.current!.config.configRevision, 'cfg-1');
    });

    test('mesma revisão e mesmo conteúdo: inalterada (ordem de chaves irrelevante)', () {
      save(configJson());
      final reordered = Map.fromEntries(configJson().entries.toList().reversed);
      expect(save(reordered), isA<ConfigUnchanged>());
    });

    test('mesma revisão com outro conteúdo: conflito; a gravada é preservada', () {
      save(configJson());
      final other = configJson(areas: [areaJson(areaCentro, revision: 2)]);
      expect(save(other), isA<ConfigRevisionConflict>());
      expect(store.configs.current(linkA)!.config.areas.single.revision, 1);
    });

    test('nova revisão substitui; resposta mais antiga é ignorada', () {
      save(configJson());
      expect(save(configJson(revision: 'cfg-2', serverTime: t0.add(const Duration(hours: 1)))),
          isA<ConfigPersisted>());
      expect(store.configs.current(linkA)!.config.configRevision, 'cfg-2');
      expect(store.configs.byRevision(linkA, 'cfg-1')!.supersededAt, isNotNull);

      final old = save(configJson(revision: 'cfg-0', serverTime: t0.subtract(const Duration(hours: 1))));
      expect(old, isA<ConfigStale>());
      // Reentrega da revisão substituída também não volta a valer.
      expect(save(configJson()), isA<ConfigStale>());
      expect(store.configs.current(linkA)!.config.configRevision, 'cfg-2');
    });

    test('configurações de vínculos diferentes ficam separadas', () {
      save(configJson());
      save(configJson(link: linkB, revision: 'cfg-b'), link: linkB);
      expect(store.configs.current(linkA)!.config.configRevision, 'cfg-1');
      expect(store.configs.current(linkB)!.config.configRevision, 'cfg-b');
    });
  });

  group('aplicada', () {
    test('confirmação completa: aplicada + evento config_applied no mesmo commit', () {
      save(configJson());
      final r = lc.confirmApplied(linkA, 'cfg-1',
          registeredAreaIds: {areaCentro}, sample: sample(t0));
      expect(r, isA<ConfigApplied>());
      expect(lc.assess(linkA, now: t0).status, ConfigStatus.applied);
      final ev = statusEvents().single;
      expect(ev['status'], 'config_applied');
      expect(ev['configRevision'], 'cfg-1');
      expect(store.configs.current(linkA)!.applyEventId, (r as ConfigApplied).event.eventId);
      // Repetir a confirmação não duplica o evento.
      expect(lc.confirmApplied(linkA, 'cfg-1', registeredAreaIds: {areaCentro},
          sample: sample(t0)), isA<ApplyAlreadyConfirmed>());
      expect(statusEvents(), hasLength(1));
    });

    test('registro parcial ou com área a mais: falha + evento de falha', () {
      save(configJson(areas: [areaJson(areaCentro), areaJson(areaAnexo)]));
      final r = lc.confirmApplied(linkA, 'cfg-1',
          registeredAreaIds: {areaCentro, 'intrusa'}, sample: sample(t0)) as ApplyFailed;
      expect(r.missing, {areaAnexo});
      expect(r.unexpected, {'intrusa'});
      expect(lc.assess(linkA, now: t0).status, ConfigStatus.applyFailed);
      expect(statusEvents().single['status'], 'geofence_registration_failed');
    });

    test('só as áreas vigentes no instante da aplicação são exigidas', () {
      save(configJson(areas: [
        areaJson(areaCentro),
        areaJson(areaAnexo, validTo: '2026-11-05T00:00:00.000Z'), // já encerrada
      ]));
      expect(lc.confirmApplied(linkA, 'cfg-1',
          registeredAreaIds: {areaCentro}, sample: sample(t0)), isA<ConfigApplied>());
    });

    test('falha informada pela plataforma', () {
      save(configJson());
      final r = lc.reportApplyFailure(linkA, 'cfg-1',
          detail: 'GEOFENCE_NOT_AVAILABLE', sample: sample(t0));
      expect(r, isA<ApplyFailed>());
      expect(statusEvents().single['detail'], 'GEOFENCE_NOT_AVAILABLE');
    });

    test('confirmação de revisão que não é a atual: nada muda', () {
      save(configJson());
      save(configJson(revision: 'cfg-2', serverTime: t0.add(const Duration(hours: 1))));
      expect(lc.confirmApplied(linkA, 'cfg-1', registeredAreaIds: {areaCentro},
          sample: sample(t0)), isA<ApplyNotCurrent>());
      expect(store.queue.all(), isEmpty);
    });
  });

  group('vencida e revogada: fatos registrados, decisões pendentes', () {
    test('vencimento: aparece como pendência D-CFG-1 e gera config_expired uma vez', () {
      save(configJson());
      final later = t0.add(const Duration(hours: 25));
      final a = lc.assess(linkA, now: later);
      expect(a.expired, isTrue);
      expect(a.pendingDecisions, [PendingDecision.expiredConfig]);
      expect(lc.noteExpiry(linkA, sample: sample(t0)), isNull); // ainda vigente
      expect(lc.noteExpiry(linkA, sample: sample(later)), isNotNull);
      expect(lc.noteExpiry(linkA, sample: sample(later)), isNull);
      expect(statusEvents().single['status'], 'config_expired');
    });

    test('revogação: pendência D-LINK-1; nova configuração recusada até liberar', () {
      save(configJson());
      lc.revoke(linkA, reason: 'link_ended', at: t0);
      final a = lc.assess(linkA, now: t0);
      expect(a.revocation!.reason, 'link_ended');
      expect(a.pendingDecisions, [PendingDecision.revokedLink]);
      expect(save(configJson(revision: 'cfg-2', serverTime: t0.add(const Duration(hours: 1)))),
          isA<ConfigRefusedRevoked>());
      lc.liftRevocation(linkA, at: t0);
      expect(save(configJson(revision: 'cfg-2', serverTime: t0.add(const Duration(hours: 1)))),
          isA<ConfigPersisted>());
    });
  });

  test('referência de horário da configuração alimenta a qualidade do relógio', () {
    final ref = ServerTimeReference(serverTime: t0, elapsedAtReceiptMs: 1000,
        bootId: 'boot-1', roundTrip: const Duration(milliseconds: 300));
    lc.persist(recv(configJson(), ref: ref), now: t0);
    store.close();
    store = openStore(tmp.path);
    final st = stamperFor(store);
    final ok = ClockSample(wall: t0.add(const Duration(minutes: 10)),
        elapsedRealtimeMs: 1000 + 600000, bootId: 'boot-1');
    expect(st.stamp(ok).quality, ClockQuality.trusted);
    final rebooted = ClockSample(wall: ok.wall, elapsedRealtimeMs: 50, bootId: 'boot-2');
    expect(st.stamp(rebooted).quality, ClockQuality.uncertain);
  });
}
