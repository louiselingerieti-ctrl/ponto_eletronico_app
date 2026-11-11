import 'package:flutter/widgets.dart';

/// Largura útil (classes de janela do Material 3, com o corte de 380 do
/// protótipo para celulares estreitos).
enum WidthClass {
  /// < 380 dp: celulares estreitos (o álbum mostra 320).
  compact,

  /// 380–599 dp: celulares comuns (o álbum foi desenhado em ~400).
  standard,

  /// 600–839 dp: tablets em retrato, celulares grandes em paisagem.
  medium,

  /// >= 840 dp: tablets em paisagem, navegador no computador.
  expanded,
}

/// Altura útil (descontadas as barras do sistema).
enum HeightClass {
  /// < 600 dp: celulares pequenos, paisagem, janela reduzida.
  short,

  /// Altura normal de celular em retrato (o álbum: ~860).
  regular,
}

/// Regras de layout adaptativo. ÚNICA fonte de espaçamento e escala
/// tipográfica que variam com o dispositivo. Cores, raios, ícones e o menu
/// (círculo de 52) não variam.
///
/// Nos contextos do álbum (standard/compact × regular) os valores são
/// exatamente os do protótipo aprovado; o resto é adaptação para contextos
/// que o álbum não define.
@immutable
class CdfLayout {
  const CdfLayout._(this.width, this.height, this.usableHeight);

  final WidthClass width;
  final HeightClass height;

  /// Altura útil em dp (sem as barras do sistema).
  final double usableHeight;

  static const _maxContentWide = 560.0;

  /// A altura útil vem da JANELA (View), não do MediaQuery: dentro de um
  /// SafeArea o MediaQuery já chega com as barras do sistema zeradas, e a
  /// classe mudaria conforme o lugar onde é consultada.
  static CdfLayout of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width; // registra a dependência
    final view = View.of(context);
    final dpr = view.devicePixelRatio;
    final height = view.physicalSize.height / dpr;
    final bars = (view.padding.top + view.padding.bottom) / dpr;
    return from(Size(width, height - bars));
  }

  /// [usable]: tamanho lógico já sem as barras do sistema.
  static CdfLayout from(Size usable) {
    final w = usable.width;
    final wc = w < 380
        ? WidthClass.compact
        : w < 600
            ? WidthClass.standard
            : w < 840
                ? WidthClass.medium
                : WidthClass.expanded;
    final hc = usable.height < 600 ? HeightClass.short : HeightClass.regular;
    return CdfLayout._(wc, hc, usable.height);
  }

  bool get isShort => height == HeightClass.short;
  bool get isNarrow => width == WidthClass.compact;
  bool get isWide => width == WidthClass.medium || width == WidthClass.expanded;

  /// Dois níveis só: o do protótipo e o de tela baixa. Abaixo disso a página
  /// rola um pouco — preferível a apertar o texto e prejudicar a leitura.
  double _h(double regular, double short) => isShort ? short : regular;

  /// Margem lateral: 22 (protótipo), 16 em tela estreita, 32 em tela larga.
  double get hPad => isNarrow ? 16 : isWide ? 32 : 22;

  /// Largura máxima do conteúdo: o app é para celular; em tela larga, uma
  /// coluna central em vez de esticar cartões e o menu.
  double get maxContentWidth => isWide ? _maxContentWide : double.infinity;

  /// Título principal: 28 (protótipo), 26 em tela estreita, 24 em tela baixa.
  double get h1 => isShort ? 24 : isNarrow ? 26 : 28;

  /// Título do login: 34 (protótipo), 28 em tela baixa.
  double get loginTitle => _h(34, 28);

  /// Espaço acima do título do login: 36 (protótipo), 12 em tela baixa.
  double get loginTop => _h(36, 12);

  /// Espaço depois do título/subtítulo da página.
  double get introGap => _h(24, 16);

  /// Espaço entre título e subtítulo da página.
  double get titleGap => _h(8, 6);

  /// Espaço entre o título grande (login) e o subtítulo: 16 no protótipo.
  double get bigTitleGap => _h(16, 12);

  /// Formulários: espaço acima e abaixo do rótulo e respiro do campo.
  double get fieldLabelTop => _h(20, 14);
  double get fieldLabelBottom => 8;
  double get fieldPadding => _h(14, 12);

  /// Espaço acima do botão principal de um formulário.
  double get formButtonTop => _h(16, 12);

  /// Respiro vertical das notas de rodapé de conteúdo.
  double get noteVertical => _h(14, 12);

  /// Respiro final da página (além da altura do menu, quando há menu).
  double get pageBottom => 24;

  /// Espaço acima de um título de seção no fluxo.
  double get sectionGap => _h(24, 16);

  /// Margem inferior de cartão (constante: alinhada ao protótipo).
  double get surfaceGap => 20;

  /// Respiro interno do cartão.
  double get surfacePadding => _h(20, 16);

  /// Cabeçalho da marca: topo e base.
  double get headerTop => _h(16, 8);
  double get headerBottom => isShort ? 10 : isNarrow ? 16 : 22;

  /// Bloco "Última detecção" do início.
  double get presenceIcon => _h(56, 48);
  double get presenceTop => _h(20, 14);
  double get presenceBottom => _h(18, 12);

  @override
  bool operator ==(Object other) =>
      other is CdfLayout && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'CdfLayout(${width.name}, ${height.name})';
}

/// Centraliza e limita a largura do conteúdo em telas largas.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final max = CdfLayout.of(context).maxContentWidth;
    if (max == double.infinity) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child),
    );
  }
}
