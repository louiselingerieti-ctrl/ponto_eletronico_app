import 'package:casa_futuro_colaborador/app/app.dart';
import 'package:casa_futuro_colaborador/app/app_services.dart';
import 'package:casa_futuro_colaborador/integration/backend/backend_auth_gateway.dart';
import 'package:casa_futuro_colaborador/integration/backend/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backend_auth_gateway_test.dart' show FakeBackend;
import 'support.dart';

/// "Puxar para atualizar": puxar a página para baixo, no topo, busca de novo
/// a conta e o acesso no servidor.
void main() {
  setUpAll(loadAppFonts);

  Future<FakeBackend> pumpSignedIn(WidgetTester t) async {
    t.view.physicalSize = const Size(400, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final fake = FakeBackend();
    final s = AppServices(
      now: () => demoNow,
      auth: BackendAuthGateway(
          baseUrl: Uri.parse('https://api.exemplo.test'),
          store: MemorySessionStore()..value = '__Secure-ponto.session_token=tok.sig',
          client: fake.client),
    );
    addTearDown(s.dispose);
    await t.pumpWidget(CasaFuturoApp(services: s, themeMode: ThemeMode.light));
    await s.init();
    await t.pumpAndSettle();
    expect(find.text('Bom dia, Ana.'), findsOneWidget);
    return fake;
  }

  Future<void> pull(WidgetTester t, String onScreen) async {
    await t.fling(find.text(onScreen).hitTestable(), const Offset(0, 400), 1500);
    await t.pumpAndSettle();
  }

  int meCalls(FakeBackend f) => f.requests.where((r) => r.url.path == '/v1/me').length;

  testWidgets('puxar no Início busca de novo a conta no servidor', (t) async {
    final fake = await pumpSignedIn(t);
    final before = meCalls(fake);
    await pull(t, 'Bom dia, Ana.');
    expect(meCalls(fake), before + 1);
    expect(find.text('Bom dia, Ana.'), findsOneWidget);
  });

  testWidgets('puxar no Perfil mostra o nome novo da empresa vindo do servidor', (t) async {
    final fake = await pumpSignedIn(t);
    await tapNav(t, 'Perfil');
    expect(find.text('Casa do Futuro'), findsWidgets);
    fake.memberships.first['tenantName'] = 'Casa do Futuro Centro';
    await pull(t, 'Meu perfil');
    expect(find.text('Casa do Futuro Centro'), findsWidgets);
  });

  testWidgets('funciona nas cinco áreas, mesmo quando o conteúdo cabe na tela', (t) async {
    final fake = await pumpSignedIn(t);
    const pages = {
      'Início': 'Bom dia, Ana.',
      'Histórico': 'Meu histórico',
      'Solicitar': 'Minhas solicitações',
      'Áreas': 'Minhas áreas',
      'Perfil': 'Meu perfil',
    };
    for (final MapEntry(key: nav, value: title) in pages.entries) {
      await tapNav(t, nav);
      final before = meCalls(fake);
      await pull(t, title);
      expect(meCalls(fake), before + 1, reason: nav);
    }
  });

  testWidgets('sessão encerrada no servidor: volta ao login com o motivo', (t) async {
    final fake = await pumpSignedIn(t);
    fake.validToken = null;
    await pull(t, 'Bom dia, Ana.');
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Sua sessão terminou. Entre novamente.'), findsOneWidget);
  });

  testWidgets('acesso retirado no servidor: sai do app e explica', (t) async {
    final fake = await pumpSignedIn(t);
    fake.memberships = [];
    await pull(t, 'Bom dia, Ana.');
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Sua conta não tem um acesso ativo a uma empresa. Procure o RH.'), findsOneWidget);
  });

  testWidgets('na demonstração, puxar não quebra nada', (t) async {
    await pumpApp(t);
    await pull(t, 'Bom dia, Ana.');
    expect(find.text('Bom dia, Ana.'), findsOneWidget);
  });
}
