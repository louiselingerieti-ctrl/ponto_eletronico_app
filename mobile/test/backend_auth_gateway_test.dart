import 'dart:convert';

import 'package:casa_futuro_colaborador/features/session/session_models.dart';
import 'package:casa_futuro_colaborador/integration/backend/backend_auth_gateway.dart';
import 'package:casa_futuro_colaborador/integration/backend/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Servidor FALSO que imita o backend (contrato lido no código do backend em
/// 11/11/2026). Não acessa a rede nem o servidor de produção.
class FakeBackend {
  String password = 'senha-correta-12';
  String accountStatus = 'active';
  bool mustChange = false;
  int signInStatus = 200;
  List<Map<String, Object?>> memberships = [
    {
      'tenantId': '00000000-0000-4000-8000-0000000000a1',
      'tenantSlug': 'casa-do-futuro',
      'tenantName': 'Casa do Futuro',
      'tenantStatus': 'active',
      'membershipStatus': 'active',
      'roles': ['employee'],
    }
  ];
  final requests = <http.Request>[];
  String? validToken = 'tok.sig';

  /// Better Auth confia na origem do próprio baseURL; aqui, a da API falsa.
  String trustedOrigin = 'https://api.exemplo.test';
  bool get _originOk => requests.last.headers['origin'] == trustedOrigin;

