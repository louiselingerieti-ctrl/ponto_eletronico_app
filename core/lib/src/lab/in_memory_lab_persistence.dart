import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../application/persistence.dart';
import '../application/ports.dart';
import '../domain/clock_quality.dart';
import '../domain/presence_config.dart';
import '../domain/presence_event.dart';
import '../domain/queued_event.dart';

/// ================================================================
///  PERSISTÊNCIA DE LABORATÓRIO — EM MEMÓRIA, SEM CIFRA, SEM DISCO.
/// ================================================================
/// Só para o laboratório web e testes. Recarregar a página apaga tudo.
/// NÃO substitui nem valida `LocalStore` (SQLite cifrado): não há chave,
/// não há arquivo e não há durabilidade. Reproduz apenas a SEMÂNTICA da
/// fila e da configuração (transações, sequência, token de reserva,
/// imutabilidade do conteúdo), para exercitar os casos de uso.
class InMemoryLabPersistence implements LocalPersistence {
  InMemoryLabPersistence({String? installationId})
      : installationId = installationId ?? const Uuid().v4();

  @override
  final String installationId;
  @override
  late final EventQueue queue = _LabQueue(this);
  @override
  late final ConfigRepository configs = _LabConfigs(this);

  @override
  bool get isEncryptedAtRest => false;

  _State _state = _State();
  final List<_State> _snapshots = [];

  @override
  T tx<T>(T Function() body) {
    _snapshots.add(_state.copy());
    try {
      final r = body();
      _snapshots.removeLast();
      return r;
    } catch (_) {
      _state = _snapshots.removeLast(); // desfaz tudo deste nível
      rethrow;
    }
  }
}

class _EventRow {
  _EventRow(this.eventId, this.seq, this.payload, this.savedAt, this.flags)
      : nextAttemptAt = savedAt;
  final String eventId;
  final int seq;
  final String payload;
  final DateTime savedAt;
  final Set<String> flags;
  DeliveryState state = DeliveryState.savedLocally;
  int attempts = 0;
  DateTime? nextAttemptAt;
  String? leaseToken;
  DateTime? leaseUntil;
  String? receiptId;
  DateTime? serverReceivedAt;
  String? outcomeCode;

  _EventRow copy() => _EventRow(eventId, seq, payload, savedAt, flags)
    ..state = state
    ..attempts = attempts
    ..nextAttemptAt = nextAttemptAt
    ..leaseToken = leaseToken
    ..leaseUntil = leaseUntil
    ..receiptId = receiptId
    ..serverReceivedAt = serverReceivedAt
    ..outcomeCode = outcomeCode;

  QueuedEvent view() => QueuedEvent(
        eventId: eventId, installationSequence: seq, payloadJson: payload,
        state: state, attempts: attempts, savedAt: savedAt,
        nextAttemptAt: nextAttemptAt, receiptId: receiptId,
        serverReceivedAt: serverReceivedAt, outcomeCode: outcomeCode,
      );
}

class _ConfigRow {
  _ConfigRow(this.c);
  StoredConfig c;
  ServerTimeReference? ref;
  _ConfigRow copy() => _ConfigRow(c)..ref = ref;
}

class _State {
  final List<_EventRow> events = [];
  int nextSeq = 1;
  int failures = 0;
  DeliveryHalt? halt;
  final List<_ConfigRow> configs = [];
  final Map<String, Revocation> revocations = {};

  _State copy() {
    final s = _State()
      ..nextSeq = nextSeq
      ..failures = failures
      ..halt = halt;
    s.events.addAll(events.map((e) => e.copy()));
    s.configs.addAll(configs.map((c) => c.copy()));
    s.revocations.addAll(revocations);
    return s;
  }
}

class _LabQueue implements EventQueue {
  _LabQueue(this._p);
  final InMemoryLabPersistence _p;
  _State get _s => _p._state;
  static const _uuid = Uuid();

