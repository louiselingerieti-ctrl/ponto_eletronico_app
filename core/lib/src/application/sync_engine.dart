import '../domain/queued_event.dart';
import 'backoff.dart';
import 'ports.dart';

enum SyncHalt { none, nothingToSend, unauthenticated, forbidden, invalidEnvelope }

class SyncReport {
  const SyncReport({
    required this.sent,
    required this.received,
    required this.conflicts,
    required this.rejected,
    required this.unanswered,
    required this.halt,
    this.failure,
  });

  final int sent;
  final int received;
  final int conflicts;
  final int rejected;

  /// Eventos do lote sem resultado na resposta (ACK parcial) ou lote sem
  /// resposta. Voltam para a fila.
  final int unanswered;
  final SyncHalt halt;
  final BatchFailureReason? failure;
}

/// Envia a fila em lotes. Nunca apaga, reordena ou deduplica eventos: só
/// muda o estado de entrega a partir do que o servidor confirmou.
class SyncEngine {
  SyncEngine({
    required EventQueue queue,
    required PresenceApi api,
    required Clock clock,
    Backoff? backoff,
    this.maxBatch = 100,
    this.leaseDuration = const Duration(minutes: 2),
  })  : _queue = queue,
        _api = api,
        _clock = clock,
        _backoff = backoff ?? Backoff();

  final EventQueue _queue;
  final PresenceApi _api;
  final Clock _clock;
  final Backoff _backoff;

  /// Limite do contrato: 100 eventos (e 256 KiB) por lote.
  int maxBatch;
  final Duration leaseDuration;

  int _consecutiveFailures = 0;

  Future<SyncReport> syncOnce() async {
    final now = _clock.now();
    _queue.recoverExpiredLeases(now);
    final batch = _queue.lease(
        max: maxBatch, now: now, leaseUntil: now.add(leaseDuration));
    if (batch.isEmpty) {
      return const SyncReport(
          sent: 0, received: 0, conflicts: 0, rejected: 0, unanswered: 0,
          halt: SyncHalt.nothingToSend);
    }
    final ids = [for (final e in batch) e.eventId];

    BatchResponse response;
    try {
      response = await _api.submitBatch([for (final e in batch) e.payloadJson]);
    } catch (_) {
      // Sem resposta: o servidor pode ou não ter feito commit. Reenviar o
      // mesmo conteúdo é seguro (idempotência por eventId).
      response = const BatchFailure(BatchFailureReason.transient);
    }

    switch (response) {
      case BatchResults(:final outcomes):
        final byId = {
          for (final o in outcomes)
            if (ids.contains(o.eventId)) o.eventId: o,
        };
        final missing = ids.length - byId.length;
        _consecutiveFailures = missing > 0 ? _consecutiveFailures + 1 : 0;
        _queue.settle(
          leasedIds: ids,
          outcomes: byId,
          retryAt: now.add(_backoff.delay(_consecutiveFailures.clamp(1, 1 << 20))),
        );
        int count(OutcomeKind k) => byId.values.where((o) => o.kind == k).length;
        return SyncReport(
          sent: ids.length,
          received: count(OutcomeKind.accepted) + count(OutcomeKind.duplicate),
          conflicts: count(OutcomeKind.conflict),
          rejected: count(OutcomeKind.rejected),
          unanswered: missing,
          halt: SyncHalt.none,
        );

      case BatchFailure(:final reason, :final retryAfter):
        _consecutiveFailures++;
        final halt = switch (reason) {
          BatchFailureReason.unauthenticated => SyncHalt.unauthenticated,
          BatchFailureReason.forbidden => SyncHalt.forbidden,
          BatchFailureReason.invalidEnvelope => SyncHalt.invalidEnvelope,
          _ => SyncHalt.none,
        };
        if (reason == BatchFailureReason.payloadTooLarge && maxBatch > 1) {
          maxBatch = (maxBatch / 2).ceil();
        }
        _queue.release(ids,
            retryAt: now.add(
                _backoff.delay(_consecutiveFailures, retryAfter: retryAfter)));
        return SyncReport(
          sent: ids.length, received: 0, conflicts: 0, rejected: 0,
          unanswered: ids.length, halt: halt, failure: reason);
    }
  }

  /// Contagem por estado, para a tela de diagnóstico.
  Map<DeliveryState, int> summary() {
    final m = {for (final s in DeliveryState.values) s: 0};
    for (final e in _queue.all()) {
      m[e.state] = m[e.state]! + 1;
    }
    return m;
  }
}
