import 'package:casa_futuro_colaborador/app/app.dart';
import 'package:casa_futuro_colaborador/app/app_services.dart';
import 'package:casa_futuro_colaborador/integration/backend/backend_auth_gateway.dart';
import 'package:casa_futuro_colaborador/integration/backend/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backend_auth_gateway_test.dart' show FakeBackend;
import 'support.dart';

/// Fluxo de login REAL pela tela, contra o servidor falso.
void main() {
  setUpAll(loadAppFonts);

  Future<(AppServices, FakeBackend, MemorySessionStore)> pumpReal(WidgetTester t,
      {void Function(FakeBackend)? setup, String? storedCookie}) async {
    t.view.physicalSize = const Size(400, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final fake = FakeBackend();
    setup?.call(fake);
    final store = MemorySessionStore()..value = storedCookie;
    final s = AppServices(
      now: () => demoNow,
      auth: BackendAuthGateway(
          baseUrl: Uri.parse('https://api.exemplo.test'), store: store, client: fake.client),
    );
    addTearDown(s.dispose);
    await t.pumpWidget(CasaFuturoApp(services: s, themeMode: ThemeMode.light));
    await s.init();
    await t.pumpAndSettle();
    return (s, fake, store);
  }

  Future<void> login(WidgetTester t, String password) async {
    await t.enterText(find.byType(TextFormField).first, 'ana@casadofuturo.com.br');
    await t.enterText(find.byType(TextFormField).last, password);
    await tapText(t, 'Entrar');
  }

  testWidgets('entra com a conta real: nome e empresa do servidor; telas simuladas avisam',
      (t) async {
    final (_, _, store) = await pumpReal(t);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Entrar na demonstração'), findsNothing);
    await login(t, 'senha-correta-12');
    expect(find.text('Bom dia, Ana.'), findsOneWidget);
    expect(find.text('Demonstração: dados fictícios nesta tela'), findsOneWidget);
    expect(find.text('Conta real • detecções e pedidos em demonstração'), findsOneWidget);
    expect(store.value, isNotNull);

    await tapNav(t, 'Perfil');
    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('Casa do Futuro'), findsWidgets);
    expect(find.text('ana@casadofuturo.com.br'), findsOneWidget);
    expect(find.textContaining('Loja Centro'), findsNothing, reason: 'vínculo fictício não aparece');
  });

  testWidgets('senha errada: mensagem clara e continua no login', (t) async {
    await pumpReal(t);
    await login(t, 'errada');
    expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
    expect(find.text('Bom dia, Ana.'), findsNothing);
  });

  Future<void> fillNewPassword(WidgetTester t, String current, String next, String confirm) async {
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(0), current);
    await t.enterText(fields.at(1), next);
    await t.enterText(fields.at(2), confirm);
    await tapText(t, 'Salvar nova senha');
  }

  testWidgets('senha temporária: abre "Crie sua senha", troca no app e entra', (t) async {
    final (_, fake, store) = await pumpReal(t, setup: (f) {
      f
        ..mustChange = true
        ..password = 'temporaria-123';
    });
    await login(t, 'temporaria-123');
    expect(find.text('Crie sua senha'), findsOneWidget);
    expect(find.textContaining('Troque-a pelo portal'), findsNothing);
    await fillNewPassword(t, 'temporaria-123', 'minha-nova-senha-segura', 'minha-nova-senha-segura');
    expect(find.text('Bom dia, Ana.'), findsOneWidget);
    expect(fake.password, 'minha-nova-senha-segura');
    expect(store.value, '__Secure-ponto.session_token=novo.sig');
  });

  testWidgets('troca de senha: validação na tela antes de enviar', (t) async {
    final (_, fake, _) = await pumpReal(t, setup: (f) {
      f
        ..mustChange = true
        ..password = 'temporaria-123';
    });
    await login(t, 'temporaria-123');
    await fillNewPassword(t, 'temporaria-123', 'curta', 'curta');
    expect(find.text('Use de 12 a 128 caracteres.'), findsOneWidget);
    await fillNewPassword(t, 'temporaria-123', 'minha-nova-senha-segura', 'outra-coisa-diferente');
    expect(find.text('As senhas não conferem.'), findsOneWidget);
    await fillNewPassword(t, 'temporaria-123', 'temporaria-123', 'temporaria-123');
    expect(find.text('A nova senha precisa ser diferente da temporária.'), findsOneWidget);
    expect(fake.requests.where((r) => r.url.path == '/v1/auth/change-password'), isEmpty);
  });

  testWidgets('troca de senha: temporária errada mostra o erro e permite tentar de novo',
      (t) async {
    await pumpReal(t, setup: (f) {
      f
        ..mustChange = true
        ..password = 'temporaria-123';
    });
    await login(t, 'temporaria-123');
    await fillNewPassword(t, 'errada-errada', 'minha-nova-senha-segura', 'minha-nova-senha-segura');
    expect(find.text('A senha temporária não confere.'), findsOneWidget);
    expect(find.text('Crie sua senha'), findsOneWidget);
    await fillNewPassword(t, 'temporaria-123', 'minha-nova-senha-segura', 'minha-nova-senha-segura');
    expect(find.text('Bom dia, Ana.'), findsOneWidget);
  });

  testWidgets('troca de senha: sair volta ao login e apaga a sessão', (t) async {
    final (_, _, store) = await pumpReal(t, setup: (f) {
      f
        ..mustChange = true
        ..password = 'temporaria-123';
    });
    await login(t, 'temporaria-123');
    await tapText(t, 'Sair');
    expect(find.text('Entrar'), findsOneWidget);
    expect(store.value, isNull);
  });

  testWidgets('sem acesso ativo a uma empresa: não entra', (t) async {
    await pumpReal(t, setup: (f) => f.memberships = []);
    await login(t, 'senha-correta-12');
    expect(find.textContaining('não tem um acesso ativo'), findsOneWidget);
  });

  for (final roles in [
    ['tenant_admin'],
    ['hr'],
    ['manager'],
    ['tenant_admin', 'hr', 'manager'],
  ]) {
    testWidgets('só gestão ($roles): login recusado e sessão apagada', (t) async {
      final (_, _, store) = await pumpReal(t,
          setup: (f) => f.memberships = [
                {...f.memberships.single, 'roles': roles}
              ]);
      await login(t, 'senha-correta-12');
      expect(find.text('Este app é só para colaboradores. Para administrar, use o portal.'),
          findsOneWidget);
      expect(find.text('Bom dia, Ana.'), findsNothing);
      expect(store.value, isNull);
    });
  }

  testWidgets('gestão numa empresa e colaborador em outra: só a de colaborador entra',
      (t) async {
    await pumpReal(t, setup: (f) => f.memberships = [
          {...f.memberships.single, 'tenantName': 'Empresa Admin', 'roles': ['tenant_admin']},
          {...f.memberships.single, 'tenantId': '00000000-0000-4000-8000-0000000000a2',
            'tenantName': 'Empresa Colaborador', 'roles': ['employee']},
        ]);
    await login(t, 'senha-correta-12');
    // Uma só opção válida: entra direto, sem oferecer a de gestão.
    expect(find.text('Bom dia, Ana.'), findsOneWidget);
    await tapNav(t, 'Perfil');
    expect(find.text('Empresa Colaborador'), findsOneWidget);
    expect(find.text('Empresa Admin'), findsNothing);
  });

  testWidgets('dois acessos: escolha explícita da empresa', (t) async {
    await pumpReal(t, setup: (f) => f.memberships = [
          {...f.memberships.single},
          {...f.memberships.single, 'tenantId': '00000000-0000-4000-8000-0000000000a2', 'tenantName': 'Outra Empresa'},
        ]);
    await login(t, 'senha-correta-12');
    expect(find.text('Escolha a empresa que você quer acompanhar.'), findsOneWidget);
    await tapText(t, 'Outra Empresa');
    await tapNav(t, 'Perfil');
    expect(find.text('Outra Empresa'), findsOneWidget);
  });

  testWidgets('sessão guardada é retomada ao abrir; sair apaga do aparelho', (t) async {
    final (_, _, store) =
        await pumpReal(t, storedCookie: '__Secure-ponto.session_token=tok.sig');
    expect(find.text('Bom dia, Ana.'), findsOneWidget);
    await tapNav(t, 'Perfil');
    await tapText(t, 'Sair da conta');
    expect(find.textContaining('em até 12 horas'), findsOneWidget);
    await tapText(t, 'Sair');
    expect(find.text('Entrar'), findsOneWidget);
    expect(store.value, isNull);
  });

  testWidgets('sessão guardada expirada: volta ao login sem erro', (t) async {
    await pumpReal(t, storedCookie: '__Secure-ponto.session_token=velho');
    expect(find.text('Entrar'), findsOneWidget);
  });
}
