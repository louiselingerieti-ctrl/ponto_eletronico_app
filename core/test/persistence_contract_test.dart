import 'dart:convert';

import 'package:presenca_core/presenca_lab.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Os MESMOS cenários contra as duas persistências. Garante que o
/// laboratório em memória reproduz a semântica da base real — e só isso:
/// não valida cifra, disco nem durabilidade (cobertos por
/// encrypted_queue_test.dart, apenas para `LocalStore`).
void main() {
  final impls = <String, (LocalPersistence, void Function()) Function()>{
    'LocalStore (SQLite cifrado)': () {
      final tmp = TempDir();
      final s = openStore(tmp.path);
      return (s, () {
        s.close();
        tmp.dispose();
      });
    },
    'InMemoryLabPersistence (laboratório)': () =>
        (InMemoryLabPersistence(), () {}),
  };

  final t0 = DateTime.utc(2026, 11, 10, 11);

  for (final MapEntry(key: name, value: make) in impls.entries) {
    group(name, () {
      late LocalPersistence p;
      late void Function() dispose;
      late FakeClock clock;

      setUp(() {
        (p, dispose) = make();
        clock = FakeClock(t0);
      });
      tearDown(() => dispose());

      QueuedEvent add() =>
          p.queue.append(transition(Transition.enter, clock.now()), now: clock.now());

      test('declara corretamente se cifra em disco', () {
        expect(p.isEncryptedAtRest, name.startsWith('LocalStore'));
      });

      test('sequência crescente e rollback desfaz gravação e sequência', () {
        expect(add().installationSequence, 1);
        expect(() => p.tx(() {
              add();
              throw StateError('x');
            }), throwsStateError);
        expect(p.queue.all(), hasLength(1));
        expect(add().installationSequence, 2);
      });

      test('savepoint: falha interna capturada não desfaz o nível externo', () {
        p.tx(() {
          add();
          try {
            p.tx(() {
              add();
              throw StateError('interno');
            });
          } on StateError {
            // capturado
          }
          add();
        });
        expect([for (final e in p.queue.all()) e.installationSequence], [1, 2]);
      });

      test('token de reserva: só o dono conclui', () {
        final e = add();
        final a = p.queue.lease(max: 5, now: t0, leaseUntil: t0.add(const Duration(minutes: 1)));
        final t1 = t0.add(const Duration(minutes: 2));
        expect(p.queue.recoverExpiredLeases(t1), 1);
        final b = p.queue.lease(max: 5, now: t1, leaseUntil: t1.add(const Duration(minutes: 1)));
        p.queue.release(a.token, retryAt: t1);
        expect(p.queue.all().single.state, DeliveryState.sending);
        p.queue.settle(token: b.token, outcomes: {
          e.eventId: EventOutcome(eventId: e.eventId, kind: OutcomeKind.accepted,
              receiptId: 'r', receivedAt: t1),
        }, retryAt: t1);
        expect(p.queue.all().single.state, DeliveryState.received);
        expect(p.queue.all().single.payloadJson, e.payloadJson);
      });

      test('motor de envio: rede, ACK parcial, 401 e retomada', () async {
        final server = SimulatedPresenceServer(
            ownedEmploymentLinks: {linkA}, clock: () => clock.now());
        final engine = SyncEngine(
            queue: p.queue, api: server, clock: clock, backoff: deterministicBackoff());
        final a = add();
        final b = add();
        server.faults.add(const NetworkDown());
        expect((await engine.syncOnce()).failure, FailureClass.transient);
        clock.advance(const Duration(minutes: 1));
        server.faults.add(PartialAck({b.eventId}));
        expect((await engine.syncOnce()).unanswered, 1);
        server.faults.add(const Unauthenticated());
        clock.advance(const Duration(minutes: 1));
        expect((await engine.syncOnce()).halt!.reason, DeliveryHaltReason.unauthenticated);
        engine.resume();
        await engine.syncOnce();
        final byId = {for (final e in p.queue.all()) e.eventId: e};
        expect(byId[a.eventId]!.state, DeliveryState.received);
        expect(byId[b.eventId]!.outcomeCode, 'duplicate');
      });

      test('configuração: recebida → persistida → aplicada → detecção', () {
        final st = ClockStamper(configs: p.configs, policy: testClockPolicy,
            timeZone: () => 'America/Sao_Paulo');
        final lc = ConfigLifecycle(store: p, stamper: st, appVersion: 't');
        final rec = lc.receive(encode(configJson()), expectedLinkId: linkA, receivedAt: t0);
        expect(p.configs.current(linkA), isNull); // recebida não grava
        expect(lc.persist(rec, now: t0), isA<ConfigPersisted>());
        expect(lc.assess(linkA, now: t0).status, ConfigStatus.persisted);
        expect(lc.confirmApplied(linkA, 'cfg-1', registeredAreaIds: {areaCentro},
            sample: ClockSample(wall: t0)), isA<ConfigApplied>());
        final out = RecordDetection(
          store: p, stamper: st, appVersion: 't',
          policies: const PendingPolicies(
              expiredConfig: PendingCaseHandling.refuse,
              revokedLink: PendingCaseHandling.refuse,
              afterAuthLoss: PendingCaseHandling.refuse),
        )(GeofenceCallback(
            employmentLinkId: linkA, configRevision: 'cfg-1', areaId: areaCentro,
            areaRevision: 1, transition: Transition.exit,
            sample: ClockSample(wall: t0.add(const Duration(minutes: 1)))));
        expect(out, isA<Recorded>());
        final kinds = [
          for (final e in p.queue.all())
            (jsonDecode(e.payloadJson) as Map)['kind'] ?? '',
        ];
        expect(kinds, ['detection_status', 'area_transition']);
      });
    });
  }
}
