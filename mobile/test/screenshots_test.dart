import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Gera as capturas Flutter equivalentes ao álbum (build/screenshots/).
/// Renderização do flutter_test (software), fontes reais empacotadas.
/// Serve para COMPARAÇÃO visual; não substitui conferir no aparelho.
void main() {
  setUpAll(loadAppFonts);
  const size = Size(400, 860);

  testWidgets('01-inicio', (t) async {
    await pumpApp(t, size: size);
    await capture(t, '01-inicio');
  });

  testWidgets('02-historico', (t) async {
    await pumpApp(t, size: size);
    await tapNav(t, 'Histórico');
    await capture(t, '02-historico');
  });

  testWidgets('03-solicitacoes', (t) async {
    await pumpApp(t, size: size);
    await tapNav(t, 'Solicitações');
    await capture(t, '03-solicitacoes');
  });

  testWidgets('04-nova-solicitacao', (t) async {
    await pumpApp(t, size: size);
    await tapNav(t, 'Solicitações');
    await tapText(t, 'Nova solicitação');
    await capture(t, '04-nova-solicitacao');
  });

  testWidgets('05-pedido-enviado', (t) async {
    await pumpApp(t, size: size);
    await tapNav(t, 'Solicitações');
    await tapText(t, 'Nova solicitação');
    await t.enterText(find.byType(TextFormField), 'Cheguei às 08:00 e a entrada não foi detectada no aparelho.');
    await tapText(t, 'Enviar solicitação de demonstração');
    await capture(t, '05-pedido-enviado');
  });

  testWidgets('06-pedido-respondido', (t) async {
    await pumpApp(t, size: size);
    await tapNav(t, 'Solicitações');
    await t.tap(find.text('Ver solicitação e resposta').last);
    await t.pumpAndSettle();
    await capture(t, '06-pedido-respondido');
  });

  testWidgets('07-areas', (t) async {
    await pumpApp(t, size: size);
    await tapText(t, 'Ver todas');
    await capture(t, '07-areas');
  });

  testWidgets('08-perfil', (t) async {
    await pumpApp(t, size: size);
    await tapNav(t, 'Perfil');
    await capture(t, '08-perfil');
  });

  testWidgets('09-permissoes', (t) async {
    await pumpApp(t, size: size);
    await tapNav(t, 'Perfil');
    await tapText(t, 'Consultar');
    await capture(t, '09-permissoes');
  });

  testWidgets('10-permissao-pendente', (t) async {
    final s = await pumpApp(t, size: size);
    s.backend.setLocationGranted(false);
    await t.pumpAndSettle();
    await capture(t, '10-permissao-pendente');
  });

  testWidgets('11-sincronizacao', (t) async {
    await pumpApp(t, size: size);
    await tapText(t, 'Ver detalhes');
    await capture(t, '11-sincronizacao');
  });

  testWidgets('12-offline', (t) async {
    final s = await pumpApp(t, size: size);
    s.backend.setOffline(true);
    await t.pumpAndSettle();
    await tapText(t, 'Ver detalhes');
    await capture(t, '12-offline');
  });

  testWidgets('13-rascunho-offline', (t) async {
    final s = await pumpApp(t, size: size);
    s.backend.setOffline(true);
    await t.pumpAndSettle();
    await tapNav(t, 'Solicitações');
    await tapText(t, 'Nova solicitação');
    await t.enterText(find.byType(TextFormField), 'A detecção falhou durante o período sem conexão.');
    await tapText(t, 'Guardar rascunho de demonstração');
    await capture(t, '13-rascunho-offline');
  });

  testWidgets('14-login', (t) async {
    await pumpApp(t, size: size, signedIn: false);
    await capture(t, '14-login');
  });

  testWidgets('15-inicio-escuro', (t) async {
    final s = await pumpApp(t, size: size, dark: true);
    s.backend
      ..setLocationGranted(false)
      ..setOffline(true);
    await t.pumpAndSettle();
    await capture(t, '15-inicio-escuro');
  });

  // Contextos que o álbum não define (para revisão da adaptação).
  testWidgets('ctx-emulador-login', (t) async {
    await pumpApp(t, size: const Size(320, 533), signedIn: false);
    await capture(t, 'ctx-emulador-login');
  });

  testWidgets('ctx-emulador-inicio', (t) async {
    await pumpApp(t, size: const Size(320, 533));
    await capture(t, 'ctx-emulador-inicio');
  });

  testWidgets('ctx-paisagem-inicio', (t) async {
    await pumpApp(t, size: const Size(800, 360));
    await capture(t, 'ctx-paisagem-inicio');
  });

  testWidgets('ctx-tablet-solicitacoes', (t) async {
    await pumpApp(t, size: const Size(768, 1024));
    await tapNav(t, 'Solicitações');
    await capture(t, 'ctx-tablet-solicitacoes');
  });

  testWidgets('ctx-navegador-inicio', (t) async {
    await pumpApp(t, size: const Size(1280, 800), dark: true);
    await capture(t, 'ctx-navegador-inicio');
  });

  testWidgets('16-menu-compacto', (t) async {
    await pumpApp(t, size: const Size(320, 1180), dark: true);
    await tapNav(t, 'Solicitações');
    await capture(t, '16-menu-compacto');
  });
}
