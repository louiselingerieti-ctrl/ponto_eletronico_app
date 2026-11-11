import 'package:flutter/material.dart';

import '../features/areas/areas_page.dart';
import '../features/history/history_page.dart';
import '../features/home/home_page.dart';
import '../features/profile/profile_page.dart';
import '../features/requests/requests_page.dart';
import '../shared/icons/lucide.dart';
import '../shared/layout/cdf_layout.dart';
import '../shared/theme/tokens.dart';
import 'app_services.dart';

enum AppTab { home, history, requests, areas, profile }

/// Estrutura principal: cabeçalho fixo, cinco áreas com navegação própria
/// (estado preservado) e menu inferior obrigatório.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static AppShellState of(BuildContext context) =>
      context.findAncestorStateOfType<AppShellState>()!;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  AppTab _tab = AppTab.home;
  AppTab get tab => _tab;

  final _keys = {for (final t in AppTab.values) t: GlobalKey<NavigatorState>()};
  late final _observers = {for (final t in AppTab.values) t: _StackObserver(_onStackChanged)};
  bool _nestedCanPop = false;

  void _onStackChanged() {
    final can = _keys[_tab]?.currentState?.canPop() ?? false;
    if (can != _nestedCanPop && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _nestedCanPop = can);
      });
    }
  }

  /// Toque no menu. Tocar na área já aberta volta ao início dela.
  void goTab(AppTab t) {
    final nav = _keys[t]!.currentState;
    if (t == _tab && nav != null && nav.canPop()) {
      nav.popUntil((r) => r.isFirst);
    }
    setState(() {
      _tab = t;
      _nestedCanPop = _keys[t]!.currentState?.canPop() ?? false;
    });
  }

  /// "Voltar ao início": fecha o que estiver aberto na área atual e vai para
  /// a primeira área.
  void backToHome() {
    _keys[_tab]!.currentState?.popUntil((r) => r.isFirst);
    goTab(AppTab.home);
  }

  static Widget _root(AppTab t) => switch (t) {
        AppTab.home => const HomePage(),
        AppTab.history => const HistoryPage(),
        AppTab.requests => const RequestsPage(),
        AppTab.areas => const AreasPage(),
        AppTab.profile => const ProfilePage(),
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Voltar do Android fecha detalhe/formulário antes de sair da área.
      canPop: !_nestedCanPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _keys[_tab]!.currentState?.maybePop();
      },
      child: Scaffold(
        // O conteúdo rola por baixo da faixa transparente onde o círculo
        // central sobe; PageBody compensa com o respiro inferior.
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            BrandHeader(onAvatar: () => goTab(AppTab.profile)),
            Expanded(
              child: IndexedStack(
                index: _tab.index,
                children: [
                  for (final t in AppTab.values)
                    // Áreas fora de foco saem da árvore de acessibilidade.
                    ExcludeSemantics(
                      excluding: t != _tab,
                      // Contêiner próprio: a barreira das rotas aninhadas
                      // (BlockSemantics) não pode apagar o cabeçalho.
                      child: Semantics(
                        container: true,
                        explicitChildNodes: true,
                        child: Navigator(
                          key: _keys[t],
                          observers: [_observers[t]!],
                          onGenerateRoute: (_) =>
                              MaterialPageRoute<void>(builder: (_) => _root(t)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        ),
        bottomNavigationBar: CdfBottomNav(current: _tab, onSelect: goTab),
      ),
    );
  }
}

class _StackObserver extends NavigatorObserver {
  _StackObserver(this.onChange);
  final VoidCallback onChange;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => onChange();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => onChange();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => onChange();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => onChange();
}

/// Marca + avatar (abre o perfil). Sem relógio/bateria: a barra é a do sistema.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.onAvatar});
  final VoidCallback? onAvatar;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    final l = CdfLayout.of(context);
    final initials = onAvatar == null ? null : AppScope.of(context).initials;
    return Padding(
      padding: EdgeInsets.fromLTRB(l.hPad, l.headerTop, l.hPad, l.headerBottom),
      child: ContentWidth(child: Row(children: [
        Semantics(
          label: 'Casa do Futuro',
          image: true,
          child: ClipOval(
            child: Image.asset('assets/brand/logo.png', width: 38, height: 38, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ExcludeSemantics(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Casa do Futuro', style: cdfText(14, weight: 700, color: c.ink)),
              const SizedBox(height: 3),
              Text('Meu espaço', style: cdfText(12, color: c.sub)),
            ]),
          ),
        ),
        if (initials != null)
          Semantics(
            button: true,
            label: 'Abrir perfil',
            excludeSemantics: true,
            // Círculo visual de 40 (protótipo) numa área de toque de 48.
            child: InkResponse(
              onTap: onAvatar,
              radius: 24,
              child: SizedBox(
                width: CdfSize.minTouch,
                height: CdfSize.minTouch,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: c.orangeSoft, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(initials, style: cdfText(12, weight: 700, color: c.ink)),
                  ),
                ),
              ),
            ),
          ),
      ])),
    );
  }
}