  MockClient get client => MockClient((r) async {
        requests.add(r);
        final cookie = r.headers['cookie'];
        final authed = cookie == '__Secure-ponto.session_token=$validToken' && validToken != null;
        switch ('${r.method} ${r.url.path}') {
          case 'POST /v1/auth/sign-in/email':
            if (signInStatus != 200) return http.Response('{"message":"x"}', signInStatus);
            final b = jsonDecode(r.body) as Map;
            if (b['password'] != password) {
              return http.Response('{"message":"Invalid email or password","code":"INVALID_EMAIL_OR_PASSWORD"}', 401);
            }
            if (accountStatus != 'active') return http.Response('{"message":"forbidden"}', 403);
            return http.Response('{"redirect":false,"token":"tok","user":{}}', 200, headers: {
              // Vários Set-Cookie juntos, como o cliente HTTP os entrega.
              'set-cookie': '__Secure-ponto.session_token=$validToken; Max-Age=43200; Path=/; '
                  'HttpOnly; Secure; SameSite=Lax,__Secure-ponto.session_data=abc; Path=/; HttpOnly',
            });
          case 'GET /v1/me':
            if (!authed) return http.Response('{"error":{"code":"unauthenticated"}}', 401);
            if (accountStatus != 'active') {
              return http.Response('{"error":{"code":"account_inactive"}}', 401);
            }
            return http.Response(
                jsonEncode({
                  'accountId': '00000000-0000-4000-8000-0000000000c1',
                  'email': 'ana@casadofuturo.com.br',
                  'name': 'Ana Souza',
                  'mustChangePassword': mustChange,
                  'sessionExpiresAt': '2026-11-11T23:00:00.000Z',
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          case 'POST /v1/auth/change-password':
            if (!authed) return http.Response('{"message":"Unauthorized"}', 401);
            if (!_originOk) {
              return http.Response('{"message":"Invalid origin","code":"MISSING_OR_NULL_ORIGIN"}', 403);
            }
            final b = jsonDecode(r.body) as Map;
            if (b['currentPassword'] != password) {
              return http.Response('{"message":"Invalid password","code":"INVALID_PASSWORD"}', 400);
            }
            if ((b['newPassword'] as String).length < 12) {
              return http.Response('{"message":"Password too short","code":"PASSWORD_TOO_SHORT"}', 400);
            }
            password = b['newPassword'] as String;
            mustChange = false;
            // revokeOtherSessions: sessão nova.
            validToken = b['revokeOtherSessions'] == true ? 'novo.sig' : validToken;
            return http.Response('{"token":"novo"}', 200, headers: {
              'set-cookie': '__Secure-ponto.session_token=$validToken; Max-Age=43200; Path=/; HttpOnly; Secure',
            });
          case 'POST /v1/auth/sign-out':
            if (!_originOk) return http.Response('{"code":"MISSING_OR_NULL_ORIGIN"}', 403);
            if (authed) validToken = null; // sessão encerrada no servidor
            return http.Response('{"success":true}', 200);
          case 'GET /v1/me/memberships':
            if (!authed) return http.Response('{"error":{"code":"unauthenticated"}}', 401);
            if (mustChange) {
              return http.Response('{"error":{"code":"password_change_required"}}', 403);
            }
            return http.Response(jsonEncode({'items': memberships}), 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response('not found', 404);
      });
}

void main() {
  late FakeBackend fake;
  late MemorySessionStore store;
  late BackendAuthGateway gw;
  final base = Uri.parse('https://api.exemplo.test');

  setUp(() {
    fake = FakeBackend();
    store = MemorySessionStore();
    gw = BackendAuthGateway(baseUrl: base, store: store, client: fake.client);
  });

  Future<AuthFailure> failureOf(Future<Object?> f) async {
    try {
      await f;
    } on AuthException catch (e) {
      return e.failure;
    }
    fail('esperava AuthException');
  }

  test('login: guarda só nome=valor do cookie de sessão e lê /v1/me', () async {
    final u = await gw.signIn(' ana@casadofuturo.com.br ', 'senha-correta-12');
    expect(u.name, 'Ana Souza');
    expect(u.firstName, 'Ana');
    expect(u.initials, 'AS');
    expect(store.value, '__Secure-ponto.session_token=tok.sig');
    final signIn = fake.requests.first;
    expect(signIn.url.toString(), 'https://api.exemplo.test/v1/auth/sign-in/email');
    expect(signIn.headers.containsKey('cookie'), isFalse,
        reason: 'login sem cookie antigo (checagem de Origin do backend)');
    expect((jsonDecode(signIn.body) as Map)['email'], 'ana@casadofuturo.com.br');
    expect(fake.requests[1].headers['cookie'], '__Secure-ponto.session_token=tok.sig');
  });

  test('senha errada: invalidCredentials e nada guardado', () async {
    expect(await failureOf(gw.signIn('ana@casadofuturo.com.br', 'errada')),
        AuthFailure.invalidCredentials);
    expect(store.value, isNull);
  });

  test('conta desativada no login (403) e em sessão existente (401 account_inactive)', () async {
    fake.accountStatus = 'disabled';
    expect(await failureOf(gw.signIn('a@b.co', 'senha-correta-12')), AuthFailure.accountInactive);
    store.value = '__Secure-ponto.session_token=tok.sig';
    expect(await failureOf(gw.restore()), AuthFailure.accountInactive);
    expect(store.value, isNull);
  });

  test('excesso de tentativas (429) e falha do servidor (500)', () async {
    fake.signInStatus = 429;
    expect(await failureOf(gw.signIn('a@b.co', 'x')), AuthFailure.rateLimited);
    fake.signInStatus = 500;
    expect(await failureOf(gw.signIn('a@b.co', 'x')), AuthFailure.server);
  });

  test('login sem cookie de sessão na resposta: erro de servidor', () async {
    final g = BackendAuthGateway(
      baseUrl: base,
      store: store,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(await failureOf(g.signIn('a@b.co', 'x')), AuthFailure.server);
    expect(store.value, isNull);
  });

  test('sem rede: network, e a sessão guardada não é apagada', () async {
    store.value = '__Secure-ponto.session_token=tok.sig';
    final g = BackendAuthGateway(
      baseUrl: base,
      store: store,
      client: MockClient((_) async => throw http.ClientException('sem rede')),
    );
    expect(await failureOf(g.restore()), AuthFailure.network);
    expect(store.value, isNotNull);
  });

  test('retomar sessão: válida → usuário; expirada → null e apaga', () async {
    store.value = '__Secure-ponto.session_token=tok.sig';
    expect((await gw.restore())!.email, 'ana@casadofuturo.com.br');
    fake.validToken = null;
    expect(await gw.restore(), isNull);
    expect(store.value, isNull);
  });

  test('acessos: lê memberships; senha temporária → passwordChangeRequired', () async {
    await gw.signIn('a@b.co', 'senha-correta-12');
    final ms = await gw.memberships();
    expect(ms.single.tenantName, 'Casa do Futuro');
    expect(ms.single.usable, isTrue);
    fake.mustChange = true;
    expect(await failureOf(gw.memberships()), AuthFailure.passwordChangeRequired);
  });

  test('resposta fora do contrato vira erro de servidor (não é aceita)', () async {
    await gw.signIn('a@b.co', 'senha-correta-12');
    fake.memberships = [
      {'tenantId': 1, 'roles': 'employee'}
    ];
    expect(await failureOf(gw.memberships()), AuthFailure.server);
  });

  test('sair encerra a sessão no servidor (com Origin da API) e apaga do aparelho', () async {
    await gw.signIn('a@b.co', 'senha-correta-12');
    await gw.signOut();
    expect(store.value, isNull);
    final out = fake.requests.last;
    expect(out.url.path, '/v1/auth/sign-out');
    expect(out.headers['origin'], 'https://api.exemplo.test');
    expect(fake.validToken, isNull, reason: 'servidor encerrou a sessão');
  });

  test('sair sem rede ou com origem recusada ainda apaga do aparelho', () async {
    await gw.signIn('a@b.co', 'senha-correta-12');
    fake.trustedOrigin = 'https://outra.origem';
    await gw.signOut();
    expect(store.value, isNull);
  });

  group('troca de senha temporária', () {
    setUp(() async {
      fake
        ..mustChange = true
        ..password = 'temporaria-123';
      await gw.signIn('a@b.co', 'temporaria-123');
    });

    test('sucesso: envia cookie e Origin, guarda a sessão nova e a conta sai do modo temporário',
        () async {
      final u = await gw.changePassword('temporaria-123', 'minha-nova-senha-segura');
      expect(u.mustChangePassword, isFalse);
      expect(store.value, '__Secure-ponto.session_token=novo.sig');
      final req = fake.requests.firstWhere((r) => r.url.path == '/v1/auth/change-password');
      expect(req.headers['origin'], 'https://api.exemplo.test');
      expect(req.headers['cookie'], '__Secure-ponto.session_token=tok.sig');
      expect((jsonDecode(req.body) as Map)['revokeOtherSessions'], isTrue);
    });

    test('senha temporária errada', () async {
      expect(await failureOf(gw.changePassword('errada', 'minha-nova-senha-segura')),
          AuthFailure.currentPasswordWrong);
    });

    test('nova senha curta (regra do servidor)', () async {
      expect(await failureOf(gw.changePassword('temporaria-123', 'curta')),
          AuthFailure.weakPassword);
    });

    test('servidor recusa a origem: troca indisponível, sem travar', () async {
      fake.trustedOrigin = 'https://portal.exemplo.test';
      expect(await failureOf(gw.changePassword('temporaria-123', 'minha-nova-senha-segura')),
          AuthFailure.passwordChangeUnavailable);
      expect(store.value, isNotNull, reason: 'sessão mantida para tentar de novo');
    });
  });

  test('só aceita https', () {
    expect(() => BackendAuthGateway(baseUrl: Uri.parse('http://api.exemplo.test'), store: store),
        throwsArgumentError);
  });

  test('a senha nunca aparece em mensagem de erro', () async {
    const segredo = 'minha-senha-secreta';
    try {
      await gw.signIn('a@b.co', segredo);
    } on AuthException catch (e) {
      expect(e.toString().contains(segredo), isFalse);
      expect(e.failure.message.contains(segredo), isFalse);
    }
  });
}
