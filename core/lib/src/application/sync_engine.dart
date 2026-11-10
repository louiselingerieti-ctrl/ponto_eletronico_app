import '../domain/queued_event.dart';
import 'backoff.dart';
import 'ports.dart';

/// Classes de falha. Só [transient] gera nova tentativa automática.
enum FailureClass {
  /// Rede, timeout, 503/5xx, 429, 413 (com lote redutível).
  transient,

  /// 401/403: para o envio até [SyncEngine.resume] explícito.
  authOrPermission,

  /// 400 de envelope, 413 com lote de 1, ou resposta 200 fora do contrato.
  contractRejection,

  /// Exceção inesperada no adaptador/app: para o envio e registra o tipo.
  internalDefect,
}

class SyncReport {
  const SyncReport({
    this.sent = 0,
    this.received = 0,
    this.conflicts = 0,
    this.rejected = 0,
    this.unanswered = 0,
    this.anomalies = const [],
    this.failure,
    this.halt,
    this.nothingToSend = false,
  });

  final int sent;
  final int received;
  final int conflicts;
  final int rejected;

  /// Eventos do lote sem resultado válido. Voltam para a fila.
  final int unanswered;

  /// Desvios do contrato na resposta 200 (resultado sem recibo, eventId
  /// estranho ou repetido…). Não são silenciados.
  final List<String> anomalies;
  final FailureClass? failure;

  /// Parada vigente (nova ou anterior). Com parada, nada é enviado.
  final DeliveryHalt? halt;
  final bool nothingToSend;
}

/// Envia a fila em lotes. Nunca apaga, reordena ou deduplica eventos: só
/// muda o estado de entrega a partir do que o servidor confirmou.
class SyncEngine {
  SyncEngine({
    required this.queue,
    required this.api,
    required this.clock,
    Backoff? backoff,
    this.maxBatch = 100,
    this.leaseDuration = const Duration(minutes: 2),
  }) : backoff = backoff ?? Backoff();

  final EventQueue queue;
  final PresenceApi api;
  final Clock clock;
  final Backoff backoff;

  /// Limite do contrato: 100 eventos (e 256 KiB) por lote.
  int maxBatch;
  final Duration leaseDuration;

  /// Retira a parada. Quem chama decide quando (nova sessão, app atualizado);
  /// essa política não está no núcleo.
  void resume() => queue.clearHalt();

  Future<SyncReport> syncOnce() async {
    final existing = queue.deliveryHalt();
    if (existing != null) return SyncReport(halt: existing);

    final now = clock.now();
    queue.recoverExpiredLeases(now);
    final batch = queue.lease(
        max: maxBatch, now: now, leaseUntil: now.add(leaseDuration));
    if (batch.events.isEmpty) return const SyncReport(nothingToSend: true);
    final ids = [for (final e in batch.events) e.eventId];

    final BatchResponse response;
    try {
      response = await api.submitBatch([for (final e in batch.events) e.payloadJson]);
    } on TransportException {
      // Sem resposta: o servidor pode ou não ter feito commit. Reenviar o
      // mesmo conteúdo é seguro (idempotência por eventId).
      return _retry(batch.token, ids.length, now, FailureClass.transient);
    } catch (e) {
      // Defeito: não vira retry silencioso. Eventos voltam intactos à fila.
      queue.release(batch.token, retryAt: now);
      final halt = DeliveryHalt(DeliveryHaltReason.internalDefect, now,
          detail: e.runtimeType.toString());
      queue.haltDelivery(halt);
      return SyncReport(sent: ids.length, unanswered: ids.length,
          failure: FailureClass.internalDefect, halt: halt);
    }

    switch (response) {
      case BatchResults(:final outcomes):
        return _settle(batch.token, ids, outcomes, now);
      case BatchFailure(:final reason, :final retryAfter, :final code):
        switch (reason) {
          case BatchFailureReason.serverUnavailable:
          case BatchFailureReason.rateLimited:
            return _retry(batch.token, ids.length, now, FailureClass.transient,
                retryAfter: retryAfter);
          case BatchFailureReason.payloadTooLarge:
            if (maxBatch > 1 && ids.length > 1) {
              maxBatch = (ids.length / 2).ceil();
              queue.release(batch.token, retryAt: now);
              return SyncReport(sent: ids.length, unanswered: ids.length,
                  failure: FailureClass.transient);
            }
            return _halt(batch.token, ids.length, now,
                DeliveryHaltReason.payloadTooLargeSingle, FailureClass.contractRejection);
          case BatchFailureReason.unauthenticated:
            return _halt(batch.token, ids.length, now,
                DeliveryHaltReason.unauthenticated, FailureClass.authOrPermission,
                detail: code);
          case BatchFailureReason.forbidden:
            return _halt(batch.token, ids.length, now,
                DeliveryHaltReason.forbidden, FailureClass.authOrPermission,
                detail: code);
          case BatchFailureReason.invalidEnvelope:
            return _halt(batch.token, ids.length, now,
                DeliveryHaltReason.invalidEnvelope, FailureClass.contractRejection,
                detail: code);
        }
    }
  }

