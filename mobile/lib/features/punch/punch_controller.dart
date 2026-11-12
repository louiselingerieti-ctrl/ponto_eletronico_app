import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../registration/registration_models.dart';
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

/// Estado do ponto REAL: a jornada de hoje, os avisos e as operações do
/// + Registrar (validar a localização, tirar a foto, gravar). Não guarda
/// coordenadas nem a foto: elas só passam por aqui a caminho do servidor.
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

  /// Pontos provisórios já criados no servidor e ainda sem foto, por
  /// tentativa: tentar de novo reaproveita o mesmo (não cria outro).
  final _provisional = <String, PunchRecord>{};

  /// Agora, em UTC, pelo mesmo relógio usado nas regras (injetável nos testes).
  DateTime nowUtc() => _d.now().toUtc();

  /// Agora, pelo mesmo relógio (validade da localização e da foto).
  DateTime now() => _d.now();

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

  /// A localização e a foto valem pela janela que o servidor dá para a foto.
  Duration get evidenceValidity => Duration(seconds: _attendance?.faceWindowSeconds ?? 300);

  /// 1. Busca a configuração vigente (áreas do vínculo) e confere a posição
  /// atual do aparelho contra ela. Não grava nada no servidor.
  Future<LocationCheck> validateLocation() async {
    final t = _tenantId;
    if (t == null) return const LocationCheck.failed(LocationFailure.sessionExpired);
    // Sempre a configuração vigente: sem conseguir buscá-la, não valida.
    await load(t);
    final a = _attendance;
    if (a == null || _error != null) {
      return LocationCheck.failed(_error == PunchFailure.sessionExpired ? LocationFailure.sessionExpired : LocationFailure.network);
    }
    if (a.links.isEmpty) return const LocationCheck.failed(LocationFailure.noLink);
    final links = a.links.where((l) => l.canPunch).toList();
    if (links.isEmpty) return const LocationCheck.failed(LocationFailure.companyInactive);
    if (links.every((l) => l.areas.isEmpty)) return const LocationCheck.failed(LocationFailure.noArea);

    final r = await _d.location.current();
    final loc = r.location;
    if (loc == null) {
      return LocationCheck.failed(switch (r.problem) {
        LocationProblem.denied => LocationFailure.denied,
        LocationProblem.deniedForever => LocationFailure.blocked,
        LocationProblem.serviceOff => LocationFailure.serviceOff,
        _ => LocationFailure.unavailable,
      });
    }

    // A área mais próxima (pelo centro) entre as autorizadas.
    (LinkAttendance, WorkArea, double)? best;
    for (final l in links) {
      for (final w in l.areas) {
        final d = distanceMeters(loc.latitude, loc.longitude, w.latitude, w.longitude);
        if (best == null || d < best.$3) best = (l, w, d);
      }
    }
    final (link, area, d) = best!;
    // Precisão pior que o raio da área: não dá para afirmar dentro nem fora.
    final acc = loc.accuracyM;
    if (acc == null || acc > area.radiusM) return const LocationCheck.failed(LocationFailure.imprecise);
    if (d > area.radiusM) return LocationCheck.failed(LocationFailure.outside, areaName: area.name, distanceM: d.round());
    return LocationCheck.ok(ValidatedLocation(
      areaName: area.name,
      companyName: link.companyName,
      linkId: link.employmentLinkId,
      location: loc,
      at: _d.now(),
      suggested: link.nextKind,
    ));
  }

  /// 2. Câmera frontal + checagem de que há um rosto (no aparelho).
  Future<PhotoResult> takePhoto() async {
    final shot = await _d.camera.capture();
    final bytes = shot.bytes;
    if (bytes == null) return PhotoResult.failed(shot.problem ?? SelfieProblem.unavailable, detail: shot.detail);
    return PhotoResult.ok(CapturedPhoto(at: _d.now(), bytes: bytes));
  }

  /// Configurações do app no celular (câmera ou localização negadas).
  Future<void> openAppSettings() => _d.camera.openSettings();

  /// 3. Grava: cria o ponto com a localização e, em seguida, confirma com a
  /// foto. Só diz que deu certo depois da confirmação do servidor.
  Future<CommitOutcome> commit(RegistrationDraft draft) async {
    final t = _tenantId;
    final bytes = draft.photo.bytes;
    final linkId = draft.location.linkId;
    if (t == null) return CommitOutcome.failed(PunchFailure.sessionExpired.message, CommitRecovery.none);
    if (bytes == null || linkId == null) return const CommitOutcome.failed('Faltam a localização ou a foto deste registro.', CommitRecovery.restart);
    try {
      final record = _provisional[draft.attemptId] ??
          await _d.gateway.register(t, employmentLinkId: linkId, clientEventId: draft.attemptId, kind: draft.kind, location: draft.location.location);
      _provisional[draft.attemptId] = record;
      PunchRecord done;
      try {
        done = await _d.gateway.confirm(t, record.id, bytes);
      } on PunchException catch (e) {
        // Outra tentativa já tinha confirmado: o ponto vale.
        if (e.failure != PunchFailure.alreadyConfirmed) rethrow;
        done = record;
      }
      _provisional.remove(draft.attemptId);
      await refresh();
      return CommitOutcome.ok(RegistrationReceipt(
        kind: done.kind,
        recordedAt: done.recordedAt,
        areaName: done.areaName ?? draft.location.areaName,
        received: true,
        serverNote: done.flagged ? '${done.locationText}. O ponto fica sinalizado para o RH avaliar.' : null,
      ));
    } on PunchException catch (e) {
      return switch (e.failure) {
        PunchFailure.windowExpired => () {
            _provisional.remove(draft.attemptId);
            return CommitOutcome.failed(e.failure.message, CommitRecovery.restart);
          }(),
        PunchFailure.invalidSelfie => () {
            _provisional.remove(draft.attemptId);
            return CommitOutcome.failed(e.failure.message, CommitRecovery.retakePhoto);
          }(),
        PunchFailure.network || PunchFailure.server => CommitOutcome.failed('${e.failure.message} O ponto ainda não foi registrado.', CommitRecovery.retry),
        _ => CommitOutcome.failed(e.failure.message, CommitRecovery.none),
      };
    }
  }

  /// Troca de conta ou saída: nada da pessoa anterior fica aqui, e os avisos
  /// agendados no aparelho são apagados.
  Future<void> reset() async {
    _tenantId = null;
    _attendance = null;
    _provisional.clear();
    _error = null;
    _scheduled = 0;
    notifyListeners();
    await _d.reminders.clear();
  }
}

/// Distância em metros entre dois pontos (fórmula de haversine).
double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}