/// Menu inferior: Início, Histórico, + Solicitar, Áreas, Perfil.
/// O círculo laranja (52, contorno 4 na cor da superfície) sobe ~24 acima
/// dos outros ícones; o rótulo "Solicitar" fica na mesma linha dos demais.
class CdfBottomNav extends StatelessWidget {
  const CdfBottomNav({super.key, required this.current, required this.onSelect});
  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  static const _overhang = 24.0;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    // Altura acompanha a escala de texto do sistema (mínimo 50, protótipo).
    final labelLine = MediaQuery.textScalerOf(context).scale(16);
    final itemHeight = (8 + CdfSize.icon + 5 + labelLine + 1).clamp(50.0, double.infinity);
    Widget item(AppTab t, IconData icon, String label) => Expanded(
          child: _NavItem(
            icon: icon,
            label: label,
            selected: current == t,
            center: t == AppTab.requests,
            onTap: () => onSelect(t),
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(clipBehavior: Clip.none, children: [
        Container(
          margin: const EdgeInsets.only(top: _overhang),
          decoration: BoxDecoration(
            color: c.paper,
            border: Border(top: BorderSide(color: c.line)),
          ),
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
          // Em tela larga, os cinco itens ficam na coluna central (não se
          // espalham pela largura toda); o fundo da barra ocupa tudo.
          child: ContentWidth(
            child: SizedBox(
              height: itemHeight,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                item(AppTab.home, Lucide.house, 'Início'),
                item(AppTab.history, Lucide.listChecks, 'Histórico'),
                item(AppTab.requests, Lucide.plus, 'Solicitar'),
                item(AppTab.areas, Lucide.mapPin, 'Áreas'),
                item(AppTab.profile, Lucide.userRound, 'Perfil'),
              ]),
            ),
          ),
        ),
        // Círculo central na pilha externa: a parte que sobe acima da barra
        // também recebe toque. Fundo do círculo 6 acima do rótulo.
        Positioned(
          top: _overhang + 10 + itemHeight - 8 - labelLine - 6 - 52,
          left: 0,
          right: 0,
          child: Center(
            child: ExcludeSemantics(
              child: GestureDetector(
                onTap: () => onSelect(AppTab.requests),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: c.orange,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.paper, width: 4),
                    boxShadow: const [
                      BoxShadow(color: Color(0x2E000000), blurRadius: 12, offset: Offset(0, 4)),
                    ],
                  ),
                  alignment: Alignment.center,
                  // Ícone de 24, cor do texto sobre laranja, igual no estado ativo.
                  child: Icon(Lucide.plus, size: 24, color: c.onOrange),
                ),
              ),
            ),
          ),
        ),
      ]),
      const DemoFooter(),
    ]);
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.center,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final bool center;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    // O rótulo "Solicitar" é sempre na cor do texto (protótipo); os demais
    // ficam em cinza quando não selecionados.
    final labelStyle = cdfText(11,
        weight: selected ? 700 : 400,
        color: selected || center ? c.ink : c.sub,
        height: 16 / 11);
    final text = Text(label, style: labelStyle, maxLines: 1, overflow: TextOverflow.visible, softWrap: false);

    // Rótulo sempre no mesmo lugar (8 do fundo, linha de 16). O círculo do
    // item central é desenhado pela barra (CdfBottomNav).
    Widget content;
    if (center) {
      content = Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Align(alignment: Alignment.bottomCenter, child: text),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          Icon(icon, size: CdfSize.icon, color: selected ? c.orange : c.sub),
          const SizedBox(height: 5),
          text,
        ]),
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        // Área de toque inclui o círculo que sobe acima da barra.
        child: SizedBox.expand(child: content),
      ),
    );
  }
}

class DemoFooter extends StatelessWidget {
  const DemoFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Container(
      width: double.infinity,
      color: c.paper,
      child: SafeArea(
        top: false,
        child: Padding(
          // Em tela baixa fica mais fino, mas não some: identifica os dados
          // fictícios.
          padding: EdgeInsets.all(CdfLayout.of(context).isShort ? 4 : 9),
          child: Text(AppScope.of(context).realMode
                  ? 'Conta real • detecções e pedidos em demonstração'
                  : 'Demonstração • dados fictícios',
              textAlign: TextAlign.center, style: cdfText(11, color: c.sub)),
        ),
      ),
    );
  }
}
