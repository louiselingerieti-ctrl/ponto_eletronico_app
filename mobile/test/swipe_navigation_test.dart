import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Troca de área deslizando a tela (PageView), com o menu acompanhando.
void main() {
  setUpAll(loadAppFonts);

  const titles = ['Bom dia, Ana.', 'Meu histórico', 'Agora, tire sua foto', 'Minhas solicitações', 'Meu perfil'];
  const navs = ['Início', 'Histórico', 'Registrar', 'Solicitações', 'Perfil'];

  Future<void> swipe(WidgetTester t, {required bool toNext}) async {
    await t.fling(find.byType(PageView), Offset(toNext ? -300 : 300, 0), 1200);
    await settleSimulated(t);
  }

  bool selected(WidgetTester t, String nav) =>
      t.getSemantics(find.bySemanticsLabel(nav)).flagsCollection.isSelected == Tristate.isTrue;

  testWidgets('deslizar percorre as cinco áreas nos dois sentidos e o menu acompanha',
      (t) async {
    await pumpApp(t);
    for (var i = 1; i < titles.length; i++) {
      await swipe(t, toNext: true);
      expect(find.text(titles[i]).hitTestable(), findsOneWidget, reason: 'ida $i');
      expect(selected(t, navs[i]), isTrue, reason: navs[i]);
    }
    // Na última área, deslizar para a frente não sai do lugar.
    await swipe(t, toNext: true);
    expect(find.text(titles.last).hitTestable(), findsOneWidget);
    for (var i = titles.length - 2; i >= 0; i--) {
      await swipe(t, toNext: false);
      expect(find.text(titles[i]).hitTestable(), findsOneWidget, reason: 'volta $i');
      expect(selected(t, navs[i]), isTrue, reason: navs[i]);
    }
  });

  testWidgets('tocar no menu continua levando direto à área, inclusive as distantes',
      (t) async {
    await pumpApp(t);
    await tapNav(t, 'Perfil');
    expect(find.text('Meu perfil').hitTestable(), findsOneWidget);
    await tapNav(t, 'Histórico');
    expect(find.text('Meu histórico').hitTestable(), findsOneWidget);
    // Deslizar a partir dali segue a ordem do menu.
    await swipe(t, toNext: true);
    expect(find.text('Agora, tire sua foto').hitTestable(), findsOneWidget);
  });

  testWidgets('dentro do detalhe, deslizar não troca de área', (t) async {
    await pumpApp(t);
    await tapNav(t, 'Solicitações');
    await tapText(t, 'Ver solicitação e resposta');
    expect(find.text('Sua solicitação').hitTestable(), findsOneWidget);
    await swipe(t, toNext: true);
    expect(find.text('Sua solicitação').hitTestable(), findsOneWidget);
    expect(selected(t, 'Solicitações'), isTrue);
    // Ao voltar para a lista, deslizar volta a funcionar.
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await swipe(t, toNext: true);
    expect(find.text('Meu perfil').hitTestable(), findsOneWidget);
  });

  testWidgets('o rascunho do formulário sobrevive a deslizar entre outras áreas', (t) async {
    await pumpApp(t);
    await tapNav(t, 'Solicitações');
    await tapText(t, 'Nova solicitação');
    await t.enterText(find.byType(TextFormField), 'rascunho que não pode sumir');
    await tapNav(t, 'Início');
    await swipe(t, toNext: true); // Histórico
    await swipe(t, toNext: true); // Registrar
    await swipe(t, toNext: true); // Solicitações
    expect(find.text('rascunho que não pode sumir'), findsOneWidget);
  });

  testWidgets('movimento reduzido: a troca pelo menu é direta e funciona', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(t);
    await tapNav(t, 'Histórico');
    expect(find.text('Meu histórico').hitTestable(), findsOneWidget);
    await tapNav(t, 'Início');
    expect(find.text('Bom dia, Ana.').hitTestable(), findsOneWidget);
  });
}
