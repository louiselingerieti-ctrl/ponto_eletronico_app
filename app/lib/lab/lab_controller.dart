import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:presenca_core/presenca_lab.dart';

import 'lab_scenario.dart';
import 'simulated_geofence_platform.dart';

/// Falha a aplicar no PRÓXIMO envio (uma vez). Ferramenta de laboratório.
enum NextSend { normal, networkDown, transient503, partialAck }

/// Resultado de avaliação ESCOLHIDO À MÃO. No sistema real quem avalia é o
/// servidor, com política versionada; aqui é fictício.
enum SimEvaluation { inside, outside, uncertain, needsReview }

/// Decisões pendentes que o laboratório precisa para rodar.
enum LabDecision { expiredConfig, revokedLink, afterAuthLoss }

enum ConfigStep { none, received, persisted, applied, applyFailed }

enum ReportTone { neutral, ok, error }

class LabReport {
  const LabReport(this.message, {this.detail, this.tone = ReportTone.neutral});
  final String message;
  final String? detail;
  final ReportTone tone;
}

/// Visão de um evento da fila para a tela.
class LabEventView {
  const LabEventView({
    required this.event,
    required this.payload,
    this.lastFailure,
    this.evaluation,
  });

  final QueuedEvent event;
  final Map<String, Object?> payload;
  final String? lastFailure;
  final SimEvaluation? evaluation;

  String get kind => payload['kind'] as String;
  bool get isTransition => kind == 'area_transition';
  bool get isDuplicate => event.outcomeCode == 'duplicate';
}

class LabController extends ChangeNotifier {
  LabController({DateTime Function()? now, this.sendDelay = const Duration(milliseconds: 700)})
      : _now = now ?? (() => DateTime.now().toUtc()) {
    server = SimulatedPresenceServer(
        ownedEmploymentLinks: {LabScenario.linkId}, clock: _now);
    final stamper = ClockStamper(
        configs: persistence.configs,
        policy: LabScenario.clockPolicy,
        timeZone: () => LabScenario.timeZone);
    _stamper = stamper;
    lifecycle = ConfigLifecycle(
        store: persistence, stamper: stamper, appVersion: LabScenario.appVersion);
    _api = _LabApi(this);
    engine = SyncEngine(
        queue: persistence.queue, api: _api, clock: _FnClock(_now),
        backoff: LabScenario.backoff());
  }

  final DateTime Function() _now;
  final Duration sendDelay;

  /// Memória do navegador: recarregar a página apaga tudo.
  final InMemoryLabPersistence persistence = InMemoryLabPersistence();
  late final SimulatedPresenceServer server;
  late final ConfigLifecycle lifecycle;
  late final SyncEngine engine;
  late final ClockStamper _stamper;
  late final _LabApi _api;
  final SimulatedGeofencePlatform platform = SimulatedGeofencePlatform();

  ConfigReceived? _received;
  ConfigStep get configStep {
    final a = lifecycle.assess(LabScenario.linkId, now: _now());
    return switch (a.status) {
      ConfigStatus.applied => ConfigStep.applied,
      ConfigStatus.applyFailed => ConfigStep.applyFailed,
      ConfigStatus.persisted => ConfigStep.persisted,
      ConfigStatus.none => _received != null ? ConfigStep.received : ConfigStep.none,
    };
  }

  DateTime? get receivedAt => _received?.receivedAt ??
      persistence.configs.current(LabScenario.linkId)?.receivedAt;
  DateTime? get persistedAt => persistence.configs.current(LabScenario.linkId)?.persistedAt;
  DateTime? get appliedAt => persistence.configs.current(LabScenario.linkId)?.appliedAt;
  DateTime? get validUntil =>
      (persistence.configs.current(LabScenario.linkId)?.config ?? _received?.config)?.validUntil;

  /// Escolhas válidas SÓ nesta simulação. Não são política aprovada.
  final Map<LabDecision, PendingCaseHandling> decisions = {
    for (final d in LabDecision.values) d: PendingCaseHandling.recordAndFlag,
  };

  NextSend nextSend = NextSend.normal;
  bool sending = false;
  String? generatorNotice;
  LabReport report = const LabReport('Nenhum envio ainda.');

  final Map<String, String> _lastFailure = {};
  final Map<String, SimEvaluation> _evaluations = {};
  Timer? _ticker;