  @override
  QueuedEvent append(PresenceEventDraft draft,
      {required DateTime now, Set<String> captureFlags = const {}}) {
    return _p.tx(() {
      final seq = _s.nextSeq;
      final id = _uuid.v4();
      final payload =
          jsonEncode(draft.toContractJson(eventId: id, installationSequence: seq));
      final row = _EventRow(id, seq, payload, now.toUtc(), Set.unmodifiable(captureFlags));
      _s.events.add(row);
      _s.nextSeq = seq + 1;
      return row.view();
    });
  }

  @override
  LeasedBatch lease({required int max, required DateTime now, required DateTime leaseUntil}) {
    return _p.tx(() {
      final token = _uuid.v4();
      final ready = _s.events
          .where((e) =>
              e.state == DeliveryState.savedLocally &&
              (e.nextAttemptAt == null || !e.nextAttemptAt!.isAfter(now)))
          .take(max)
          .toList();
      for (final e in ready) {
        e
          ..state = DeliveryState.sending
          ..attempts += 1
          ..leaseToken = token
          ..leaseUntil = leaseUntil;
      }
      return LeasedBatch(token, [for (final e in ready) e.view()]);
    });
  }

  Iterable<_EventRow> _leased(String token) => _s.events
      .where((e) => e.state == DeliveryState.sending && e.leaseToken == token);

  @override
  void settle({
    required String token,
    required Map<String, EventOutcome> outcomes,
    required DateTime retryAt,
  }) {
    _p.tx(() {
      for (final e in _leased(token).toList()) {
        final o = outcomes[e.eventId];
        if (o == null) {
          _back(e, retryAt);
          continue;
        }
        e
          ..state = switch (o.kind) {
            OutcomeKind.accepted || OutcomeKind.duplicate => DeliveryState.received,
            OutcomeKind.conflict => DeliveryState.conflict,
            OutcomeKind.rejected => DeliveryState.rejected,
          }
          ..leaseToken = null
          ..leaseUntil = null
          ..nextAttemptAt = null
          ..receiptId = o.receiptId
          ..serverReceivedAt = o.receivedAt
          ..outcomeCode = o.code ?? (o.kind == OutcomeKind.duplicate ? 'duplicate' : null);
      }
    });
  }

  void _back(_EventRow e, DateTime retryAt) => e
    ..state = DeliveryState.savedLocally
    ..leaseToken = null
    ..leaseUntil = null
    ..nextAttemptAt = retryAt;

  @override
  void release(String token, {required DateTime retryAt}) =>
      _p.tx(() => _leased(token).toList().forEach((e) => _back(e, retryAt)));

  @override
  int recoverExpiredLeases(DateTime now) => _p.tx(() {
        var n = 0;
        for (final e in _s.events) {
          if (e.state == DeliveryState.sending && !e.leaseUntil!.isAfter(now)) {
            e
              ..state = DeliveryState.savedLocally
              ..leaseToken = null
              ..leaseUntil = null;
            n++;
          }
        }
        return n;
      });

  @override
  List<QueuedEvent> all() => [for (final e in _s.events) e.view()];

  @override
  DateTime? nextAttemptAt() {
    DateTime? m;
    for (final e in _s.events) {
      if (e.state != DeliveryState.savedLocally || e.nextAttemptAt == null) continue;
      if (m == null || e.nextAttemptAt!.isBefore(m)) m = e.nextAttemptAt;
    }
    return m;
  }

  @override
  Set<String> captureFlagsOf(String eventId) =>
      _s.events.where((e) => e.eventId == eventId).firstOrNull?.flags ?? const {};

  @override
  int consecutiveFailures() => _s.failures;
  @override
  void setConsecutiveFailures(int n) => _p.tx(() => _s.failures = n);
  @override
  DeliveryHalt? deliveryHalt() => _s.halt;
  @override
  void haltDelivery(DeliveryHalt halt) => _p.tx(() => _s.halt = halt);
  @override
  void clearHalt() => _p.tx(() => _s.halt = null);
}

