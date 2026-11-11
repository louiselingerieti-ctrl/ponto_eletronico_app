import 'package:flutter/widgets.dart';

import '../demo/demo_backend.dart';
import '../features/session/session_models.dart';

/// Sessão do app em dois modos EXPLÍCITOS (nunca há troca silenciosa):
/// - real: [auth] presente → conta do backend (login, nome, empresa);
/// - demonstração: sessão simulada, não autentica.
/// Em ambos, detecções, áreas e solicitações continuam SIMULADAS (o backend
/// ainda não tem essas rotas) e a tela avisa isso no modo real.
class AppServices extends ChangeNotifier {
  AppServices({DateTime Function()? now, bool signedIn = false, this.auth, this.google})
      : _now = now,
        // ignore: prefer_initializing_formals
        _demoSignedIn = signedIn {
    _backend = DemoBackend(now: now)..addListener(notifyListeners);
  }

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

  /// Entra com a conta do Google do aparelho. Desistir no seletor de contas
  /// não é erro. Se a conta escolhida não puder entrar, ela é esquecida para
  /// a pessoa poder escolher outra.
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
      if (token == null) return false;
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
    return true;
  }

  void chooseMembership(Membership m) {
    if (!_choices.contains(m)) return;
    _membership = m;
    notifyListeners();
  }

  /// Sai: encerra a sessão no servidor quando possível, apaga do aparelho e
  /// descarta os dados da demonstração (ver BackendAuthGateway.signOut).
  Future<void> signOut() async {
    await auth?.signOut();
    await _forgetGoogle();
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
