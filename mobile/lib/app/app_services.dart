import 'dart:async';

import 'package:flutter/widgets.dart';

import '../demo/demo_backend.dart';
import '../demo/demo_registration.dart';
import '../features/punch/punch_controller.dart';
import '../features/punch/punch_registration.dart';
import '../features/registration/registration_controller.dart';
import '../features/session/session_models.dart';

/// Sessão do app em dois modos EXPLÍCITOS (nunca há troca silenciosa):
/// - real: [auth] presente → conta do backend (login, nome, empresa);
/// - demonstração: sessão simulada, não autentica.
/// Em ambos, detecções, áreas e solicitações continuam SIMULADAS (o backend
/// ainda não tem essas rotas) e a tela avisa isso no modo real.
class AppServices extends ChangeNotifier {
  AppServices({DateTime Function()? now, bool signedIn = false, this.auth, this.google, PunchDeps? punch})
      : _now = now,
        // ignore: prefer_initializing_formals
        _demoSignedIn = signedIn,
        punch = auth != null && punch != null ? PunchController(punch) : null {
    _backend = DemoBackend(now: now)..addListener(notifyListeners);
  }

  /// Ponto REAL (localização + selfie). Só existe no modo real e quando o
  /// build trouxe os adaptadores do aparelho; na demonstração é null.
  final PunchController? punch;

  /// + Registrar: localização → foto → Entrada/Saída → confirmação. Real com
  /// [punch]; simulado na demonstração; indisponível (porta null) no modo
  /// real sem os adaptadores do aparelho. Nunca mistura os dois.
  late final RegistrationController registration = RegistrationController(
    switch ((realMode, punch)) {
      (false, _) => DemoRegistrationPort(() => _backend),
      (true, final PunchController p?) => PunchRegistrationPort(p, now: p.now),
      (true, null) => null,
    },
  );

  final DateTime Function()? _now;
  final AuthGateway? auth;
  bool get realMode => auth != null;

  /// Identidade do Google no aparelho; só existe no modo real e quando o
  /// build informou o client ID.
  final GoogleIdTokenSource? google;
  bool get googleAvailable => realMode && google != null;

  late DemoBackend _backend;
  DemoBackend get backend => _backend;

  bool _demoSignedIn;
  SessionUser? _user;
  SessionUser? get user => _user;
  Membership? _membership;
  Membership? get membership => _membership;
  List<Membership> _choices = const [];

  /// Mais de um acesso ativo: a pessoa escolhe explicitamente.
  List<Membership> get pendingChoices => _membership == null ? _choices : const [];

  bool get signedIn => realMode ? (_user != null && _membership != null) : _demoSignedIn;

  bool _busy = false;
  bool get authenticating => _busy;

  bool _restoring = false;
  bool get restoring => _restoring;

  AuthFailure? _failure;
  AuthFailure? get lastFailure => _failure;

  /// Incrementa a cada saída: o shell é recriado e nada da conta anterior
  /// passa para a próxima pessoa.
  int generation = 0;

  // ---- Contexto mostrado nas telas ----

  String get fullName => realMode ? (_user?.name ?? '') : _backend.profile.fullName;
  String get firstName => realMode ? (_user?.firstName ?? '') : _backend.profile.firstName;
  String get initials => realMode ? (_user?.initials ?? '') : _backend.profile.initials;
  String get companyName => realMode ? (_membership?.tenantName ?? '') : _backend.profile.company;
  String? get email => _user?.email;

  // ---- Ciclo da sessão ----

