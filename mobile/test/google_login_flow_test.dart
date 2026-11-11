import 'package:casa_futuro_colaborador/app/app.dart';
import 'package:casa_futuro_colaborador/app/app_services.dart';
import 'package:casa_futuro_colaborador/features/session/session_models.dart';
import 'package:casa_futuro_colaborador/integration/backend/backend_auth_gateway.dart';
import 'package:casa_futuro_colaborador/integration/backend/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backend_auth_gateway_test.dart' show FakeBackend;
import 'support.dart';

/// Google FALSO do aparelho: devolve o token combinado, null (a pessoa
/// desistiu no seletor de contas) ou falha.
class FakeGoogle implements GoogleIdTokenSource {
  String? token = 'id-token-da-ana';
  bool fails = false;
  int picks = 0;
  int signOuts = 0;

  @override
  Future<String?> idToken() async {
    picks++;
    if (fails) throw const AuthException(AuthFailure.googleUnavailable);
    return token;
  }

  @override
  Future<void> signOut() async => signOuts++;
}

/// Login com Google pela tela, contra o servidor falso e o Google falso.
void main() {
  setUpAll(loadAppFonts);

  Future<(AppServices, FakeBackend, MemorySessionStore, FakeGoogle)> pumpReal(WidgetTester t,
      {void Function(FakeBackend, FakeGoogle)? setup, bool withGoogle = true, bool dark = false}) async {
    t.view.physicalSize = const Size(400, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final fake = FakeBackend();
    final google = FakeGoogle();
    setup?.call(fake, google);
    final store = MemorySessionStore();
    final s = AppServices(
      now: () => demoNow,
      auth: BackendAuthGateway(
          baseUrl: Uri.parse('https://api.exemplo.test'), store: store, client: fake.client),
      google: withGoogle ? google : null,
    );
    addTearDown(s.dispose);
    await t.pumpWidget(RepaintBoundary(
      key: rootKey,
      child: CasaFuturoApp(services: s, themeMode: dark ? ThemeMode.dark : ThemeMode.light),
    ));
    await s.init();
    await t.pumpAndSettle();
    return (s, fake, store, google);
  }

  const button = 'Entrar com Google';

  testWidgets('o botão só aparece quando o build informou o client ID do Google', (t) async {
    await pumpReal(t, withGoogle: false);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text(button), findsNothing);
  });

  testWidgets('na demonstração não há botão do Google', (t) async {
    await pumpApp(t, signedIn: false);
    expect(find.text(button), findsNothing);
  });

  testWidgets('entra com o Google: conta do servidor, sem digitar senha', (t) async {
    final (_, fake, store, google) = await pumpReal(t);
    expect(find.text(button), findsOneWidget);
    await tapText(t, button);
    expect(find.text('Bom dia, Ana.'), findsOneWidget);
    expect(store.value, '__Secure-ponto.session_token=tok.sig');
    expect(google.picks, 1);
    expect(google.signOuts, 0, reason: 'conta que entrou continua lembrada');
    expect(fake.requests.where((r) => r.url.path == '/v1/auth/sign-in/email'), isEmpty);
  });

  testWidgets('desistir no seletor de contas não mostra erro nem chama o servidor', (t) async {
    final (_, fake, store, _) = await pumpReal(t, setup: (_, g) => g.token = null);
    await tapText(t, button);
    expect(find.text(button), findsOneWidget);
    expect(find.textContaining('Google agora'), findsNothing);
    expect(fake.requests, isEmpty);
    expect(store.value, isNull);
  });

  testWidgets('conta do Google sem cadastro: mensagem clara, conta esquecida para tentar outra',
      (t) async {
    final (_, _, store, google) =
        await pumpReal(t, setup: (_, g) => g.token = 'id-token-sem-cadastro');
    await tapText(t, button);
    expect(find.textContaining('não tem cadastro no sistema'), findsOneWidget);
    expect(find.text('Bom dia, Ana.'), findsNothing);
    expect(store.value, isNull);
    expect(google.signOuts, 1);

    // escolhe a conta certa na segunda tentativa
    google.token = 'id-token-da-ana';
    await tapText(t, button);
    expect(find.text('Bom dia, Ana.'), findsOneWidget);
    expect(find.textContaining('não tem cadastro no sistema'), findsNothing);
  });

  testWidgets('falha do Google no aparelho: orienta a usar e-mail e senha', (t) async {
    final (_, fake, _, _) = await pumpReal(t, setup: (_, g) => g.fails = true);
    await tapText(t, button);
    expect(find.text('Não foi possível entrar com o Google agora. Entre com e-mail e senha.'),
        findsOneWidget);
    expect(fake.requests, isEmpty);
  });

  testWidgets('papel de gestão entrando pelo Google: recusado como no login por senha', (t) async {
    final (_, _, store, google) = await pumpReal(t, setup: (f, _) {
      f.memberships = [
        {...f.memberships.single, 'roles': ['hr']}
      ];
    });
    await tapText(t, button);
    expect(find.textContaining('só para colaboradores'), findsOneWidget);
    expect(store.value, isNull);
    expect(google.signOuts, 1);
  });

  testWidgets('senha temporária: o Google entra, mas a troca de senha continua obrigatória',
      (t) async {
    final (_, _, _, google) = await pumpReal(t, setup: (f, _) {
      f
        ..mustChange = true
        ..password = 'temporaria-123';
    });
    await tapText(t, button);
    expect(find.text('Crie sua senha'), findsOneWidget);
    expect(google.signOuts, 0);
  });

  testWidgets('sair esquece a conta do Google do aparelho', (t) async {
    final (s, _, store, google) = await pumpReal(t);
    await tapText(t, button);
    expect(find.text('Bom dia, Ana.'), findsOneWidget);
    await s.signOut();
    await t.pumpAndSettle();
    expect(find.text(button), findsOneWidget);
    expect(store.value, isNull);
    expect(google.signOuts, 1);
  });

  for (final dark in [false, true]) {
    testWidgets('captura: login com Google (${dark ? 'escuro' : 'claro'})', (t) async {
      await pumpReal(t, dark: dark);
      await capture(t, 'google-login-${dark ? 'escuro' : 'claro'}');
    });
  }
}