class _LabConfigs implements ConfigRepository {
  _LabConfigs(this._p);
  final InMemoryLabPersistence _p;
  _State get _s => _p._state;

  _ConfigRow? _row(String link, String rev) => _s.configs
      .where((r) => r.c.config.employmentLinkId == link && r.c.config.configRevision == rev)
      .firstOrNull;

  @override
  StoredConfig? current(String linkId) => _s.configs
      .where((r) => r.c.config.employmentLinkId == linkId && r.c.supersededAt == null)
      .firstOrNull
      ?.c;

  @override
  StoredConfig? byRevision(String linkId, String revision) => _row(linkId, revision)?.c;

  @override
  List<StoredConfig> history(String linkId) => [
        for (final r in _s.configs
            .where((r) => r.c.config.employmentLinkId == linkId)
            .toList()
          ..sort((a, b) => a.c.config.serverTime.compareTo(b.c.config.serverTime)))
          r.c,
      ];

  @override
  void insertCurrent(PresenceConfig c,
      {required String rawJson,
      required DateTime receivedAt,
      required DateTime persistedAt,
      required ServerTimeReference? reference}) {
    _p.tx(() {
      if (_row(c.employmentLinkId, c.configRevision) != null) {
        throw StateError('revisão já gravada');
      }
      for (final r in _s.configs) {
        if (r.c.config.employmentLinkId == c.employmentLinkId && r.c.supersededAt == null) {
          r.c = _with(r.c, supersededAt: persistedAt);
        }
      }
      _s.configs.add(_ConfigRow(StoredConfig(
          config: c, rawJson: rawJson, receivedAt: receivedAt,
          persistedAt: persistedAt, stage: ApplyStage.persisted))
        ..ref = reference);
    });
  }

  @override
  void setApplyResult(String linkId, String revision,
      {required ApplyStage stage, required DateTime at, String? detail, String? eventId}) {
    final r = _row(linkId, revision);
    if (r == null) return;
    r.c = StoredConfig(
      config: r.c.config, rawJson: r.c.rawJson, receivedAt: r.c.receivedAt,
      persistedAt: r.c.persistedAt, stage: stage,
      appliedAt: stage == ApplyStage.applied ? at : null, applyDetail: detail,
      supersededAt: r.c.supersededAt, applyEventId: eventId,
      expiredEventId: r.c.expiredEventId,
    );
  }

  @override
  void setExpiredEvent(String linkId, String revision, String eventId) {
    final r = _row(linkId, revision);
    if (r == null || r.c.expiredEventId != null) return;
    r.c = _with(r.c, expiredEventId: eventId);
  }

  @override
  ServerTimeReference? latestClockReference() {
    final withRef = _s.configs.where((r) => r.ref != null).toList()
      ..sort((a, b) => b.c.persistedAt.compareTo(a.c.persistedAt));
    return withRef.firstOrNull?.ref;
  }

  @override
  Revocation? activeRevocation(String linkId) => _s.revocations[linkId];

  @override
  void revoke(String linkId, {required String reason, required DateTime at}) =>
      _s.revocations.putIfAbsent(linkId, () => Revocation(linkId, at, reason));

  @override
  void liftRevocation(String linkId, {required DateTime at}) =>
      _s.revocations.remove(linkId);

  static StoredConfig _with(StoredConfig c, {DateTime? supersededAt, String? expiredEventId}) =>
      StoredConfig(
        config: c.config, rawJson: c.rawJson, receivedAt: c.receivedAt,
        persistedAt: c.persistedAt, stage: c.stage, appliedAt: c.appliedAt,
        applyDetail: c.applyDetail, supersededAt: supersededAt ?? c.supersededAt,
        applyEventId: c.applyEventId, expiredEventId: expiredEventId ?? c.expiredEventId,
      );
}