  /// Retoma a sessão guardada (modo real). Falha de rede não apaga a sessão.
  Future<void> init() async {
    final a = auth;
    if (a == null) return;
    _restoring = true;
    notifyListeners();
    try {
      final u = await a.restore();
      if (u != null) await _afterAuth(u);
    } on AuthException catch (e) {
      _failure = e.failure;
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  /// Entra. Retorna true quando a pessoa pode seguir para o app.
  Future<bool> signIn({String email = '', String password = ''}) async {
    if (_busy) return false;
    _busy = true;
    _failure = null;
    notifyListeners();
    try {
      final a = auth;
      if (a == null) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        _demoSignedIn = true;
        return true;
      }
      final u = await a.signIn(email, password);
      return await _afterAuth(u);
    } on AuthException catch (e) {
      _failure = e.failure;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Entra com a conta do Google do aparelho. Se o Google devolver
  /// "cancelado", a tela avisa que o login não foi concluído. Se a conta
  /// escolhida não puder entrar, ela é esquecida para a pessoa poder escolher
  /// outra.
  Future<bool> signInWithGoogle() async {
    final a = auth;
    final g = google;
    if (a == null || g == null || _busy) return false;
    _busy = true;
    _failure = null;
    notifyListeners();
    var entered = false;
    try {
      final token = await g.idToken();
      if (token == null) {
        // "Cancelado" pode ser desistência ou recusa do Google por
        // configuração; o aviso cobre os dois sem afirmar o que não se sabe.
        _failure = AuthFailure.googleNotCompleted;
        return false;
      }
      entered = await _afterAuth(await a.signInWithGoogleIdToken(token));
      return entered;
    } on AuthException catch (e) {
      _failure = e.failure;
      return false;
    } finally {
      if (!entered && !needsPasswordChange) await _forgetGoogle();
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _forgetGoogle() async {
    try {
      await google?.signOut();
    } catch (_) {
      // Melhor esforço: no pior caso o Google reaproveita a última conta.
    }
  }

  /// Conta autenticada com senha temporária: precisa criar a nova senha no
  /// app antes de seguir. A sessão continua aberta só para isso.
  SessionUser? _passwordChangeFor;
  bool get needsPasswordChange => _passwordChangeFor != null;
  String get passwordChangeFirstName => _passwordChangeFor?.firstName ?? '';

  Future<bool> changePassword(String current, String next) async {
    final a = auth;
    if (a == null || _passwordChangeFor == null || _busy) return false;
    _busy = true;
    _failure = null;
    notifyListeners();
    try {
      final u = await a.changePassword(current, next);
      _passwordChangeFor = null;
      if (u.mustChangePassword) {
        // O servidor não confirmou a troca: não entra.
        _failure = AuthFailure.passwordChangeUnavailable;
        await a.signOut();
        return false;
      }
      return await _afterAuth(u);
    } on AuthException catch (e) {
      _failure = e.failure;
      if (e.failure == AuthFailure.sessionExpired) _passwordChangeFor = null;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> _afterAuth(SessionUser u) async {
    final a = auth!;
    if (u.mustChangePassword) {
      _passwordChangeFor = u;
      return false;
    }
    final List<Membership> active;
    try {
      active = (await a.memberships()).where((m) => m.usable).toList();
    } on AuthException catch (e) {
      await a.signOut();
      _failure = e.failure;
      return false;
    }
    if (active.isEmpty) {
      await a.signOut();
      _failure = AuthFailure.noActiveAccess;
      return false;
    }
    // Só acessos de COLABORADOR entram no app; gestão usa o portal.
    final ms = active.where((m) => m.isEmployee).toList();
    if (ms.isEmpty) {
      await a.signOut();
      _failure = AuthFailure.notEmployee;
      return false;
    }
    _user = u;
    _choices = ms;
    _membership = ms.length == 1 ? ms.single : null;
    final chosen = _membership;
    if (chosen != null) unawaited(punch?.load(chosen.tenantId));
    return true;
  }

  bool _refreshing = false;

  /// "Puxar para atualizar": busca de novo no servidor a conta, o acesso e o
  /// ponto de hoje. Devolve o aviso a mostrar se não deu certo (null = ok).
  /// Falha de rede não mexe em nada; sessão encerrada ou acesso retirado no
  /// servidor tiram a pessoa do app, com o motivo na tela de login.
  /// Na demonstração não há o que buscar: as telas já mostram o estado atual.
  Future<String?> refresh() async {
    final a = auth;
    if (a == null) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return null;
    }
    final current = _membership;
    if (_refreshing || _busy || current == null) return null;
    _refreshing = true;
    try {
      final u = await a.restore();
      if (u == null) return await _endSession(AuthFailure.sessionExpired);
      final ms = (await a.memberships()).where((m) => m.usable && m.isEmployee).toList();
      final same = ms.where((m) => m.tenantId == current.tenantId).firstOrNull;
      if (same == null) {
        return await _endSession(AuthFailure.noActiveAccess);
      }
      _user = u;
      _choices = ms;
      _membership = same;
      notifyListeners();
      await punch?.refresh();
      final e = punch?.error;
      return e?.message;
    } on AuthException catch (e) {
      return switch (e.failure) {
        AuthFailure.sessionExpired || AuthFailure.accountInactive => await _endSession(e.failure),
        _ => e.failure.message,
      };
    } finally {
      _refreshing = false;
    }
  }

  /// Sai do app porque o servidor encerrou a sessão ou retirou o acesso.
  Future<String?> _endSession(AuthFailure why) async {
    await signOut();
    _failure = why;
    notifyListeners();
    return null;
  }

  void chooseMembership(Membership m) {
    if (!_choices.contains(m)) return;
    _membership = m;
    unawaited(punch?.load(m.tenantId));
    notifyListeners();
  }

  /// Sai: encerra a sessão no servidor quando possível, apaga do aparelho e
  /// descarta os dados da demonstração (ver BackendAuthGateway.signOut).
  Future<void> signOut() async {
    registration.discard();
    await auth?.signOut();
    await _forgetGoogle();
    await punch?.reset();
    _backend
      ..removeListener(notifyListeners)
      ..dispose();
    _backend = DemoBackend(now: _now)..addListener(notifyListeners);
    _demoSignedIn = false;
    _user = null;
    _membership = null;
    _choices = const [];
    _passwordChangeFor = null;
    _failure = null;
    generation++;
    notifyListeners();
  }

  @override
  void dispose() {
    registration.dispose();
    punch?.dispose();
    _backend.dispose();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppServices> {
  const AppScope({super.key, required AppServices services, required super.child})
      : super(notifier: services);

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static DemoBackend backendOf(BuildContext context) => of(context).backend;
}
