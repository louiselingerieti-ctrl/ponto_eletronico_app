import '../domain/presence_event.dart';
import '../domain/queued_event.dart';

/// Lote reservado. O [token] identifica ESTA reserva: só quem a detém pode
/// concluir ou devolver os eventos (evita que um envio atrasado, de outro
/// isolate, mexa num lote já reservado por outro).
class LeasedBatch {
  const LeasedBatch(this.token, this.events);
  final String token;
  final List<QueuedEvent> events;
}

/// Parada persistida do envio. Só é retirada por [EventQueue.clearHalt],
/// chamada explicitamente (nova autenticação, atualização do app…).
enum DeliveryHaltReason {
  unauthenticated,
  forbidden,
  invalidEnvelope,
  payloadTooLargeSingle,
  internalDefect,
}

class DeliveryHalt {
  const DeliveryHalt(this.reason, this.at, {this.detail});
  final DeliveryHaltReason reason;
  final DateTime at;
  final String? detail;
}

/// Fila local (outbox). Toda operação é transacional.
abstract interface class EventQueue {
  /// Atribui `eventId` e `installationSequence`, congela o payload e faz o
  /// commit. Só retorna depois do commit. [captureFlags] é contexto LOCAL
  /// (não entra no payload do contrato).
  QueuedEvent append(PresenceEventDraft draft,
      {required DateTime now, Set<String> captureFlags = const {}});

  LeasedBatch lease({
    required int max,
    required DateTime now,
    required DateTime leaseUntil,
  });

  void settle({
    required String token,
    required Map<String, EventOutcome> outcomes,
    required DateTime retryAt,
  });

  void release(String token, {required DateTime retryAt});

  int recoverExpiredLeases(DateTime now);

  List<QueuedEvent> all();

  DateTime? nextAttemptAt();

  /// Contexto local gravado com o evento (fora do payload).
  Set<String> captureFlagsOf(String eventId);

  // Estado de entrega persistido (sobrevive a reinício).
  int consecutiveFailures();
  void setConsecutiveFailures(int n);
  DeliveryHalt? deliveryHalt();
  void haltDelivery(DeliveryHalt halt);
  void clearHalt();
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
  /// 503 / 5xx com resposta: reenviar o MESMO lote com backoff.
  serverUnavailable,
  rateLimited,
  payloadTooLarge,
  unauthenticated,
  forbidden,
  invalidEnvelope,
}

/// Falha de transporte: sem resposta conhecida (o servidor pode ou não ter
/// feito commit). O adaptador HTTP deve converter erros de rede/timeout/TLS
/// nesta exceção. QUALQUER outra exceção é tratada como defeito interno.
final class TransportException implements Exception {
  const TransportException(this.kind, [this.message]);
  final TransportFailure kind;
  final String? message;
  @override
  String toString() => 'TransportException(${kind.name})';
}

enum TransportFailure { network, timeout, tls }

/// Cliente do endpoint `POST /v1/me/presence-events/batch` (rascunho).
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
