@TestOn('browser')
library;

import 'package:presenca_core/presenca_lab.dart';
import 'package:test/test.dart';

/// Roda DENTRO do navegador (`dart test -p chrome test/web`). Prova só que o
/// domínio, os casos de uso e os adaptadores de laboratório compilam e
/// funcionam na web. Não valida SQLite cifrado, Keystore, geofence ou
/// segundo plano.
void main() {
  test('fluxo de laboratório completo no navegador', () async {
    final t0 = DateTime.utc(2026, 11, 10, 11);
    var now = t0;
    final p = InMemoryLabPersistence();
    expect(p.isEncryptedAtRest, isFalse);
    final server = SimulatedPresenceServer(
        ownedEmploymentLinks: {'00000000-0000-4000-8000-00000000e001'},
        clock: () => now);
    final e = p.queue.append(
        AreaTransitionDraft(
          employmentLinkId: '00000000-0000-4000-8000-00000000e001',
          configRevision: 'cfg-1', appVersion: 'lab',
          clock: DeviceClock(detectedAt: t0, elapsedRealtimeMs: null, bootId: null,
              timeZone: 'America/Sao_Paulo', quality: ClockQuality.uncertain),
          areaId: 'a', areaRevision: 1, transition: Transition.enter),
        now: t0);
    final engine = SyncEngine(queue: p.queue, api: server, clock: _C(() => now));
    server.faults.add(const TimeoutAfterCommit());
    expect((await engine.syncOnce()).failure, FailureClass.transient);
    now = now.add(const Duration(hours: 1));
    await engine.syncOnce();
    final q = p.queue.all().single;
    expect(q.state, DeliveryState.received);
    expect(q.outcomeCode, 'duplicate');
    expect(q.receiptId, server.stored[e.eventId]!.receiptId);
  });
}

class _C implements Clock {
  _C(this._f);
  final DateTime Function() _f;
  @override
  DateTime now() => _f();
}
