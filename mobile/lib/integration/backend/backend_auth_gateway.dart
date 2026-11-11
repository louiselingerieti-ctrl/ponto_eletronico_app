import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/session/session_models.dart';
import 'session_store.dart';

/// Autenticação no backend REAL (NestJS + Better Auth), por cookie de sessão.
///
/// PROVISÓRIO até o backend aceitar token para o app (D-AUTH-1). Contrato
/// conferido no código do backend (somente leitura) em 11/11/2026:
/// - POST /v1/auth/sign-in/email {email, password} → Set-Cookie
///   `__Secure-ponto.session_token` (12 h). Enviado SEM cookie antigo, para
///   não cair na checagem de Origin do backend.
/// - GET /v1/me → {accountId, email, name, mustChangePassword, sessionExpiresAt}
/// - GET /v1/me/memberships → {items: [...]} (403 password_change_required)
///
/// - POST /v1/auth/change-password e /v1/auth/sign-out (com cookie): o Better
///   Auth exige um Origin confiável. Ele inclui por padrão a origem do próprio
///   baseURL (better-auth context/helpers.mjs:73-74); o app envia
///   `Origin: <origem da API>`. Funciona se BETTER_AUTH_URL de produção for
///   esse endereço (não verificável daqui). Se o servidor recusar, a troca
///   de senha cai no aviso de usar o portal e a saída apaga só o aparelho.
///   A solução definitiva é token para o app (D-AUTH-1).
///
/// Nunca registra (log) senha, cookie ou corpo de resposta.
class BackendAuthGateway implements AuthGateway {
  BackendAuthGateway({
    required Uri baseUrl,
    required SessionStore store,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  })  : _base = _checkBase(baseUrl),
        // ignore: prefer_initializing_formals
        _store = store,
        _client = client ?? http.Client();

  final Uri _base;
  final SessionStore _store;
  final http.Client _client;
  final Duration timeout;

  static const _cookieNames = ['__Secure-ponto.session_token', 'ponto.session_token'];

  static Uri _checkBase(Uri u) {
    if (u.scheme != 'https') {
      throw ArgumentError('O endereço do servidor precisa usar https.');
    }
    return u.replace(path: '');
  }

  Uri _u(String path) => _base.replace(path: path);

