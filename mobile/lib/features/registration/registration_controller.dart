import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../punch/punch_models.dart';
import 'registration_models.dart';

enum RegStep {
  /// Nada em andamento (ex.: saiu de + Registrar).
  idle,

  /// 1. Conferindo a posição atual.
  locating,

  /// 1. Localização não validada: tudo bloqueado.
  locationFailed,

  /// 2. Localização validada; falta a foto.
  photo,

  /// 2. Câmera aberta.
  capturing,

  /// 2. Conferir a foto (usar ou tirar outra).
  review,

  /// 3. Escolher Entrada ou Saída.
  choose,

  /// 3. Resumo antes de gravar.
  confirm,

  /// 3. Gravando.
  committing,

  /// Ponto gravado.
  done,
}

/// Sessão de registro com estado explícito. Cada sessão tem um número:
/// respostas que chegam depois de cancelar, sair ou recomeçar são ignoradas,
/// então uma foto ou localização de outra tentativa nunca libera o ponto.
class RegistrationController extends ChangeNotifier {
  RegistrationController(this.port, {String Function()? newId}) : _newId = newId ?? const Uuid().v4;

  /// null = registro indisponível nesta versão (modo real sem os adaptadores).
  final RegistrationPort? port;
  final String Function() _newId;

  int _session = 0;
  RegStep _step = RegStep.idle;
  RegStep get step => _step;

  ValidatedLocation? _location;
  ValidatedLocation? get location => _location;
  LocationCheck? _failure;
  LocationFailure? get locationFailure => _failure?.failure;

  /// Fora da área: área mais próxima e distância até ela.
  String? get nearestArea => _failure?.areaName;
  int? get nearestDistanceM => _failure?.distanceM;

  CapturedPhoto? _photo;
  CapturedPhoto? get photo => _photo;
  SelfieProblem? _photoProblem;
  SelfieProblem? get photoProblem => _photoProblem;
  String? _photoDetail;

  /// Código técnico curto do último problema da câmera (diagnóstico).
  String? get photoDetail => _photoDetail;

  PunchKind? _kind;
  PunchKind? get kind => _kind;

  String? _attemptId;
  String? _commitError;
  String? get commitError => _commitError;
  CommitRecovery _recovery = CommitRecovery.none;
  CommitRecovery get recovery => _recovery;

  RegistrationReceipt? _receipt;
  RegistrationReceipt? get receipt => _receipt;

  bool get busy => _step == RegStep.locating || _step == RegStep.capturing || _step == RegStep.committing;
  bool get simulated => port?.simulated ?? false;

  void _reset() {
    _session++;
    _location = null;
    _failure = null;
    _photo = null;
    _photoProblem = null;
    _photoDetail = null;
    _kind = null;
    _attemptId = null;
    _commitError = null;
    _recovery = CommitRecovery.none;
    _receipt = null;
  }

  /// Começa (ou recomeça) pela localização. Nunca interrompe uma gravação.
  Future<void> begin() async {
    final p = port;
    if (p == null || _step == RegStep.committing) return;
    _reset();
    final session = _session;
    _step = RegStep.locating;
    notifyListeners();
    final r = await p.validateLocation();
    if (session != _session) return;
    if (r.location != null) {
      _location = r.location;
      _step = RegStep.photo;
    } else {
      _failure = r;
      _step = RegStep.locationFailed;
    }
    notifyListeners();
  }

  /// Saiu de + Registrar (outra área do menu, troca de conta): descarta a
  /// sessão. Uma gravação em curso termina e o resultado fica para quando a
  /// pessoa voltar.
  void leave() {
    if (_step == RegStep.committing || _step == RegStep.idle) return;
    _reset();
    _step = RegStep.idle;
    notifyListeners();
  }

  /// "Cancelar registro".
  void cancel() => leave();

  /// Saída da conta: descarta tudo, inclusive o resultado de uma gravação
  /// em curso (ele não aparece para a próxima pessoa).
  void discard() {
    _reset();
    _step = RegStep.idle;
    notifyListeners();
  }

  bool _expired() {
    final p = port;
    final l = _location;
    if (p == null || l == null) return true;
    if (p.now().difference(l.at) <= p.evidenceValidity) return false;
    _reset();
    _failure = const LocationCheck.failed(LocationFailure.expired);
    _step = RegStep.locationFailed;
    notifyListeners();
    return true;
  }

  /// 2. Abre a câmera. Só depois da localização validada.
  Future<void> takePhoto() async {
    final p = port;
    if (p == null || (_step != RegStep.photo && _step != RegStep.review)) return;
    if (_expired()) return;
    final session = _session;
    _photo = null;
    _photoProblem = null;
    _photoDetail = null;
    _step = RegStep.capturing;
    notifyListeners();
    final r = await p.takePhoto();
    if (session != _session) return;
    if (r.photo != null) {
      _photo = r.photo;
      _step = RegStep.review;
    } else {
      // Desistir da câmera não é erro: só volta para tirar a foto.
      _photoProblem = r.problem == SelfieProblem.cancelled ? null : r.problem;
      _photoDetail = _photoProblem == null ? null : r.detail;
      _step = RegStep.photo;
    }
    notifyListeners();
  }

  /// Abre as configurações do app (câmera ou localização negadas). Ao
  /// voltar, a pessoa toca em "Tentar novamente".
  Future<void> openAppSettings() async => port?.openAppSettings();

  /// 2. "Usar esta foto".
  void usePhoto() {
    if (_step != RegStep.review || _photo == null || _expired()) return;
    _step = RegStep.choose;
    notifyListeners();
  }

  /// 3. Entrada ou Saída.
  void choose(PunchKind k) {
    if (_step != RegStep.choose || _photo == null || _expired()) return;
    _kind = k;
    _commitError = null;
    _step = RegStep.confirm;
    notifyListeners();
  }

  /// 3. "Alterar tipo de registro".
  void changeKind() {
    if (_step != RegStep.confirm) return;
    _kind = null;
    _commitError = null;
    _step = RegStep.choose;
    notifyListeners();
  }

  /// 3. Grava o ponto. Toque duplo não gera dois pontos.
  Future<void> confirm() async {
    final p = port;
    final l = _location;
    final ph = _photo;
    final k = _kind;
    if (p == null || _step != RegStep.confirm || l == null || ph == null || k == null) return;
    if (_expired()) return;
    final session = _session;
    _attemptId ??= _newId();
    _commitError = null;
    _step = RegStep.committing;
    notifyListeners();
    final r = await p.commit(RegistrationDraft(attemptId: _attemptId!, kind: k, location: l, photo: ph));
    if (session != _session) return;
    if (r.receipt != null) {
      _receipt = r.receipt;
      _step = RegStep.done;
      notifyListeners();
      return;
    }
    switch (r.recovery) {
      case CommitRecovery.restart:
        _reset();
        _failure = const LocationCheck.failed(LocationFailure.expired);
        _step = RegStep.locationFailed;
      case CommitRecovery.retakePhoto:
        _photo = null;
        _photoProblem = null;
        _attemptId = null;
        _commitError = r.message;
        _step = RegStep.photo;
      case CommitRecovery.retry:
      case CommitRecovery.none:
        _commitError = r.message;
        _recovery = r.recovery;
        _step = RegStep.confirm;
    }
    notifyListeners();
  }
}
