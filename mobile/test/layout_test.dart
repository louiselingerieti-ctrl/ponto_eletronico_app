import 'package:casa_futuro_colaborador/app/app.dart';
import 'package:casa_futuro_colaborador/app/app_services.dart';
import 'package:casa_futuro_colaborador/shared/layout/cdf_layout.dart';
import 'package:casa_futuro_colaborador/shared/widgets/cdf_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Contextos de referência (tamanho lógico da janela).
const contexts = <String, Size>{
  'emulador 480x800@240': Size(320, 533),
  'celular pequeno': Size(360, 640),
  'padrão (álbum)': Size(400, 860),
  'celular grande': Size(412, 915),
  'paisagem': Size(800, 360),
  'tablet retrato': Size(768, 1024),
  'navegador largo': Size(1280, 800),
};

void main() {
  setUpAll(loadAppFonts);

  group('regras', () {
    test('no contexto do álbum, valores idênticos ao protótipo aprovado', () {
      final l = CdfLayout.from(const Size(400, 860));
      expect(l.width, WidthClass.standard);
      expect(l.height, HeightClass.regular);
      expect(
        [l.hPad, l.h1, l.loginTitle, l.loginTop, l.introGap, l.titleGap, l.sectionGap,
          l.surfacePadding, l.headerTop, l.headerBottom, l.presenceIcon, l.presenceTop,
          l.presenceBottom],
        [22, 28, 34, 36, 24, 8, 24, 20, 16, 22, 56, 20, 18],
      );
      expect([l.fieldLabelTop, l.fieldLabelBottom, l.fieldPadding, l.formButtonTop, l.noteVertical],
          [20, 8, 14, 16, 14]);
      expect(l.maxContentWidth, double.infinity);
    });

    test('320 de largura (álbum compacto): só margem 16, título 26 e cabeçalho 16', () {
      final l = CdfLayout.from(const Size(320, 760));
      expect(l.width, WidthClass.compact);
      expect([l.hPad, l.h1, l.headerBottom, l.loginTitle], [16, 26, 16, 34]);
    });

    test('altura baixa reduz títulos e espaços; tela larga limita a coluna', () {
      final short = CdfLayout.from(const Size(320, 560));
      expect(short.isShort, isTrue);
      expect([short.h1, short.loginTitle, short.loginTop, short.fieldPadding], [24, 28, 12, 12]);
      // Telas ainda menores não apertam mais: rolam um pouco.
      expect(CdfLayout.from(const Size(320, 461)), short);
      expect(CdfLayout.from(const Size(768, 1000)).maxContentWidth, 560);
      expect(CdfLayout.from(const Size(1280, 760)).width, WidthClass.expanded);
    });
  });

  group('matriz de contextos', () {
    for (final MapEntry(key: name, value: size) in contexts.entries) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('$name, fonte ×$scale: todas as telas sem corte', (t) async {
          await pumpApp(t, size: size, textScale: scale);
          for (final nav in ['Histórico', 'Solicitar', 'Áreas', 'Perfil', 'Início']) {
            await tapNav(t, nav);
            expect(t.takeException(), isNull, reason: nav);
          }
          await tapText(t, 'Ver sincronização');
          expect(t.takeException(), isNull, reason: 'sincronização');
          await tapNav(t, 'Solicitar');
          await tapText(t, 'Nova solicitação');
          expect(t.takeException(), isNull, reason: 'formulário');
          await tapNav(t, 'Perfil');
          await tapText(t, 'Consultar');
          expect(t.takeException(), isNull, reason: 'permissões');
        });
      }

      testWidgets('$name: login sem corte', (t) async {
        await pumpApp(t, size: size, signedIn: false);
        expect(t.takeException(), isNull);
      });
    }
  });

  // Rolagem como último recurso: o login inteiro cabe sem rolar nas alturas
  // úteis comuns. Em telas muito pequenas rola um pouco (decisão: preferível
  // a apertar a leitura).
  for (final (name, size) in [
    ('celular pequeno 360x640 (útil ~590)', const Size(360, 590)),
    ('celular comum', const Size(360, 760)),
  ]) {
    testWidgets('login cabe sem rolar: $name', (t) async {
      await pumpApp(t, size: size, signedIn: false);
      // O primeiro Scrollable é o da página (campos de texto têm o próprio).
      final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(pos.maxScrollExtent, 0, reason: 'sobram ${pos.maxScrollExtent.toStringAsFixed(1)} dp de rolagem');
      // A rolagem continua disponível como rede de segurança (fonte maior,
      // teclado, telas ainda menores).
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  }

  testWidgets('fim do conteúdo nunca fica escondido atrás do menu', (t) async {
    for (final size in [const Size(320, 533), const Size(800, 360), const Size(400, 860)]) {
      await pumpApp(t, size: size);
      await t.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
      await t.pumpAndSettle();
      final note = t.getRect(find.textContaining('não confirma a jornada'));
      final navTop = t.getRect(find.text('Início').last).top - 10 - 20 - 5 - 8;
      expect(note.bottom <= navTop, isTrue, reason: '$size: nota $note, menu em $navTop');
    }
  });

  testWidgets('emulador real (480x800 px, densidade 1,5, barras de 36 px): botão visível, rolagem pequena',
      (t) async {
    t.view.physicalSize = const Size(480, 800);
    t.view.devicePixelRatio = 1.5;
    t.view.padding = const FakeViewPadding(top: 36, bottom: 36);
    addTearDown(t.view.reset);
    final s = AppServices(now: () => demoNow);
    addTearDown(s.dispose);
    await t.pumpWidget(CasaFuturoApp(services: s, themeMode: ThemeMode.light));
    await t.pumpAndSettle();
    // A classe não pode depender de onde é consultada (dentro do SafeArea):
    // 533 dp menos as barras (24 + 24) = 485 → tela baixa.
    final ctx = t.element(find.text('Entrar na demonstração'));
    expect(CdfLayout.of(ctx).isShort, isTrue);
    // A ação principal aparece sem rolar; a rolagem que sobra é pequena.
    final btn = t.getRect(find.text('Entrar na demonstração'));
    final footer = t.getRect(find.text('Demonstração • dados fictícios'));
    expect(btn.bottom < footer.top - 9, isTrue, reason: 'botão $btn, rodapé $footer');
    final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(pos.maxScrollExtent < 80, isTrue, reason: 'rolagem de ${pos.maxScrollExtent} dp');
  });

  testWidgets('tela larga: conteúdo em coluna central de até 560', (t) async {
    await pumpApp(t, size: const Size(1280, 800));
    final card = t.getRect(find.ancestor(
        of: find.text('Ver sincronização'), matching: find.byType(Surface)).first);
    expect(card.width <= 560, isTrue, reason: '$card');
    expect((card.center.dx - 640).abs() < 1, isTrue, reason: 'centralizado');
  });

  testWidgets('teclado aberto: formulário rola e o campo em foco fica visível', (t) async {
    await pumpApp(t, size: const Size(360, 800));
    await tapNav(t, 'Solicitar');
    await tapText(t, 'Nova solicitação');
    t.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    await t.tap(find.byType(TextFormField));
    await t.enterText(find.byType(TextFormField), 'Digitando com o teclado aberto.');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final field = t.getRect(find.byType(TextFormField));
    expect(field.top < 800 - 320, isTrue, reason: 'campo acima do teclado: $field');
  });
}
