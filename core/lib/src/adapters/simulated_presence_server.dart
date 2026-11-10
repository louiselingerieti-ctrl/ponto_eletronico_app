import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../application/ports.dart';

/// ============================================================
///  SERVIDOR SIMULADO — NÃO É O BACKEND REAL.
/// ============================================================
/// Reproduz, em memória, as regras de RECEBIMENTO do rascunho
/// `presenca-v1` (seções 4 e 5) para testar o app. Não avalia política, não
/// cria marcação e não representa o comportamento implementado no backend
/// (que, em 10/11/2026, não tinha nenhuma dessas rotas).
class SimulatedPresenceServer implements PresenceApi {
  SimulatedPresenceServer({
    required Set<String> ownedEmploymentLinks,
    required DateTime Function() clock,
  })  : _owned = ownedEmploymentLinks,
        _clock = clock;

  final Set<String> _owned;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  /// eventId → registro gravado ("commit").
  final Map<String, StoredEvent> stored = {};
  final Map<int, String> _seqOwner = {};
  final List<(int, int)> sequenceGaps = [];
  final List<String> conflictIncidents = [];
  int submitCalls = 0;

  /// Falhas a aplicar nas próximas chamadas, em ordem.
  final List<Fault> faults = [];

  @override
  Future<BatchResponse> submitBatch(List<String> payloadsJson) async {
    submitCalls++;
    final fault = faults.isEmpty ? null : faults.removeAt(0);

    switch (fault) {
      case NetworkDown():
        throw const SocketLikeException('rede indisponível (simulado)');
      case FailBeforeCommit():
        return const BatchFailure(BatchFailureReason.transient); // 503
      case RateLimited(:final retryAfter):
        return BatchFailure(BatchFailureReason.rateLimited, retryAfter: retryAfter);
      case Unauthenticated():
        return const BatchFailure(BatchFailureReason.unauthenticated);
      case InstallationRevoked():
        return const BatchFailure(BatchFailureReason.forbidden,
            code: 'installation_revoked');
      case _:
    }
    if (payloadsJson.length > 100) {
      return const BatchFailure(BatchFailureReason.payloadTooLarge);
    }

    // "Transação": cada item independente (savepoint por item).
    final outcomes = <EventOutcome>[];
    for (final raw in payloadsJson) {
      outcomes.add(_receive(raw));
    }

    switch (fault) {
      case TimeoutAfterCommit():
        throw TimeoutException('timeout depois do commit (simulado)');
      case PartialAck(:final omit):
        return BatchResults(
            [for (final o in outcomes) if (!omit.contains(o.eventId)) o]);
      case _:
        return BatchResults(outcomes);
    }
  }

  EventOutcome _receive(String raw) {
    final Map<String, Object?> e;
    try {
      e = (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (_) {
      return const EventOutcome(
          eventId: '', kind: OutcomeKind.rejected, code: 'invalid_event');
    }
    final id = e['eventId'] as String;
    final seq = e['installationSequence'] as int;
    final hash = _canonical(e);

    final existing = stored[id];
    if (existing != null) {
      if (existing.canonical == hash) {
        return EventOutcome(
            eventId: id, kind: OutcomeKind.duplicate,
            receiptId: existing.receiptId, receivedAt: existing.receivedAt);
      }
      conflictIncidents.add(id); // original preservado
      return EventOutcome(eventId: id, kind: OutcomeKind.conflict,
          code: 'content_mismatch');
    }
    if (e['schemaVersion'] != 1) {
      return EventOutcome(eventId: id, kind: OutcomeKind.rejected,
          code: 'unsupported_schema_version');
    }
    if (!_owned.contains(e['employmentLinkId'])) {
      return EventOutcome(eventId: id, kind: OutcomeKind.rejected,
          code: 'link_not_owned');
    }
    final owner = _seqOwner[seq];
    if (owner != null && owner != id) {
      return EventOutcome(eventId: id, kind: OutcomeKind.rejected,
          code: 'sequence_reused');
    }
    final maxSeq = _seqOwner.keys.fold<int>(0, (a, b) => a > b ? a : b);
    if (seq > maxSeq + 1) sequenceGaps.add((maxSeq, seq));

    final rec = StoredEvent(
      canonical: hash, receiptId: _uuid.v4(), receivedAt: _clock(),
      sequence: seq, body: e);
    stored[id] = rec;
    _seqOwner[seq] = id;
    return EventOutcome(eventId: id, kind: OutcomeKind.accepted,
        receiptId: rec.receiptId, receivedAt: rec.receivedAt);
  }

  static String _canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(v[k])}').join(',')}}';
    }
    if (v is List) return '[${v.map(_canonical).join(',')}]';
    return jsonEncode(v);
  }
}

class StoredEvent {
  StoredEvent({
    required this.canonical,
    required this.receiptId,
    required this.receivedAt,
    required this.sequence,
    required this.body,
  });
  final String canonical;
  final String receiptId;
  final DateTime receivedAt;
  final int sequence;
  final Map<String, Object?> body;
}

sealed class Fault {
  const Fault();
}

final class NetworkDown extends Fault {
  const NetworkDown();
}

final class FailBeforeCommit extends Fault {
  const FailBeforeCommit();
}

final class TimeoutAfterCommit extends Fault {
  const TimeoutAfterCommit();
}

final class PartialAck extends Fault {
  const PartialAck(this.omit);
  final Set<String> omit;
}

final class RateLimited extends Fault {
  const RateLimited(this.retryAfter);
  final Duration retryAfter;
}

final class Unauthenticated extends Fault {
  const Unauthenticated();
}

final class InstallationRevoked extends Fault {
  const InstallationRevoked();
}

class SocketLikeException implements Exception {
  const SocketLikeException(this.message);
  final String message;
  @override
  String toString() => 'SocketLikeException: $message';
}