  // ---- Configuração ----

  void receiveConfig() {
    _received = lifecycle.receive(LabScenario.configJson(_now()),
        expectedLinkId: LabScenario.linkId, receivedAt: _now());
    notifyListeners();
  }

  void persistConfig() {
    final r = _received;
    if (r == null) return;
    lifecycle.persist(r, now: _now());
    _received = null;
    notifyListeners();
  }

  void confirmApply() {
    final cur = persistence.configs.current(LabScenario.linkId);
    if (cur == null) return;
    final ids = platform.register(cur.config, _now());
    lifecycle.confirmApplied(LabScenario.linkId, cur.config.configRevision,
        registeredAreaIds: ids, sample: ClockSample(wall: _now()));
    notifyListeners();
  }

  void failApply() {
    final cur = persistence.configs.current(LabScenario.linkId);
    if (cur == null) return;
    lifecycle.reportApplyFailure(LabScenario.linkId, cur.config.configRevision,
        detail: 'falha simulada da plataforma', sample: ClockSample(wall: _now()));
    notifyListeners();
  }

  // ---- Geração sintética ----

  void generateTransition(Transition t) {
    final cb = configStep == ConfigStep.applied
        ? platform.syntheticTransition(LabScenario.areaId, t, _now())
        : null;
    if (cb == null) {
      generatorNotice = 'Aplique a configuração primeiro. Sem configuração aplicada '
          'não há área registrada para detectar.';
      notifyListeners();
      return;
    }
    final out = RecordDetection(
      store: persistence, stamper: _stamper, appVersion: LabScenario.appVersion,
      policies: _policies,
    )(cb);
    generatorNotice = switch (out) {
      Recorded() => null,
      Refused(:final reason, :final decision) => decision != null
          ? 'Não gravado: a opção "recusar" escolhida para $decision nesta simulação.'
          : 'Não gravado: ${reason.name}.',
    };
    notifyListeners();
  }

  void generateStatus(DetectionStatus s) {
    final cur = persistence.configs.current(LabScenario.linkId);
    if (cur == null) {
      generatorNotice = 'Persista a configuração primeiro: o evento precisa da revisão.';
      notifyListeners();
      return;
    }
    persistence.queue.append(
      DetectionStatusDraft(
        employmentLinkId: LabScenario.linkId,
        configRevision: cur.config.configRevision,
        appVersion: LabScenario.appVersion,
        clock: _stamper.stamp(ClockSample(wall: _now())),
        status: s,
      ),
      now: _now(),
    );
    generatorNotice = null;
    notifyListeners();
  }

  // ---- Envio ----

  Future<void> sendNow() async {
    if (sending) return;
    sending = true;
    _api.pendingFault = nextSend;
    _api.lastBatchIds = const [];
    notifyListeners();
    final r = await engine.syncOnce();
    nextSend = NextSend.normal;
    sending = false;
    _afterSync(r);
    notifyListeners();
  }

  void _afterSync(SyncReport r) {
    final batch = _api.lastBatchIds;
    final stillQueued = {
      for (final e in persistence.queue.all())
        if (e.state == DeliveryState.savedLocally) e.eventId,
    };
    for (final id in batch) {
      if (stillQueued.contains(id)) {
        // Falha do lote inteiro → o motivo injetado; resposta 200 sem o
        // resultado deste evento → "sem confirmação" (ACK parcial).
        _lastFailure[id] = r.failure == FailureClass.transient
            ? (_api.lastFaultLabel ?? 'sem resposta')
            : 'sem confirmação';
      } else {
        _lastFailure.remove(id);
      }
    }

    if (r.nothingToSend) {
      final next = persistence.queue.nextAttemptAt();
      report = next == null
          ? const LabReport('Nada para enviar: todos os eventos já têm resposta.')
          : LabReport('Aguardando a próxima tentativa, a partir de ${_hms(next)}.',
              detail: 'Backoff fictício de 5 s dobrando até 30 min. Tente de novo depois desse horário.');
      return;
    }
    final next = persistence.queue.nextAttemptAt();
    final wait = next?.difference(_now()).inSeconds.clamp(0, 1 << 30);
    switch (r.failure) {
      case FailureClass.transient when r.received == 0:
        report = LabReport(
          '${_api.lastFaultLabel == 'sem resposta' ? 'Rede ausente' : 'Servidor indisponível (503)'}: '
          '${r.unanswered} evento(s) voltaram para a fila.'
          '${wait == null ? '' : ' Nova tentativa em $wait s.'}',
          detail: 'Classe: falha transitória. Nada foi marcado como recebido.',
          tone: ReportTone.error,
        );
      case null when r.unanswered > 0:
        report = LabReport(
          'ACK parcial: ${r.received} recebido(s). ${r.unanswered} ficou(aram) sem confirmação e volta(m) para a fila.',
          detail: 'No reenvio, o servidor responde "duplicado" com o recibo original.',
          tone: ReportTone.error,
        );
      case null:
        report = LabReport(
          '${r.received} evento(s) recebido(s) pelo servidor simulado.',
          detail: 'Recebido quer dizer que o servidor gravou o evento. Não quer dizer ponto aprovado.',
          tone: ReportTone.ok,
        );
      case final c:
        report = LabReport('Envio parado: ${c.name}.',
            detail: r.halt?.detail, tone: ReportTone.error);
    }
    _ensureTicker();
  }

