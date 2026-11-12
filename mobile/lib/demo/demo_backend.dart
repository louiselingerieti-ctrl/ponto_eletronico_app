import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:presenca_core/presenca_lab.dart';
import 'package:uuid/uuid.dart';

import '../features/requests/request_models.dart';

/// ================================================================
///  ADAPTADORES SIMULADOS DA DEMONSTRAÇÃO — dados fictícios.
/// ================================================================
/// Usa o núcleo REAL (fila, envio com ACK, ciclo de configuração) sobre
/// persistência em memória SEM cifra e servidor SIMULADO. Não autentica, não
/// lê permissões reais, não detecta localização e não fala com o backend.
/// Recarregar/fechar o app apaga tudo.

const _linkId = '00000000-0000-4000-8000-0000000c0f01';
const _areaId = '00000000-0000-4000-8000-0000000c0a01';

/// Contexto do colaborador. Em produção virá do servidor, autorizado pelo
/// vínculo; aqui é fictício.
class DemoProfile {
  const DemoProfile();
  String get fullName => 'Ana Souza';
  String get firstName => 'Ana';
  String get initials => 'AS';
  String get company => 'Casa do Futuro';
  String get establishment => 'Loja Centro';
  String get areaLabel => 'Loja Centro';
}

enum DeliveryView {
  savedOnDevice('Salvo no aparelho'),
  sending('Enviando'),
  retryPending('Falha no envio, nova tentativa'),
  received('Recebido pelo servidor'),
  rejected('Recusado pelo servidor'),
  conflict('Em conflito, mantido para análise');

  const DeliveryView(this.label);
  final String label;
  bool get ok => this == received;
}

class DetectionView {
  const DetectionView({
    required this.eventId,
    required this.isEntry,
    required this.area,
    required this.detectedAt,
    required this.delivery,
  });
  final String eventId;
  final bool isEntry;
  final String area;

  /// Relógio do aparelho no momento da detecção (local). Não é o instante
  /// exato de cruzamento.
  final DateTime detectedAt;
  final DeliveryView delivery;

  String get title => isEntry ? 'Entrada detectada' : 'Saída detectada';
}

/// Ponto registrado pelo + Registrar na demonstração (localização + foto
/// simuladas). Fica só em memória, "salvo no aparelho": nada é enviado.
class ManualPunchView {
  const ManualPunchView({required this.clientId, required this.isEntry, required this.area, required this.at});
  final String clientId;
  final bool isEntry;
  final String area;
  final DateTime at;

  String get title => isEntry ? 'Entrada manual' : 'Saída manual';
}

enum AreaConfigView {
  applied('Configuração aplicada', true),
  pending('Configuração pendente', false),
  expired('Configuração expirada', false),
  revoked('Acesso revogado', false),
  error('Erro ao aplicar a configuração', false);

  const AreaConfigView(this.label, this.ok);
  final String label;
  final bool ok;
}

class DemoBackend extends ChangeNotifier implements RequestsRepository {
  DemoBackend({DateTime Function()? now}) : _now = now ?? DateTime.now {
    _server = SimulatedPresenceServer(
        ownedEmploymentLinks: {_linkId}, clock: () => _now().toUtc());
    _stamper = ClockStamper(
      configs: _store.configs,
      // Fictício, só da demonstração (D-CLK-1 pendente).
      policy: const ClockQualityPolicy(
          tolerance: Duration(seconds: 5), maxReferenceAge: Duration(hours: 12)),
      timeZone: () => 'America/Sao_Paulo',
    );
    _lifecycle = ConfigLifecycle(store: _store, stamper: _stamper, appVersion: _appVersion);
    _engine = SyncEngine(queue: _store.queue, api: _server, clock: _Fn(() => _now().toUtc()));
    _seed();
  }

  static const _appVersion = '0.1.0-demo';
  final DateTime Function() _now;
  final InMemoryLabPersistence _store = InMemoryLabPersistence();
  late final SimulatedPresenceServer _server;
  late final ClockStamper _stamper;
  late final ConfigLifecycle _lifecycle;
  late final SyncEngine _engine;

  final DemoProfile profile = const DemoProfile();

  DateTime now() => _now();

  // ---- Estado simulado do aparelho ----

  bool _offline = false;
  bool get offline => _offline;
  void setOffline(bool v) {
    _offline = v;
    notifyListeners();
  }

