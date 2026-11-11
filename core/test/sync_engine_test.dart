import 'dart:convert';

import 'package:presenca_core/presenca_core_native.dart';
import 'package:presenca_core/presenca_lab.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late TempDir tmp;
  late FakeClock clock;
  late LocalStore store;
  late SimulatedPresenceServer server;
  late SyncEngine engine;

  final t0 = DateTime.utc(2026, 11, 10, 11);

  SyncEngine newEngine(LocalStore s, PresenceApi api, {int maxBatch = 100}) =>
      SyncEngine(queue: s.queue, api: api, clock: clock,
          backoff: deterministicBackoff(), maxBatch: maxBatch);

  setUp(() {
    tmp = TempDir();
    clock = FakeClock(t0);
    store = openStore(tmp.path);
    server = SimulatedPresenceServer(
        ownedEmploymentLinks: {linkA}, clock: () => clock.now());
    engine = newEngine(store, server);
  });

  tearDown(() {
    store.close();
    tmp.dispose();
  });

  List<DeliveryState> states() => [for (final e in store.queue.all()) e.state];
  QueuedEvent add([Transition t = Transition.enter, String link = linkA]) =>
      store.queue.append(transition(t, clock.now(), link: link), now: clock.now());
  void reopen() {
    store.close();
    store = openStore(tmp.path);
    engine = newEngine(store, server);
  }

  group('forma do contrato v1', () {
    test('sem leitura do SO: observedAt nulo, source none, sem location', () {
      final json = jsonDecode(add().payloadJson) as Map<String, Object?>;
      expect(json['schemaVersion'], 1);
      expect(json['observedAt'], isNull);
      expect(json['observedAtSource'], 'none');
      expect(json.containsKey('location'), isFalse);
      expect(json['installationSequence'], 1);
    });

    test('com leitura do SO: observedAt vem da leitura, nunca de estimativa', () {
      final fix = DateTime.utc(2026, 11, 10, 10, 59, 48);
      final e = store.queue.append(
          transition(Transition.enter, t0,
              observedAt: fix,
              location: LocationFix(latitude: 0.0013, longitude: 0.0035,
                  accuracyMeters: 18, provider: LocationProvider.fused,
                  fixedAt: fix, mockReported: false)),
          now: t0);
      final json = jsonDecode(e.payloadJson) as Map<String, Object?>;
      expect(json['observedAtSource'], 'os_triggering_fix');
      expect(json['observedAt'], fix.toIso8601String());
      expect((json['clock'] as Map)['detectedAt'], t0.toIso8601String());
    });

    test('monotônico e boot ausentes são enviados como nulos, nunca inventados', () {
      final e = store.queue.append(
          DetectionStatusDraft(
              employmentLinkId: linkA, configRevision: 'cfg-1', appVersion: 't',
              clock: deviceClock(t0, elapsedMs: null, bootId: null),
              status: DetectionStatus.appRestarted),
          now: t0);
      final c = (jsonDecode(e.payloadJson) as Map)['clock'] as Map;
      expect(c['elapsedRealtimeMs'], isNull);
      expect(c['bootId'], isNull);
      expect(c['quality'], 'uncertain');
    });
  });

  test('salvo no aparelho sobrevive a reabertura', () {
    final e = add();
    reopen();
    expect(store.queue.all().single.eventId, e.eventId);
  });

  test('callback duplicado do SO vira dois eventos (sem dedupe por horário)', () async {
    add();
    add();
    expect((await engine.syncOnce()).received, 2);
    expect(server.stored, hasLength(2));
  });

  test('ordem invertida do SO é preservada como chegou', () async {
    add(Transition.exit);
    add(Transition.enter);
    await engine.syncOnce();
    final kinds = [
      for (final s in server.stored.values.toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence)))
        s.body['transition']
    ];
    expect(kinds, ['exit', 'enter']);
  });

  group('falhas transitórias', () {
    test('rede ausente: volta à fila com backoff e depois envia', () async {
      add();
      server.faults.add(const NetworkDown());
      final r1 = await engine.syncOnce();
      expect(r1.failure, FailureClass.transient);
      expect(r1.halt, isNull);
      expect(states(), [DeliveryState.savedLocally]);
      final next = store.queue.nextAttemptAt()!;
      expect(next.isAfter(t0), isTrue);
      expect((await engine.syncOnce()).nothingToSend, isTrue);
      clock.advance(next.difference(t0));
      expect((await engine.syncOnce()).received, 1);
    });

    test('503 antes do commit: nada gravado; reenvio grava', () async {
      add();
      server.faults.add(const FailBeforeCommit());
      expect((await engine.syncOnce()).failure, FailureClass.transient);
      expect(server.stored, isEmpty);
      clock.advance(const Duration(hours: 1));
      await engine.syncOnce();
      expect(states(), [DeliveryState.received]);
    });

    test('timeout depois do commit: reenvio recebe duplicate com o recibo original',
        () async {
      final e = add();
      server.faults.add(const TimeoutAfterCommit());
      await engine.syncOnce();
      expect(states(), [DeliveryState.savedLocally]);
      final original = server.stored[e.eventId]!;
      clock.advance(const Duration(hours: 1));
      await engine.syncOnce();
      final q = store.queue.all().single;
      expect(q.state, DeliveryState.received);
      expect(q.outcomeCode, 'duplicate');
      expect(q.receiptId, original.receiptId);
      expect(q.serverReceivedAt, original.receivedAt);
      expect(server.stored, hasLength(1));
    });

    test('429: Retry-After é piso do próximo envio', () async {
      add();
      server.faults.add(const RateLimited(Duration(minutes: 45)));
      await engine.syncOnce();
      expect(store.queue.nextAttemptAt()!.difference(t0) >= const Duration(minutes: 45),
          isTrue);
    });

    test('backoff persiste entre reinícios', () async {
      add();
      final delays = <Duration>[];
      for (var i = 0; i < 3; i++) {
        server.faults.add(const NetworkDown());
        final before = clock.now();
        await engine.syncOnce();
        delays.add(store.queue.nextAttemptAt()!.difference(before));
        clock.advance(delays.last);
        reopen(); // novo processo, novo SyncEngine
      }
      expect(store.queue.consecutiveFailures(), 3);
      expect(delays, [
        const Duration(seconds: 5),
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      await engine.syncOnce();
      expect(store.queue.consecutiveFailures(), 0); // zera com sucesso completo
    });
  });

  group('autenticação/permissão: para e persiste', () {
    test('401: envio parado, eventos mantidos, nada sai até resume()', () async {
      add();
      server.faults.add(const Unauthenticated());
      final r = await engine.syncOnce();
      expect(r.failure, FailureClass.authOrPermission);
      expect(r.halt!.reason, DeliveryHaltReason.unauthenticated);
      expect(states(), [DeliveryState.savedLocally]);

      reopen();
      final calls = server.submitCalls;
      clock.advance(const Duration(days: 1));
      expect((await engine.syncOnce()).halt!.reason, DeliveryHaltReason.unauthenticated);
      expect(server.submitCalls, calls);

      engine.resume();
      expect((await engine.syncOnce()).received, 1);
    });

    test('403 instalação revogada: parado com o código', () async {
      add();
      server.faults.add(const InstallationRevoked());
      final r = await engine.syncOnce();
      expect(r.halt!.reason, DeliveryHaltReason.forbidden);
      expect(r.halt!.detail, 'installation_revoked');
    });
  });

  group('rejeição de contrato', () {
    test('400 de envelope: parado (defeito do app, sem retry)', () async {
      add();
      server.faults.add(const InvalidEnvelope());
      final r = await engine.syncOnce();
      expect(r.failure, FailureClass.contractRejection);
      expect(r.halt!.reason, DeliveryHaltReason.invalidEnvelope);
    });

    test('200 sem recibo: não marca recebido e registra anomalia', () async {
      add();
      server.faults.add(const AckWithoutReceipt());
      final r = await engine.syncOnce();
      expect(r.received, 0);
      expect(r.unanswered, 1);
      expect(r.failure, FailureClass.contractRejection);
      expect(r.anomalies.single, contains('sem receiptId'));
      expect(states(), [DeliveryState.savedLocally]);
      clock.advance(const Duration(hours: 1));
      await engine.syncOnce();
      expect(store.queue.all().single.outcomeCode, 'duplicate');
    });

    test('resultado repetido ou de evento estranho: anomalia, sem efeito', () async {
      final e = add();
      final api = _ScriptedApi((_) => BatchResults([
            EventOutcome(eventId: e.eventId, kind: OutcomeKind.accepted,
                receiptId: 'r1', receivedAt: t0),
            EventOutcome(eventId: e.eventId, kind: OutcomeKind.rejected, code: 'x'),
            EventOutcome(eventId: 'nao-pertence', kind: OutcomeKind.accepted,
                receiptId: 'r2', receivedAt: t0),
          ]));
      final r = await newEngine(store, api).syncOnce();
      expect(r.anomalies, hasLength(2));
      expect(r.received, 0);
      expect(states(), [DeliveryState.savedLocally]);
    });

    test('413 com lote redutível: reduz; com lote de 1: para', () async {
      final api = _ScriptedApi((p) => p.length > 2
          ? const BatchFailure(BatchFailureReason.payloadTooLarge)
          : BatchResults([
              for (final raw in p)
                EventOutcome(
                    eventId: (jsonDecode(raw) as Map)['eventId'] as String,
                    kind: OutcomeKind.accepted, receiptId: 'r', receivedAt: t0),
            ]));
      final eng = newEngine(store, api, maxBatch: 4);
      for (var i = 0; i < 4; i++) {
        add();
      }
      final r = await eng.syncOnce();
      expect(r.failure, FailureClass.transient);
      expect(eng.maxBatch, 2);
      await eng.syncOnce();
      await eng.syncOnce();
      expect(states().every((s) => s == DeliveryState.received), isTrue);

      add();
      final tooBig = newEngine(store,
          _ScriptedApi((_) => const BatchFailure(BatchFailureReason.payloadTooLarge)),
          maxBatch: 1);
      final r2 = await tooBig.syncOnce();
      expect(r2.halt!.reason, DeliveryHaltReason.payloadTooLargeSingle);
    });

    test('vínculo de outra conta: rejected; válidos não afetados; nunca reenvia',
        () async {
      add();
      add(Transition.enter, linkDeOutraConta);
      add(Transition.exit);
      await engine.syncOnce();
      final all = store.queue.all();
      expect(all[1].state, DeliveryState.rejected);
      expect(all[1].outcomeCode, 'link_not_owned');
      expect(all[0].state, DeliveryState.received);
      expect(all[2].state, DeliveryState.received);
      clock.advance(const Duration(days: 1));
      expect((await engine.syncOnce()).nothingToSend, isTrue);
    });

    test('conflito: mesmo eventId com outro conteúdo; original preservado', () async {
      final e = add();
      final adulterado = (jsonDecode(e.payloadJson) as Map<String, Object?>)
        ..['transition'] = 'exit';
      await server.submitBatch([jsonEncode(adulterado)]);
      await engine.syncOnce();
      final q = store.queue.all().single;
      expect(q.state, DeliveryState.conflict);
      expect(server.stored[e.eventId]!.body['transition'], 'exit');
      expect(q.payloadJson, e.payloadJson);
    });
  });

  group('defeito interno', () {
    test('exceção inesperada não vira retry silencioso: para e registra o tipo',
        () async {
      add();
      server.faults.add(const AdapterBug());
      final r = await engine.syncOnce();
      expect(r.failure, FailureClass.internalDefect);
      expect(r.halt!.reason, DeliveryHaltReason.internalDefect);
      expect(r.halt!.detail, 'StateError');
      expect(states(), [DeliveryState.savedLocally]);
      reopen();
      expect(store.queue.deliveryHalt()!.reason, DeliveryHaltReason.internalDefect);
      final calls = server.submitCalls;
      await engine.syncOnce();
      expect(server.submitCalls, calls);
    });
  });

  group('ACK parcial e lacunas', () {
    test('sem resultado volta à fila; reenvio vira duplicate', () async {
      final a = add();
      final b = add(Transition.exit);
      final c = add();
      server.faults.add(PartialAck({b.eventId}));
      final r1 = await engine.syncOnce();
      expect(r1.received, 2);
      expect(r1.unanswered, 1);
      expect(r1.anomalies, isEmpty);
      final byId = {for (final e in store.queue.all()) e.eventId: e.state};
      expect(byId[a.eventId], DeliveryState.received);
      expect(byId[b.eventId], DeliveryState.savedLocally);
      expect(byId[c.eventId], DeliveryState.received);
      clock.advance(const Duration(hours: 1));
      await engine.syncOnce();
      expect(states().every((s) => s == DeliveryState.received), isTrue);
      expect(server.stored, hasLength(3));
    });

    test('evento perdido antes do envio: servidor aceita e sinaliza lacuna', () async {
      add();
      final perdido = add(Transition.exit);
      add();
      await server.submitBatch([
        for (final e in store.queue.all())
          if (e.eventId != perdido.eventId) e.payloadJson
      ]);
      expect(server.sequenceGaps, [(1, 3)]);
    });
  });

  group('reinício e concorrência', () {
    test('processo morre com lote em voo: lease expira e reenvia; sequência continua',
        () async {
      add();
      add(Transition.exit);
      store.queue.lease(max: 10, now: t0, leaseUntil: t0.add(const Duration(minutes: 2)));
      reopen();
      expect((await engine.syncOnce()).nothingToSend, isTrue);
      clock.advance(const Duration(minutes: 3));
      expect((await engine.syncOnce()).received, 2);
      expect(add().installationSequence, 3);
    });

    test('duas conexões na mesma base não reservam o mesmo evento', () {
      add();
      add();
      final other = openStore(tmp.path); // outro isolate/processo
      addTearDown(other.close);
      final a = store.queue.lease(max: 10, now: t0, leaseUntil: t0.add(const Duration(minutes: 2)));
      final b = other.queue.lease(max: 10, now: t0, leaseUntil: t0.add(const Duration(minutes: 2)));
      expect(a.events, hasLength(2));
      expect(b.events, isEmpty);
    });

    test('reserva vencida e retomada por outro: o primeiro não altera o lote alheio',
        () {
      final e = add();
      final other = openStore(tmp.path);
      addTearDown(other.close);
      final a = store.queue.lease(max: 10, now: t0, leaseUntil: t0.add(const Duration(minutes: 2)));
      final t1 = t0.add(const Duration(minutes: 3));
      other.queue.recoverExpiredLeases(t1);
      final b = other.queue.lease(max: 10, now: t1, leaseUntil: t1.add(const Duration(minutes: 2)));
      expect(b.events.single.eventId, e.eventId);

      // O envio atrasado do primeiro tenta concluir/devolver: sem efeito.
      store.queue.release(a.token, retryAt: t1);
      store.queue.settle(token: a.token, outcomes: {
        e.eventId: EventOutcome(eventId: e.eventId, kind: OutcomeKind.rejected, code: 'x'),
      }, retryAt: t1);
      expect(store.queue.all().single.state, DeliveryState.sending);

      other.queue.settle(token: b.token, outcomes: {
        e.eventId: EventOutcome(eventId: e.eventId, kind: OutcomeKind.accepted,
            receiptId: 'r', receivedAt: t1),
      }, retryAt: t1);
      expect(store.queue.all().single.state, DeliveryState.received);
    });

    test('installationId é estável entre reaberturas', () {
      final id = store.installationId;
      store.close();
      store = openStore(tmp.path, installationId: 'outro');
      expect(store.installationId, id);
    });
  });
}

class _ScriptedApi implements PresenceApi {
  _ScriptedApi(this._fn);
  final BatchResponse Function(List<String>) _fn;
  @override
  Future<BatchResponse> submitBatch(List<String> payloadsJson) async => _fn(payloadsJson);
}