  /// Atualiza a contagem regressiva do backoff enquanto houver espera.
  void _ensureTicker() {
    _ticker?.cancel();
    if (persistence.queue.nextAttemptAt() == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      final n = persistence.queue.nextAttemptAt();
      if (n == null || !n.isAfter(_now())) t.cancel();
      notifyListeners();
    });
  }

  // ---- Avaliação simulada ----

  void evaluateReceived(SimEvaluation v) {
    for (final e in persistence.queue.all()) {
      final kind = (jsonDecode(e.payloadJson) as Map)['kind'];
      if (e.state == DeliveryState.received && kind == 'area_transition') {
        _evaluations.putIfAbsent(e.eventId, () => v);
      }
    }
    notifyListeners();
  }

  void setDecision(LabDecision d, PendingCaseHandling h) {
    decisions[d] = h;
    notifyListeners();
  }

  void setNextSend(NextSend n) {
    nextSend = n;
    notifyListeners();
  }

  // ---- Leitura para a tela ----

  List<LabEventView> get events => [
        for (final e in persistence.queue.all().reversed)
          LabEventView(
            event: e,
            payload: (jsonDecode(e.payloadJson) as Map).cast<String, Object?>(),
            lastFailure: e.state == DeliveryState.savedLocally ? _lastFailure[e.eventId] : null,
            evaluation: _evaluations[e.eventId],
          ),
      ];

  PendingPolicies get _policies => PendingPolicies(
        expiredConfig: decisions[LabDecision.expiredConfig]!,
        revokedLink: decisions[LabDecision.revokedLink]!,
        afterAuthLoss: decisions[LabDecision.afterAuthLoss]!,
      );

  void _batchInFlight() => notifyListeners();

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _hms(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }
}

/// Cliente de envio do laboratório: injeta a falha escolhida e um pequeno
/// atraso (para a tela mostrar "enviando"), e repassa ao SERVIDOR SIMULADO.
class _LabApi implements PresenceApi {
  _LabApi(this._c);
  final LabController _c;
  NextSend pendingFault = NextSend.normal;
  List<String> lastBatchIds = const [];
  String? lastFaultLabel;

  @override
  Future<BatchResponse> submitBatch(List<String> payloadsJson) async {
    lastBatchIds = [
      for (final p in payloadsJson) (jsonDecode(p) as Map)['eventId'] as String,
    ];
    _c._batchInFlight(); // mostra os eventos em "enviando"
    if (_c.sendDelay > Duration.zero) await Future<void>.delayed(_c.sendDelay);
    lastFaultLabel = switch (pendingFault) {
      NextSend.networkDown => 'sem resposta',
      NextSend.transient503 => '503',
      _ => null,
    };
    switch (pendingFault) {
      case NextSend.networkDown:
        _c.server.faults.add(const NetworkDown());
      case NextSend.transient503:
        _c.server.faults.add(const FailBeforeCommit());
      case NextSend.partialAck:
        _c.server.faults.add(PartialAck({lastBatchIds.last}));
      case NextSend.normal:
        break;
    }
    pendingFault = NextSend.normal;
    return _c.server.submitBatch(payloadsJson);
  }
}

class _FnClock implements Clock {
  _FnClock(this._f);
  final DateTime Function() _f;
  @override
  DateTime now() => _f();
}