  bool _locationGranted = true;
  bool get locationGranted => _locationGranted;
  void setLocationGranted(bool v) {
    _locationGranted = v;
    notifyListeners();
  }

  bool _sending = false;
  bool get sending => _sending;

  // ---- Pontos do + Registrar (simulados) ----

  final List<ManualPunchView> _manual = [];

  /// Mais recente primeiro.
  List<ManualPunchView> get manualPunches => List.unmodifiable(_manual.reversed);

  /// Próximo previsto: entrada se o último foi saída (ou se não houve).
  bool get nextManualIsEntry => _manual.isEmpty || !_manual.last.isEntry;

  /// Grava em memória. A mesma tentativa ([clientId]) não gera dois pontos.
  ManualPunchView addManualPunch({required bool isEntry, required String area, required String clientId}) {
    for (final m in _manual) {
      if (m.clientId == clientId) return m;
    }
    final p = ManualPunchView(clientId: clientId, isEntry: isEntry, area: area, at: _now());
    _manual.add(p);
    notifyListeners();
    return p;
  }

  // ---- Semeadura fictícia ----

  void _seed() {
    final n = _now();
    final today = DateTime(n.year, n.month, n.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final serverTime = n.toUtc().subtract(const Duration(minutes: 1));
    final rec = _lifecycle.receive(
      jsonEncode({
        'employmentLinkId': _linkId,
        'configRevision': 'demo-1',
        'policyRevision': 'demo-pol-1',
        'serverTime': serverTime.toIso8601String(),
        'validUntil': serverTime.add(const Duration(hours: 24)).toIso8601String(),
        'areas': [
          {
            'areaId': _areaId,
            'revision': 1,
            'label': profile.areaLabel,
            'kind': 'establishment',
            'center': {'latitude': 0.0012, 'longitude': 0.0034},
            'radiusMeters': 150,
            'validFrom': '2026-01-01T00:00:00.000Z',
            'validTo': null,
          }
        ],
        'detection': {'maxFixAgeSeconds': 120, 'maxAccuracyMeters': 100, 'dwellSeconds': 0},
        'manualPunch': {'allowed': false, 'reasonRequired': true, 'locationRequired': false},
        'offline': {'maxEventAgeHours': 24, 'maxQueuedEvents': 500},
      }),
      expectedLinkId: _linkId,
      receivedAt: serverTime,
    );
    _lifecycle.persist(rec, now: serverTime);
    _lifecycle.confirmApplied(_linkId, 'demo-1',
        registeredAreaIds: {_areaId}, sample: ClockSample(wall: serverTime));

    _detect(Transition.enter, yesterday.add(const Duration(hours: 8, minutes: 4)));
    _detect(Transition.exit, yesterday.add(const Duration(hours: 17, minutes: 36)));
    // Os de ontem chegam ao servidor simulado. A reserva do lote é síncrona,
    // então a detecção de hoje (abaixo) fica fora dele e segue pendente.
    unawaited(_syncNow());
    _detect(Transition.enter, today.add(const Duration(hours: 8, minutes: 2)));

    final tId = _uuid.v4();
    _requests.addAll([
      EmployeeRequest(
        displayId: 1042,
        clientRequestId: tId,
        category: RequestCategory.detectionProblem,
        date: today,
        time: const TimeOfDay(hour: 8, minute: 0),
        description: 'Cheguei à loja às 08:00, mas a entrada só apareceu às 08:02.',
        status: RequestStatus.underReview,
        reply: 'Sua solicitação está com o RH. Você poderá acompanhar a resposta por aqui.',
      ),
      EmployeeRequest(
        displayId: 1043,
        clientRequestId: _uuid.v4(),
        category: RequestCategory.absenceJustification,
        date: today.subtract(const Duration(days: 2)),
        description: 'Precisei me ausentar para uma consulta e comuniquei a liderança.',
        status: RequestStatus.answered,
        reply: 'Recebemos sua justificativa. Entre em contato com o RH para conferir o tratamento na jornada.',
      ),
    ]);
  }

  /// Detecção sintética (o produto receberá isso da plataforma nativa).
  void _detect(Transition t, DateTime localWall) {
    RecordDetection(
      store: _store,
      stamper: _stamper,
      appVersion: _appVersion,
      // Escolha SÓ da demonstração: as decisões D-CFG-1/D-LINK-1/D-AUTH-2
      // continuam pendentes.
      policies: const PendingPolicies(
        expiredConfig: PendingCaseHandling.recordAndFlag,
        revokedLink: PendingCaseHandling.recordAndFlag,
        afterAuthLoss: PendingCaseHandling.recordAndFlag,
      ),
    )(GeofenceCallback(
      employmentLinkId: _linkId,
      configRevision: 'demo-1',
      areaId: _areaId,
      areaRevision: 1,
      transition: t,
      sample: ClockSample(wall: localWall.toUtc()),
    ));
  }

  Future<SyncReport> _syncNow() => _engine.syncOnce();

  // ---- Leitura para as telas ----

  List<DetectionView> get detections {
    final out = <DetectionView>[];
    for (final e in _store.queue.all().reversed) {
      final p = (jsonDecode(e.payloadJson) as Map).cast<String, Object?>();
      if (p['kind'] != 'area_transition') continue;
      out.add(DetectionView(
        eventId: e.eventId,
        isEntry: p['transition'] == 'enter',
        area: profile.areaLabel,
        detectedAt: DateTime.parse((p['clock'] as Map)['detectedAt'] as String).toLocal(),
        delivery: _deliveryOf(e),
      ));
    }
    return out;
  }

  DeliveryView _deliveryOf(QueuedEvent e) => switch (e.state) {
        DeliveryState.savedLocally =>
          e.attempts > 0 ? DeliveryView.retryPending : DeliveryView.savedOnDevice,
        DeliveryState.sending => DeliveryView.sending,
        DeliveryState.received => DeliveryView.received,
        DeliveryState.rejected => DeliveryView.rejected,
        DeliveryState.conflict => DeliveryView.conflict,
      };

  /// Eventos (de qualquer tipo) ainda sem ACK do servidor.
  int get pendingCount => _store.queue
      .all()
      .where((e) => e.state == DeliveryState.savedLocally || e.state == DeliveryState.sending)
      .length;

  /// Última confirmação de recebimento (commit do servidor simulado).
  DateTime? get lastAck {
    DateTime? m;
    for (final e in _store.queue.all()) {
      final r = e.serverReceivedAt;
      if (r != null && (m == null || r.isAfter(m))) m = r;
    }
    return m?.toLocal();
  }

  AreaConfigView get areaConfig {
    final a = _lifecycle.assess(_linkId, now: _now().toUtc());
    if (a.revocation != null) return AreaConfigView.revoked;
    if (a.expired) return AreaConfigView.expired;
    return switch (a.status) {
      ConfigStatus.applied => AreaConfigView.applied,
      ConfigStatus.applyFailed => AreaConfigView.error,
      _ => AreaConfigView.pending,
    };
  }

  /// "Simular envio agora". Recebido só com ACK do servidor (simulado).
  Future<void> sendNow() async {
    if (_offline || _sending) return;
    _sending = true;
    notifyListeners();
    try {
      await _syncNow();
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  // ---- Solicitações (RequestsRepository SIMULADO) ----

  static const _uuid = Uuid();
  final List<EmployeeRequest> _requests = [];

  @override
  List<EmployeeRequest> list() => List.unmodifiable(_requests);

  @override
  EmployeeRequest? byDisplayId(int id) {
    for (final r in _requests) {
      if (r.displayId == id) return r;
    }
    return null;
  }

  @override
  Future<EmployeeRequest> submit(RequestDraft d, {required bool online}) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final next = _requests.fold<int>(1041, (m, r) => r.displayId > m ? r.displayId : m) + 1;
    final r = EmployeeRequest(
      displayId: next,
      clientRequestId: _uuid.v4(),
      category: d.category,
      date: d.date,
      time: d.time,
      description: d.description.trim(),
      status: online ? RequestStatus.underReview : RequestStatus.localDraft,
      reply: online
          ? 'Envio simulado. A empresa analisará o relato antes de qualquer alteração.'
          : 'Rascunho apenas nesta demonstração. Ainda não foi enviado à empresa.',
    );
    _requests.insert(0, r);
    notifyListeners();
    return r;
  }
}

class _Fn implements Clock {
  _Fn(this._f);
  final DateTime Function() _f;
  @override
  DateTime now() => _f();
}