  SyncReport _settle(
      String token, List<String> ids, List<EventOutcome> outcomes, DateTime now) {
    final idSet = ids.toSet();
    final anomalies = <String>[];
    final valid = <String, EventOutcome>{};
    final repeated = <String>{};
    for (final o in outcomes) {
      if (!idSet.contains(o.eventId)) {
        anomalies.add('resultado para evento fora do lote');
        continue;
      }
      if (valid.containsKey(o.eventId) || repeated.contains(o.eventId)) {
        repeated.add(o.eventId);
        valid.remove(o.eventId);
        anomalies.add('resultado repetido para o mesmo evento');
        continue;
      }
      final isReceipt = o.kind == OutcomeKind.accepted || o.kind == OutcomeKind.duplicate;
      if (isReceipt && (o.receiptId == null || o.receivedAt == null)) {
        // "Recebido" exige recibo do commit do servidor.
        anomalies.add('${o.kind.name} sem receiptId/receivedAt');
        continue;
      }
      if (o.kind == OutcomeKind.rejected && o.code == null) {
        anomalies.add('rejected sem código');
        continue;
      }
      valid[o.eventId] = o;
    }
    final missing = ids.length - valid.length;
    final failures = missing > 0 ? queue.consecutiveFailures() + 1 : 0;
    queue.setConsecutiveFailures(failures);
    queue.settle(
      token: token,
      outcomes: valid,
      retryAt: now.add(backoff.delay(failures < 1 ? 1 : failures)),
    );
    int count(OutcomeKind k) => valid.values.where((o) => o.kind == k).length;
    return SyncReport(
      sent: ids.length,
      received: count(OutcomeKind.accepted) + count(OutcomeKind.duplicate),
      conflicts: count(OutcomeKind.conflict),
      rejected: count(OutcomeKind.rejected),
      unanswered: missing,
      anomalies: anomalies,
      failure: anomalies.isNotEmpty ? FailureClass.contractRejection : null,
    );
  }

  SyncReport _retry(String token, int n, DateTime now, FailureClass c,
      {Duration? retryAfter}) {
    final failures = queue.consecutiveFailures() + 1;
    queue.setConsecutiveFailures(failures);
    queue.release(token,
        retryAt: now.add(backoff.delay(failures, retryAfter: retryAfter)));
    return SyncReport(sent: n, unanswered: n, failure: c);
  }

  SyncReport _halt(String token, int n, DateTime now, DeliveryHaltReason r,
      FailureClass c, {String? detail}) {
    queue.release(token, retryAt: now);
    final halt = DeliveryHalt(r, now, detail: detail);
    queue.haltDelivery(halt);
    return SyncReport(sent: n, unanswered: n, failure: c, halt: halt);
  }

  Map<DeliveryState, int> summary() {
    final m = {for (final s in DeliveryState.values) s: 0};
    for (final e in queue.all()) {
      m[e.state] = m[e.state]! + 1;
    }
    return m;
  }
}
