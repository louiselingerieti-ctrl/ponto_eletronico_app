import 'package:meta/meta.dart';

/// Etapas de entrega vistas pelo aparelho. Cada uma tem significado próprio:
///
/// - [savedLocally]: commit na fila local. Só a partir daqui o app pode dizer
///   "registrado no aparelho".
/// - [sending]: em voo, com lease recuperável (se o processo morrer, o lease
///   expira e o evento volta a [savedLocally]).
/// - [received]: o servidor respondeu `accepted` ou `duplicate` DEPOIS do
///   commit dele. Não significa "ponto aprovado" nem "dentro da área".
/// - [conflict]: mesmo `eventId` com outro conteúdo no servidor. O evento é
///   mantido para análise e nunca reenviado.
/// - [rejected]: recusa permanente com código. Mantido, nunca reenviado igual.
///
/// "Avaliado" (inside/outside/needs_review…) vem de outra consulta
/// (`GET /v1/me/presence-events`) e não é estado de entrega.
enum DeliveryState { savedLocally, sending, received, conflict, rejected }

@immutable
class QueuedEvent {
  const QueuedEvent({
    required this.eventId,
    required this.installationSequence,
    required this.payloadJson,
    required this.state,
    required this.attempts,
    required this.savedAt,
    this.nextAttemptAt,
    this.receiptId,
    this.serverReceivedAt,
    this.outcomeCode,
  });

  final String eventId;
  final int installationSequence;

  /// Forma de fio congelada na gravação.
  final String payloadJson;
  final DeliveryState state;
  final int attempts;

  /// Relógio do aparelho quando a fila confirmou o commit local.
  final DateTime savedAt;
  final DateTime? nextAttemptAt;
  final String? receiptId;

  /// `receivedAt` do servidor (commit do recebimento ORIGINAL).
  final DateTime? serverReceivedAt;
  final String? outcomeCode;
}
