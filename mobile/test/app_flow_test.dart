import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  group('menu inferior', () {
    testWidgets('os cinco destinos funcionam em sequência, na ordem certa', (t) async {
      await pumpApp(t);
      final labels = ['Início', 'Histórico', 'Solicitar', 'Áreas', 'Perfil'];
      final xs = [for (final l in labels) t.getCenter(find.text(l).last).dx];
      expect(xs, orderedEquals([...xs]..sort()), reason: 'ordem visual');

      final titles = {
        'Histórico': 'Meu histórico',
        'Solicitar': 'Minhas solicitações',
        'Áreas': 'Minhas áreas',
        'Perfil': 'Meu perfil',
        'Início': 'Bom dia, Ana.',
      };
      for (final MapEntry(key: nav, value: title) in titles.entries) {
        await tapNav(t, nav);
        expect(find.text(title).hitTestable(), findsOneWidget, reason: nav);
      }
    });

    testWidgets('o círculo central inteiro responde ao toque', (t) async {
      await pumpApp(t);
      final plus = find.byWidgetPredicate((w) => w is Icon && w.size == 24);
      final box = t.getRect(plus);
      // Toque perto do topo do círculo (parte que sobe acima da barra).
      await t.tapAt(Offset(box.center.dx, box.top - 6));
      await t.pumpAndSettle();
      expect(find.text('Minhas solicitações').hitTestable(), findsOneWidget);
    });

    testWidgets('Solicitar continua selecionado no detalhe e no formulário', (t) async {
      await pumpApp(t);
      await tapNav(t, 'Solicitar');
      await tapText(t, 'Ver solicitação e resposta');
      expect(find.text('Sua solicitação'), findsOneWidget);
      expect(t.getSemantics(find.bySemanticsLabel('Solicitar')).flagsCollection.isSelected,
          Tristate.isTrue);
      // A partir do detalhe, os outros destinos continuam funcionando.
      await tapNav(t, 'Áreas');
      expect(find.text('Minhas áreas').hitTestable(), findsOneWidget);
      // Voltar para Solicitar mantém o detalhe aberto (estado preservado).
      await tapNav(t, 'Solicitar');
      expect(find.text('Sua solicitação').hitTestable(), findsOneWidget);
      // Tocar de novo na área aberta volta ao início dela.
      await tapNav(t, 'Solicitar');
      expect(find.text('Minhas solicitações').hitTestable(), findsOneWidget);
    });

    testWidgets('voltar do sistema fecha o detalhe antes de sair da área', (t) async {
      await pumpApp(t);
      await tapNav(t, 'Solicitar');
      await tapText(t, 'Ver solicitação e resposta');
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Minhas solicitações').hitTestable(), findsOneWidget);
    });

    testWidgets('avatar abre o perfil', (t) async {
      await pumpApp(t);
      await t.tap(find.bySemanticsLabel('Abrir perfil'));
      await t.pumpAndSettle();
      expect(find.text('Meu perfil').hitTestable(), findsOneWidget);
    });
  });

  group('detecção e entrega (núcleo real + servidor simulado)', () {
    testWidgets('início mostra a última detecção e o pendente; envio só com ACK', (t) async {
      await pumpApp(t);
      expect(find.text('Detecção habilitada'), findsOneWidget);
      expect(find.text('Entrada na Loja Centro às 08:02'), findsOneWidget);
      expect(find.text('1 evento aguardando envio'), findsOneWidget);
      expect(find.text('Salvo no aparelho'), findsOneWidget);

      await tapText(t, 'Ver sincronização');
      expect(find.text('1 evento pendente'), findsOneWidget);
      await tapText(t, 'Simular envio agora');
      expect(find.text('Tudo enviado'), findsOneWidget);
      expect(find.textContaining('Última confirmação do servidor'), findsOneWidget);

      await tapNav(t, 'Histórico');
      expect(find.text('Recebido pelo servidor'), findsNWidgets(3));
      expect(find.text('Salvo no aparelho'), findsNothing);
    });

    testWidgets('sem conexão: envio desabilitado e nada vira recebido', (t) async {
      await pumpApp(t);
      await tapText(t, 'Ver sincronização');
      await tapText(t, 'Simular modo offline');
      expect(find.text('Sem internet'), findsOneWidget);
      final send = t.widget<FilledButton>(find.ancestor(
          of: find.text('Simular envio agora'), matching: find.byType(FilledButton)));
      expect(send.onPressed, isNull);
      await tapText(t, 'Voltar ao início');
      expect(find.text('Sem conexão com a internet'), findsOneWidget);
      expect(find.text('Salvo no aparelho'), findsOneWidget);
    });

    testWidgets('sem permissão nunca anuncia detecção habilitada', (t) async {
      await pumpApp(t);
      await tapNav(t, 'Perfil');
      await tapText(t, 'Consultar');
      await tapText(t, 'Simular permissão desativada');
      expect(find.text('Permissão pendente'), findsOneWidget);
      await tapText(t, 'Voltar ao início');
      expect(find.text('Detecção indisponível'), findsOneWidget);
      expect(find.text('Detecção habilitada'), findsNothing);
      expect(find.text('Revisar permissões'), findsOneWidget);
    });

    testWidgets('áreas mostram a configuração aplicada pelo ciclo do núcleo', (t) async {
      await pumpApp(t);
      await tapNav(t, 'Áreas');
      expect(find.text('Configuração aplicada'), findsOneWidget);
      expect(find.text('Loja Centro'), findsOneWidget);
    });
  });

  group('solicitações', () {
    Future<void> openForm(WidgetTester t) async {
      await tapNav(t, 'Solicitar');
      await tapText(t, 'Nova solicitação');
    }

    testWidgets('descrição curta é recusada e o texto é mantido', (t) async {
      await pumpApp(t);
      await openForm(t);
      await t.enterText(find.byType(TextFormField), 'curto');
      await tapText(t, 'Enviar solicitação de demonstração');
      expect(find.text('Escreva pelo menos 10 caracteres.'), findsOneWidget);
      expect(find.text('curto'), findsOneWidget);
      expect(find.text('Nova solicitação'), findsWidgets);
    });

    testWidgets('envio válido abre o detalhe em análise; toque repetido não duplica', (t) async {
      final s = await pumpApp(t);
      await openForm(t);
      await t.enterText(find.byType(TextFormField), 'A saída não apareceu no aparelho.');
      final btn = find.text('Enviar solicitação de demonstração');
      await t.ensureVisible(btn);
      await t.tap(btn);
      await t.tap(btn, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.text('Sua solicitação'), findsOneWidget);
      expect(find.text('Em análise'), findsOneWidget);
      expect(find.text('#1044 • 11/11/2026'), findsOneWidget);
      expect(s.backend.list().where((r) => r.displayId >= 1044), hasLength(1));
    });

    testWidgets('sem conexão vira rascunho local, nunca "em análise"', (t) async {
      final s = await pumpApp(t);
      s.backend.setOffline(true);
      await t.pumpAndSettle();
      await openForm(t);
      expect(find.text('Guardar rascunho de demonstração'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), 'A detecção falhou sem conexão.');
      await tapText(t, 'Guardar rascunho de demonstração');
      expect(find.text('Rascunho local'), findsOneWidget);
      expect(find.text('Em análise'), findsNothing);
      expect(find.textContaining('Ainda não foi enviado'), findsOneWidget);
    });

    testWidgets('sair do formulário com texto pede confirmação', (t) async {
      await pumpApp(t);
      await openForm(t);
      await t.enterText(find.byType(TextFormField), 'texto em andamento');
      await tapText(t, 'Cancelar');
      expect(find.text('Descartar solicitação?'), findsOneWidget);
      await tapText(t, 'Continuar editando');
      expect(find.text('texto em andamento'), findsOneWidget);
    });

    testWidgets('trocar de área não perde o rascunho do formulário', (t) async {
      await pumpApp(t);
      await openForm(t);
      await t.enterText(find.byType(TextFormField), 'não pode se perder');
      await tapNav(t, 'Início');
      await tapNav(t, 'Solicitar');
      expect(find.text('não pode se perder'), findsOneWidget);
    });
  });

  group('sessão simulada', () {
    testWidgets('login valida campos e entra; saída apaga a conta anterior', (t) async {
      final s = await pumpApp(t, signedIn: false);
      expect(find.text('Seu dia.\nSeu espaço.'), findsOneWidget);
      expect(find.bySemanticsLabel('Abrir perfil'), findsNothing);
      await tapText(t, 'Entrar na demonstração');
      expect(find.text('Informe um e-mail válido.'), findsOneWidget);

      await t.enterText(find.byType(TextFormField).first, 'ana@exemplo.com');
      await t.enterText(find.byType(TextFormField).last, 'senha-ficticia');
      await tapText(t, 'Entrar na demonstração');
      expect(find.text('Bom dia, Ana.'), findsOneWidget);

      // Cria um pedido e sai: a próxima pessoa não herda nada.
      await tapNav(t, 'Solicitar');
      await tapText(t, 'Nova solicitação');
      await t.enterText(find.byType(TextFormField), 'pedido que não pode vazar');
      await tapText(t, 'Enviar solicitação de demonstração');
      await tapNav(t, 'Perfil');
      await tapText(t, 'Sair da conta');
      expect(find.text('Sair da conta?'), findsOneWidget);
      expect(find.textContaining('sem confirmação do servidor'), findsOneWidget);
      await tapText(t, 'Sair');
      expect(find.text('Entrar na demonstração'), findsOneWidget);
      expect(s.backend.list().any((r) => r.description.contains('vazar')), isFalse);
    });
  });

  group('layout', () {
    for (final (w, scale) in [(320.0, 1.0), (320.0, 1.3), (400.0, 1.6)]) {
      testWidgets('sem overflow em $w px com fonte ×$scale', (t) async {
        await pumpApp(t, size: Size(w, 800), textScale: scale);
        for (final nav in ['Histórico', 'Solicitar', 'Áreas', 'Perfil', 'Início']) {
          await tapNav(t, nav);
          expect(t.takeException(), isNull, reason: nav);
        }
        await tapNav(t, 'Solicitar');
        await tapText(t, 'Nova solicitação');
        expect(t.takeException(), isNull, reason: 'formulário');
      });
    }

    testWidgets('alvos de toque do menu com pelo menos 48', (t) async {
      await pumpApp(t, size: const Size(320, 800));
      for (final l in ['Início', 'Histórico', 'Solicitar', 'Áreas', 'Perfil']) {
        final r = t.getRect(find.bySemanticsLabel(l));
        expect(r.width >= 48 && r.height >= 48, isTrue, reason: '$l: $r');
      }
    });
  });
}
