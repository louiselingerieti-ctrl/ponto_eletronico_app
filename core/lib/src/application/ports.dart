import '../domain/presence_event.dart';
import '../domain/queued_event.dart';

/// Fila local (outbox). Toda operação é transacional.
abstract interface class EventQueue {
  /// Atribui `eventId` e `installationSequence`, congela o payload e faz o
  /// commit. Só retorna depois do commit: quem chama pode então informar
  /// "registrado no aparelho".
  QueuedEvent append(PresenceEventDraft draft, {required DateTime now});

  /// Reserva até [max] eventos prontos para envio (ordem de sequência),
  /// marcando-os como `sending` com lease até [leaseUntil].
  List<QueuedEvent> lease({
    required int max,
    required DateTime now,
    required DateTime leaseUntil,
  });

  /// Aplica os resultados do servidor e devolve ao estado `savedLocally`
  /// (com próxima tentativa) os eventos do lote que ficaram sem resultado.
  void settle({
    required List<String> leasedIds,
    required Map<String, EventOutcome> outcomes,
    required DateTime retryAt,
  });

  /// Devolve o lote inteiro para a fila sem alterar o conteúdo.
  void release(List<String> leasedIds, {required DateTime retryAt});

  /// Leases vencidos (processo morto no meio do envio) voltam para a fila.
  int recoverExpiredLeases(DateTime now);

  List<QueuedEvent> all();

  /// Data do próximo envio agendado, se houver pendentes.
  DateTime? nextAttemptAt();
}

enum OutcomeKind { accepted, duplicate, conflict, rejected }

class EventOutcome {
  const EventOutcome({
    required this.eventId,
    required this.kind,
    this.receiptId,
    this.receivedAt,
    this.code,
  });

  final String eventId;
  final OutcomeKind kind;
  final String? receiptId;
  final DateTime? receivedAt;
  final String? code;
}

/// Resposta do servidor a um lote.
sealed class BatchResponse {
  const BatchResponse();
}

/// 200: um resultado por evento (o app casa por `eventId`, não por posição).
final class BatchResults extends BatchResponse {
  const BatchResults(this.outcomes);
  final List<EventOutcome> outcomes;
}

/// Erro do lote inteiro: nada foi gravado no servidor.
final class BatchFailure extends BatchResponse {
  const BatchFailure(this.reason, {this.retryAfter, this.code});
  final BatchFailureReason reason;
  final Duration? retryAfter;
  final String? code;
}

enum BatchFailureReason {
  /// Sem resposta / rede / 503 / 5xx: reenviar o MESMO lote com backoff.
  transient,

  /// 429: respeitar Retry-After.
  rateLimited,

  /// 413: lote grande demais; reduzir.
  payloadTooLarge,

  /// 401: sessão inválida. Eventos ficam no aparelho (política D-DEV-2).
  unauthenticated,

  /// 403 installation_revoked / installation_not_owned.
  forbidden,

  /// 400 envelope fora do contrato: defeito do app; não insistir.
  invalidEnvelope,
}

/// Cliente do endpoint `POST /v1/me/presence-events/batch` (rascunho).
/// Uma exceção lançada significa "sem resposta conhecida" (inclui timeout
/// depois do commit no servidor) e é tratada como [BatchFailureReason.transient].
abstract interface class PresenceApi {
  Future<BatchResponse> submitBatch(List<String> payloadsJson);
}

abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now().toUtc();
}
