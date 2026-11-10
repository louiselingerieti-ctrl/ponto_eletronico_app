import 'dart:convert';

import 'package:presenca_core/presenca_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late TempDb tmp;
  late FakeClock clock;
  late SqliteEventQueue queue;
  late SimulatedPresenceServer server;
  late SyncEngine engine;

  final t0 = DateTime.utc(2026, 11, 10, 11);

  setUp(() {
    tmp = TempDb();
    clock = FakeClock(t0);
    queue = SqliteEventQueue.open(tmp.path);
    server = SimulatedPresenceServer(
        ownedEmploymentLinks: {linkA}, clock: () => clock.now());
    engine = SyncEngine(
        queue: queue, api: server, clock: clock, backoff: deterministicBackoff());
  });

  tearDown(() {
    queue.close();
    tmp.dispose();
  });

  List<DeliveryState> states() => [for (final e in queue.all()) e.state];

  group('forma do contrato v1', () {
    test('sem leitura do SO: observedAt nulo, source none, sem location', () {
      final e = queue.append(transition(Transition.enter, t0), now: t0);
      final json = jsonDecode(e.payloadJson) as Map<String, Object?>;
      expect(json['schemaVersion'], 1);
      expect(json['kind'], 'area_transition');
      expect(json['observedAt'], isNull);
      expect(json['observedAtSource'], 'none');
      expect(json.containsKey('location'), isFalse);
      expect(json['installationSequence'], 1);
    });

    test('com leitura do SO: observedAt vem da leitura, nunca de estimativa', () {
      final fix = DateTime.utc(2026, 11, 10, 10, 59, 48);
      final e = queue.append(
          transition(Transition.enter, t0,
              observedAt: fix,
              location: LocationFix(
                  latitude: 0.0013, longitude: 0.0035, accuracyMeters: 18,
                  provider: LocationProvider.fused, fixedAt: fix,
                  mockReported: false)),
          now: t0);
      final json = jsonDecode(e.payloadJson) as Map<String, Object?>;
      expect(json['observedAtSource'], 'os_triggering_fix');
      expect(json['observedAt'], fix.toIso8601String());
      expect((json['clock'] as Map)['detectedAt'], t0.toIso8601String());
    });

    test('detection_status sem localização', () {
      final e = queue.append(
          DetectionStatusDraft(
              employmentLinkId: linkA, configRevision: 'cfg-sintetica-1',
              appVersion: '0.1.0-poc', clock: deviceClock(t0),
              status: DetectionStatus.backgroundLocationRevoked),
          now: t0);
      final json = jsonDecode(e.payloadJson) as Map<String, Object?>;
      expect(json['status'], 'background_location_revoked');
      expect(json.containsKey('location'), isFalse);
    });
  });

  test('salvo no aparelho só depois do commit e sobrevive a reabertura', () {
    final e = queue.append(transition(Transition.enter, t0), now: t0);
    expect(e.state, DeliveryState.savedLocally);
    queue.close();
    queue = SqliteEventQueue.open(tmp.path);
    expect(queue.all().single.eventId, e.eventId);
  });

  test('callback duplicado do SO vira dois eventos (sem dedupe por horário)',
      () async {
    queue.append(transition(Transition.enter, t0), now: t0);
    queue.append(transition(Transition.enter, t0.add(const Duration(seconds: 3))),
        now: t0);
    final r = await engine.syncOnce();
    expect(r.received, 2);
    expect(server.stored, hasLength(2));
    expect([for (final e in queue.all()) e.installationSequence], [1, 2]);
  });

  test('ordem invertida do SO (exit antes de enter) é preservada como chegou',
      () async {
    queue.append(transition(Transition.exit, t0), now: t0);
    queue.append(transition(Transition.enter, t0.add(const Duration(seconds: 1))),
        now: t0);
    await engine.syncOnce();
    final kinds = [
      for (final s in server.stored.values.toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence)))
        s.body['transition']
    ];
    expect(kinds, ['exit', 'enter']); // o app não reordena nem "corrige"
  });

  test('rede ausente: nada recebido, volta à fila com backoff, depois envia',
      () async {
    queue.append(transition(Transition.enter, t0), now: t0);
    server.faults.add(const NetworkDown());
    final r1 = await engine.syncOnce();
    expect(r1.failure, BatchFailureReason.transient);
    expect(states(), [DeliveryState.savedLocally]);
    expect(queue.all().single.attempts, 1);
    final next = queue.nextAttemptAt()!;
    expect(next.isAfter(t0), isTrue);

    // Antes do horário de retry, nada sai.
    expect((await engine.syncOnce()).halt, SyncHalt.nothingToSend);

    clock.advance(next.difference(t0));
    final r2 = await engine.syncOnce();
    expect(r2.received, 1);
    expect(states(), [DeliveryState.received]);
  });

  test('backoff cresce entre falhas seguidas', () async {
    queue.append(transition(Transition.enter, t0), now: t0);
    final delays = <Duration>[];
    for (var i = 0; i < 4; i++) {
      server.faults.add(const NetworkDown());
      final before = clock.now();
      await engine.syncOnce();
      final next = queue.nextAttemptAt()!;
      delays.add(next.difference(before));
      clock.advance(next.difference(before));
    }
    for (var i = 1; i < delays.length; i++) {
      expect(delays[i] > delays[i - 1], isTrue, reason: '$delays');
    }
  });

  test('503 antes do commit: nada gravado; reenvio grava normalmente', () async {
    queue.append(transition(Transition.enter, t0), now: t0);
    server.faults.add(const FailBeforeCommit());
    await engine.syncOnce();
    expect(server.stored, isEmpty);
    clock.advance(const Duration(hours: 1));
    await engine.syncOnce();
    expect(server.stored, hasLength(1));
    expect(states(), [DeliveryState.received]);
  });

  test('timeout depois do commit: reenvio recebe duplicate com o recibo original',
      () async {
    final e = queue.append(transition(Transition.enter, t0), now: t0);
    server.faults.add(const TimeoutAfterCommit());
    await engine.syncOnce();
    expect(states(), [DeliveryState.savedLocally]); // sem ACK, não é "recebido"
    final original = server.stored[e.eventId]!;

    clock.advance(const Duration(hours: 1));
    await engine.syncOnce();
    final q = queue.all().single;
    expect(q.state, DeliveryState.received);
    expect(q.outcomeCode, 'duplicate');
    expect(q.receiptId, original.receiptId);
    expect(q.serverReceivedAt, original.receivedAt); // do primeiro commit
    expect(server.stored, hasLength(1));
  });

  test('mesmo lote reenviado várias vezes: uma gravação, mesmo recibo', () async {
    final e = queue.append(transition(Transition.enter, t0), now: t0);
    for (var i = 0; i < 5; i++) {
      server.faults.add(const TimeoutAfterCommit());
      await engine.syncOnce();
      clock.advance(const Duration(hours: 2));
    }
    await engine.syncOnce();
    expect(server.stored, hasLength(1));
    expect(queue.all().single.receiptId, server.stored[e.eventId]!.receiptId);
  });

  test('ACK parcial: sem resultado volta para a fila; servidor sinaliza lacuna',
      () async {
    final a = queue.append(transition(Transition.enter, t0), now: t0);
    final b = queue.append(transition(Transition.exit, t0), now: t0);
    final c = queue.append(transition(Transition.enter, t0), now: t0);
    server.faults.add(PartialAck({b.eventId}));
    final r1 = await engine.syncOnce();
    expect(r1.received, 2);
    expect(r1.unanswered, 1);
    expect(server.sequenceGaps, isEmpty); // b foi gravado; só o ACK faltou
    final byId = {for (final e in queue.all()) e.eventId: e.state};
    expect(byId[a.eventId], DeliveryState.received);
    expect(byId[b.eventId], DeliveryState.savedLocally);
    expect(byId[c.eventId], DeliveryState.received);

    clock.advance(const Duration(hours: 1));
    await engine.syncOnce();
    // b foi gravado no 1º lote (só faltou o ACK) → agora é duplicate.
    expect(queue.all().every((e) => e.state == DeliveryState.received), isTrue);
    expect(server.stored, hasLength(3));
  });

  test('evento perdido antes do envio: servidor aceita e sinaliza lacuna', () async {
    queue.append(transition(Transition.enter, t0), now: t0);
    final perdido = queue.append(transition(Transition.exit, t0), now: t0);
    queue.append(transition(Transition.enter, t0), now: t0);
    // Simula perda: o 2º nunca chega ao servidor.
    final payloads = [
      for (final e in queue.all())
        if (e.eventId != perdido.eventId) e.payloadJson
    ];
    final r = await server.submitBatch(payloads) as BatchResults;
    expect(r.outcomes.every((o) => o.kind == OutcomeKind.accepted), isTrue);
    expect(server.sequenceGaps, [(1, 3)]);
  });

  test('resultado com eventId estranho ao lote é ignorado', () async {
    final api = _ScriptedApi((payloads) => const BatchResults([
          EventOutcome(eventId: 'nao-pertence', kind: OutcomeKind.accepted,
              receiptId: 'x'),
        ]));
    final eng = SyncEngine(
        queue: queue, api: api, clock: clock, backoff: deterministicBackoff());
    queue.append(transition(Transition.enter, t0), now: t0);
    final r = await eng.syncOnce();
    expect(r.received, 0);
    expect(r.unanswered, 1);
    expect(states(), [DeliveryState.savedLocally]);
  });

  test('vínculo de outra conta: rejected; os válidos do lote não são afetados',
      () async {
    queue.append(transition(Transition.enter, t0), now: t0);
    queue.append(transition(Transition.enter, t0, link: linkDeOutraConta), now: t0);
    queue.append(transition(Transition.exit, t0), now: t0);
    await engine.syncOnce();
    final all = queue.all();
    expect(all[1].state, DeliveryState.rejected);
    expect(all[1].outcomeCode, 'link_not_owned');
    expect(all[0].state, DeliveryState.received);
    expect(all[2].state, DeliveryState.received);

    // Recusado nunca é reenviado.
    clock.advance(const Duration(days: 1));
    final calls = server.submitCalls;
    expect((await engine.syncOnce()).halt, SyncHalt.nothingToSend);
    expect(server.submitCalls, calls);
  });

  test('conflito: mesmo eventId com outro conteúdo; original preservado', () async {
    final e = queue.append(transition(Transition.enter, t0), now: t0);
    final adulterado = (jsonDecode(e.payloadJson) as Map<String, Object?>)
      ..['transition'] = 'exit';
    await server.submitBatch([jsonEncode(adulterado)]);
    await engine.syncOnce();
    final q = queue.all().single;
    expect(q.state, DeliveryState.conflict);
    expect(server.stored[e.eventId]!.body['transition'], 'exit'); // o 1º fica
    expect(server.conflictIncidents, [e.eventId]);
    expect(q.payloadJson, e.payloadJson); // o app mantém o seu para análise
  });

  test('sessão expirada (401): para o envio e mantém os eventos', () async {
    queue.append(transition(Transition.enter, t0), now: t0);
    server.faults.add(const Unauthenticated());
    final r = await engine.syncOnce();
    expect(r.halt, SyncHalt.unauthenticated);
    expect(states(), [DeliveryState.savedLocally]);
  });

  test('instalação revogada (403): para o envio e mantém os eventos', () async {
    queue.append(transition(Transition.enter, t0), now: t0);
    server.faults.add(const InstallationRevoked());
    final r = await engine.syncOnce();
    expect(r.halt, SyncHalt.forbidden);
    expect(states(), [DeliveryState.savedLocally]);
  });

  test('429: Retry-After é piso do próximo envio', () async {
    queue.append(transition(Transition.enter, t0), now: t0);
    server.faults.add(const RateLimited(Duration(minutes: 45)));
    await engine.syncOnce();
    expect(
        queue.nextAttemptAt()!.difference(t0) >= const Duration(minutes: 45),
        isTrue);
  });

  test('413: reduz o tamanho do lote', () async {
    final api = _ScriptedApi((p) => p.length > 2
        ? const BatchFailure(BatchFailureReason.payloadTooLarge)
        : BatchResults([
            for (final raw in p)
              EventOutcome(
                  eventId: (jsonDecode(raw) as Map)['eventId'] as String,
                  kind: OutcomeKind.accepted, receiptId: 'r'),
          ]));
    final eng = SyncEngine(queue: queue, api: api, clock: clock,
        backoff: deterministicBackoff(), maxBatch: 4);
    for (var i = 0; i < 4; i++) {
      queue.append(transition(Transition.enter, t0), now: t0);
    }
    await eng.syncOnce();
    expect(eng.maxBatch, 2);
    for (var i = 0; i < 3; i++) {
      clock.advance(const Duration(hours: 1));
      await eng.syncOnce();
    }
    expect(states().every((s) => s == DeliveryState.received), isTrue);
  });

  group('reinício do processo', () {
    test('processo morre com lote em voo: lease expira e reenvia; sequência continua',
        () async {
      queue.append(transition(Transition.enter, t0), now: t0);
      queue.append(transition(Transition.exit, t0), now: t0);
      queue.lease(max: 10, now: t0, leaseUntil: t0.add(const Duration(minutes: 2)));
      expect(states(), [DeliveryState.sending, DeliveryState.sending]);
      queue.close(); // "morte" sem settle

      queue = SqliteEventQueue.open(tmp.path);
      engine = SyncEngine(queue: queue, api: server, clock: clock,
          backoff: deterministicBackoff());

      // Lease ainda válido: não reenvia (pode haver outro isolate enviando).
      expect((await engine.syncOnce()).halt, SyncHalt.nothingToSend);

      clock.advance(const Duration(minutes: 3));
      final r = await engine.syncOnce();
      expect(r.received, 2);

      final novo = queue.append(transition(Transition.enter, clock.now()),
          now: clock.now());
      expect(novo.installationSequence, 3); // nunca reutiliza
    });

    test('installationId é estável entre reaberturas', () {
      final id = queue.installationId;
      queue.close();
      queue = SqliteEventQueue.open(tmp.path, installationId: 'outro');
      expect(queue.installationId, id);
    });
  });
}

class _ScriptedApi implements PresenceApi {
  _ScriptedApi(this._fn);
  final BatchResponse Function(List<String>) _fn;
  @override
  Future<BatchResponse> submitBatch(List<String> payloadsJson) async =>
      _fn(payloadsJson);
}
