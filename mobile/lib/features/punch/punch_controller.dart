import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'punch_models.dart';

/// O que o registro de ponto precisa do mundo de fora (servidor e aparelho).
class PunchDeps {
  PunchDeps({required this.gateway, required this.location, required this.camera, required this.reminders, DateTime Function()? now, String Function()? newId})
      : now = now ?? DateTime.now,
        newId = newId ?? const Uuid().v4;

  final PunchGateway gateway;
  final LocationSource location;
  final SelfieCamera camera;
  final PunchReminders reminders;
  final DateTime Function() now;
  final String Function() newId;
}

enum PunchStep {
  /// Lendo a localização e criando o ponto provisório.
  locating,

  /// Localização registrada; falta a selfie.
  located,

  /// Câmera aberta ou selfie sendo enviada.
  confirming,

  /// Ponto confirmado.
  done,

  /// A janela da selfie acabou: é preciso registrar de novo.
  expired,

  /// O servidor não aceitou a etapa 1.
  failed,
}

/// Um registro de ponto em andamento.
@immutable
class PunchFlow {
  const PunchFlow({required this.link, required this.kind, required this.step, this.record, this.locationProblem, this.selfieProblem, this.failure});
  final LinkAttendance link;
  final PunchKind kind;
  final PunchStep step;
  final PunchRecord? record;

  /// O aparelho não entregou a localização: o ponto seguiu sem ela.
  final LocationProblem? locationProblem;
  final SelfieProblem? selfieProblem;
  final PunchFailure? failure;

  PunchFlow copy({PunchStep? step, PunchRecord? record, LocationProblem? locationProblem, SelfieProblem? selfieProblem, PunchFailure? failure}) => PunchFlow(
        link: link,
        kind: kind,
        step: step ?? this.step,
        record: record ?? this.record,
        locationProblem: locationProblem ?? this.locationProblem,
        selfieProblem: selfieProblem,
        failure: failure,
      );
}

/// Estado do ponto REAL: a jornada de hoje, os avisos e o registro em duas
/// etapas. Não guarda coordenadas nem a selfie: elas só passam por aqui a
/// caminho do servidor.
class PunchController extends ChangeNotifier {
  PunchController(this._d);
  final PunchDeps _d;

  String? _tenantId;
  Attendance? _attendance;
  Attendance? get attendance => _attendance;
  bool _loading = false;
  bool get loading => _loading;
  PunchFailure? _error;
  PunchFailure? get error => _error;

  bool _remindersOn = false;
  bool get remindersOn => _remindersOn;
  int _scheduled = 0;

  /// Quantos avisos estão agendados para os próximos dias.
  int get scheduledReminders => _scheduled;

  PunchFlow? _flow;
  PunchFlow? get flow => _flow;

  /// Agora, em UTC, pelo mesmo relógio usado nas regras (injetável nos testes).
  DateTime nowUtc() => _d.now().toUtc();

  /// Carrega (ou recarrega) a jornada do vínculo e reagenda os avisos.
  Future<void> load(String tenantId) async {
    _tenantId = tenantId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _attendance = await _d.gateway.attendance(tenantId);
      _remindersOn = await _d.reminders.enabled();
      await _reschedule();
    } on PunchException catch (e) {
      _error = e.failure;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final t = _tenantId;
    if (t != null && !_loading) await load(t);
  }

  /// Pede a permissão de notificações (em resposta a um toque) e agenda.
  Future<void> enableReminders() async {
    _remindersOn = await _d.reminders.request();
    await _reschedule();
    notifyListeners();
  }

  Future<void> _reschedule() async {
    final a = _attendance;
    if (a == null || !_remindersOn) {
      _scheduled = 0;
      return;
    }
    // Compara com o relógio do SERVIDOR, no fuso da operação: "hoje" vem dele.
    final t = a.serverTime;
    final reminders = buildReminders(a, nowDate: a.today, nowTime: _localTimeOf(t, a));
    try {
      await _d.reminders.schedule(reminders, timeZone: a.timeZone);
      _scheduled = reminders.length;
    } catch (_) {
      _scheduled = 0;
    }
  }

  /// Hora local (HH:MM) do instante do servidor. O servidor informa só o dia
  /// civil; a hora é aproximada pelo fuso fixo da operação (UTC−3, sem
  /// horário de verão). Serve apenas para não agendar aviso que já passou.
  static String _localTimeOf(DateTime utc, Attendance a) {
    final local = utc.toUtc().subtract(const Duration(hours: 3));
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------- registro

  /// Etapa 1: localização. Se já existe um ponto provisório dentro da janela,
  /// retoma dele (não cria outro).
  Future<void> start(LinkAttendance link) async {
    final tenantId = _tenantId;
    if (tenantId == null || _flow?.step == PunchStep.locating || _flow?.step == PunchStep.confirming) return;
    final pending = link.pendingAt(_d.now().toUtc());
    if (pending != null) {
      _flow = PunchFlow(link: link, kind: pending.kind, step: PunchStep.located, record: pending);
      notifyListeners();
      return;
    }
    final kind = link.nextKind;
    _flow = PunchFlow(link: link, kind: kind, step: PunchStep.locating);
    notifyListeners();
    final where = await _d.location.current();
    try {
      final record = await _d.gateway.register(tenantId, employmentLinkId: link.employmentLinkId, clientEventId: _d.newId(), kind: kind, location: where.location);
      _flow = PunchFlow(link: link, kind: kind, step: PunchStep.located, record: record, locationProblem: where.problem);
    } on PunchException catch (e) {
      _flow = PunchFlow(link: link, kind: kind, step: PunchStep.failed, failure: e.failure, locationProblem: where.problem);
    }
    notifyListeners();
  }

  /// Etapa 2: selfie. Problema com a foto permite tentar de novo enquanto a
  /// janela estiver aberta.
  Future<void> takeSelfie() async {
    final tenantId = _tenantId;
    final f = _flow;
    final record = f?.record;
    if (tenantId == null || f == null || record == null || f.step != PunchStep.located) return;
    if (record.faceDeadline != null && !_d.now().toUtc().isBefore(record.faceDeadline!)) {
      _flow = f.copy(step: PunchStep.expired);
      notifyListeners();
      return;
    }
    _flow = f.copy(step: PunchStep.confirming);
    notifyListeners();
    final shot = await _d.camera.capture();
    if (shot.bytes == null) {
      _flow = f.copy(step: PunchStep.located, selfieProblem: shot.problem);
      notifyListeners();
      return;
    }
    try {
      final confirmed = await _d.gateway.confirm(tenantId, record.id, shot.bytes!);
      _flow = f.copy(step: PunchStep.done, record: confirmed);
    } on PunchException catch (e) {
      _flow = switch (e.failure) {
        PunchFailure.windowExpired => f.copy(step: PunchStep.expired),
        // Outra tentativa já tinha confirmado: o ponto vale.
        PunchFailure.alreadyConfirmed => f.copy(step: PunchStep.done),
        _ => f.copy(step: PunchStep.located, failure: e.failure),
      };
    }
    notifyListeners();
    if (_flow?.step == PunchStep.done) await refresh();
  }

  /// Fecha o registro em andamento (o ponto provisório sem selfie não conta).
  void closeFlow() {
    _flow = null;
    notifyListeners();
  }

  /// Troca de conta ou saída: nada da pessoa anterior fica aqui, e os avisos
  /// agendados no aparelho são apagados.
  Future<void> reset() async {
    _tenantId = null;
    _attendance = null;
    _flow = null;
    _error = null;
    _scheduled = 0;
    notifyListeners();
    await _d.reminders.clear();
  }
}