  @override
  Future<SessionUser> signIn(String email, String password) async {
    // Sessão anterior é descartada antes: a nova não pode herdar nada.
    await _store.clear();
    final http.Response r;
    try {
      r = await _client
          .post(
            _u('/v1/auth/sign-in/email'),
            headers: const {'content-type': 'application/json', 'accept': 'application/json'},
            body: jsonEncode({'email': email.trim(), 'password': password}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AuthException(AuthFailure.network);
    } on http.ClientException {
      throw const AuthException(AuthFailure.network);
    }

    switch (r.statusCode) {
      case 200:
        break;
      case 401:
      case 400:
        throw const AuthException(AuthFailure.invalidCredentials);
      case 403:
        // Ex.: conta desativada (hook do backend recusa criar a sessão).
        throw const AuthException(AuthFailure.accountInactive);
      case 429:
        throw const AuthException(AuthFailure.rateLimited);
      default:
        throw const AuthException(AuthFailure.server);
    }

    final cookie = _extractSessionCookie(r.headers['set-cookie']);
    if (cookie == null) throw const AuthException(AuthFailure.server);
    await _store.write(cookie);
    try {
      final me = await _me(cookie);
      if (me == null) throw const AuthException(AuthFailure.sessionExpired);
      return me;
    } on AuthException {
      await _store.clear();
      rethrow;
    }
  }

  @override
  Future<SessionUser?> restore() async {
    final cookie = await _store.read();
    if (cookie == null) return null;
    try {
      final me = await _me(cookie);
      if (me == null) await _store.clear();
      return me;
    } on AuthException catch (e) {
      if (e.failure == AuthFailure.accountInactive) await _store.clear();
      rethrow;
    }
  }

  /// null = sessão inválida/expirada (401 sem código de conta inativa).
  Future<SessionUser?> _me(String cookie) async {
    final r = await _get('/v1/me', cookie);
    if (r.statusCode == 401) {
      if (_errorCode(r) == 'account_inactive') {
        throw const AuthException(AuthFailure.accountInactive);
      }
      return null;
    }
    if (r.statusCode != 200) throw const AuthException(AuthFailure.server);
    final j = _json(r);
    final accountId = j['accountId'];
    final email = j['email'];
    final name = j['name'];
    final must = j['mustChangePassword'];
    final expires = j['sessionExpiresAt'];
    if (accountId is! String || email is! String || name is! String || must is! bool ||
        expires is! String || DateTime.tryParse(expires) == null) {
      throw const AuthException(AuthFailure.server);
    }
    return SessionUser(
      accountId: accountId,
      email: email,
      name: name,
      mustChangePassword: must,
      sessionExpiresAt: DateTime.parse(expires),
    );
  }

  @override
  Future<List<Membership>> memberships() async {
    final cookie = await _store.read();
    if (cookie == null) throw const AuthException(AuthFailure.sessionExpired);
    final r = await _get('/v1/me/memberships', cookie);
    if (r.statusCode == 401) {
      await _store.clear();
      throw AuthException(_errorCode(r) == 'account_inactive'
          ? AuthFailure.accountInactive
          : AuthFailure.sessionExpired);
    }
    if (r.statusCode == 403 && _errorCode(r) == 'password_change_required') {
      throw const AuthException(AuthFailure.passwordChangeRequired);
    }
    if (r.statusCode != 200) throw const AuthException(AuthFailure.server);
    final items = _json(r)['items'];
    if (items is! List) throw const AuthException(AuthFailure.server);
    final out = <Membership>[];
    for (final raw in items) {
      if (raw is! Map) throw const AuthException(AuthFailure.server);
      final roles = raw['roles'];
      if (raw['tenantId'] is! String || raw['tenantSlug'] is! String ||
          raw['tenantName'] is! String || raw['tenantStatus'] is! String ||
          raw['membershipStatus'] is! String || roles is! List ||
          roles.any((x) => x is! String)) {
        throw const AuthException(AuthFailure.server);
      }
      out.add(Membership(
        tenantId: raw['tenantId'] as String,
        tenantSlug: raw['tenantSlug'] as String,
        tenantName: raw['tenantName'] as String,
        tenantActive: raw['tenantStatus'] == 'active',
        membershipActive: raw['membershipStatus'] == 'active',
        roles: List.unmodifiable(roles.cast<String>()),
      ));
    }
    return out;
  }

  String get _origin => _base.origin;

  @override
  Future<SessionUser> changePassword(String currentPassword, String newPassword) async {
    final cookie = await _store.read();
    if (cookie == null) throw const AuthException(AuthFailure.sessionExpired);
    final http.Response r;
    try {
      r = await _client
          .post(
            _u('/v1/auth/change-password'),
            headers: {
              'content-type': 'application/json',
              'accept': 'application/json',
              'cookie': cookie,
              'origin': _origin,
            },
            body: jsonEncode({
              'currentPassword': currentPassword,
              'newPassword': newPassword,
              // A senha temporária pode ser conhecida por quem a criou.
              'revokeOtherSessions': true,
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AuthException(AuthFailure.network);
    } on http.ClientException {
      throw const AuthException(AuthFailure.network);
    }
    if (r.statusCode != 200) {
      final code = (_errorCode(r) ?? '').toUpperCase();
      if (r.statusCode == 401) {
        await _store.clear();
        throw const AuthException(AuthFailure.sessionExpired);
      }
      if (code == 'INVALID_PASSWORD') throw const AuthException(AuthFailure.currentPasswordWrong);
      if (code == 'PASSWORD_TOO_SHORT' || code == 'PASSWORD_TOO_LONG') {
        throw const AuthException(AuthFailure.weakPassword);
      }
      if (r.statusCode == 429) throw const AuthException(AuthFailure.rateLimited);
      // 403 de origem não confiável, ou qualquer outro: troca indisponível.
      throw const AuthException(AuthFailure.passwordChangeUnavailable);
    }
    // Com revokeOtherSessions o servidor emite uma sessão nova.
    final renewed = _extractSessionCookie(r.headers['set-cookie']);
    final active = renewed ?? cookie;
    if (renewed != null) await _store.write(renewed);
    final me = await _me(active);
    if (me == null) {
      await _store.clear();
      throw const AuthException(AuthFailure.sessionExpired);
    }
    return me;
  }

  @override
  Future<void> signOut() async {
    final cookie = await _store.read();
    // Apaga do aparelho primeiro: sair nunca depende da rede.
    await _store.clear();
    if (cookie == null) return;
    try {
      await _client.post(
        _u('/v1/auth/sign-out'),
        headers: {'cookie': cookie, 'origin': _origin, 'content-type': 'application/json'},
        body: '{}',
      ).timeout(timeout);
    } catch (_) {
      // Melhor esforço: sem rede ou origem recusada, a sessão expira no
      // servidor em até 12 h.
    }
  }

  Future<http.Response> _get(String path, String cookie) async {
    try {
      return await _client
          .get(_u(path), headers: {'accept': 'application/json', 'cookie': cookie})
          .timeout(timeout);
    } on TimeoutException {
      throw const AuthException(AuthFailure.network);
    } on http.ClientException {
      throw const AuthException(AuthFailure.network);
    }
  }

  static Map<String, Object?> _json(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map<String, Object?>) return d;
    } on FormatException {
      // cai no erro abaixo
    }
    throw const AuthException(AuthFailure.server);
  }

  static String? _errorCode(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map && d['error'] is Map) return (d['error'] as Map)['code'] as String?;
      if (d is Map) return d['code'] as String?;
    } catch (_) {
      // sem corpo legível
    }
    return null;
  }

  /// Extrai só `nome=valor` do cookie de sessão. Vários Set-Cookie podem vir
  /// juntos, separados por vírgula; o valor do cookie não tem vírgula.
  static String? _extractSessionCookie(String? header) {
    if (header == null) return null;
    for (final name in _cookieNames) {
      final m = RegExp('(?:^|[,;\\s])${RegExp.escape(name)}=([^;,\\s]+)').firstMatch(header);
      if (m != null && m.group(1)!.isNotEmpty) return '$name=${m.group(1)}';
    }
    return null;
  }
}
