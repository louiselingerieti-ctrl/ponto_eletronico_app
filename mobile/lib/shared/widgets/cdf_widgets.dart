import 'package:flutter/material.dart';

import '../icons/lucide.dart';
import '../layout/cdf_layout.dart';
import '../theme/tokens.dart';

/// Título e subtítulo de página (h1 28/26 + texto 14).
class PageIntro extends StatelessWidget {
  const PageIntro(this.title, this.subtitle, {super.key, this.big = false});
  final String title;
  final String subtitle;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    final l = CdfLayout.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: l.introGap),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          header: true,
          child: Text(title,
              style: cdfText(big ? l.loginTitle : l.h1,
                  weight: 650, color: c.ink, height: 1.2, spacing: -.8)),
        ),
        SizedBox(height: big ? l.bigTitleGap : l.titleGap),
        Text(subtitle, style: cdfText(14, color: c.sub, height: 1.5)),
      ]),
    );
  }
}

/// Rolagem de página com as margens do protótipo.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.onRefresh});
  final List<Widget> children;

  /// "Puxar para atualizar": com isto, puxar a página para baixo no topo
  /// chama [onRefresh], que devolve o aviso a mostrar se não deu certo
  /// (null = atualizou). Funciona mesmo quando o conteúdo cabe na tela.
  final Future<String?> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = CdfLayout.of(context);
    final h = l.hPad;
    // Com o menu sobreposto (extendBody), o Scaffold informa a altura dele
    // como padding inferior: o fim do conteúdo nunca fica escondido.
    final bottom = l.pageBottom + MediaQuery.paddingOf(context).bottom;
    final refresh = onRefresh;
    final scroll = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(h, 0, h, bottom),
      physics: refresh == null ? null : const AlwaysScrollableScrollPhysics(),
      // Com o teclado aberto, o campo em foco é rolado para a vista.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      child: ContentWidth(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
    if (refresh == null) return scroll;
    final c = context.cdf;
    return RefreshIndicator(
      color: c.orange,
      backgroundColor: c.paper,
      onRefresh: () async {
        final problem = await refresh();
        if (problem == null || !context.mounted) return;
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(problem)));
      },
      child: scroll,
    );
  }
}

class Surface extends StatelessWidget {
  const Surface({super.key, required this.child, this.margin = const EdgeInsets.only(bottom: 20)});
  final Widget child;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: Material(
          color: context.cdf.paper,
          borderRadius: BorderRadius.circular(CdfSize.radiusSurface),
          child: Padding(
              padding: EdgeInsets.all(CdfLayout.of(context).surfacePadding), child: child),
        ),
      );
}

class H2 extends StatelessWidget {
  const H2(this.text, {super.key, this.size = 16});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(text,
            style: cdfText(size, weight: 650, color: context.cdf.ink,
                spacing: size > 16 ? -.4 : null, height: 1.25)),
      );
}

class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.top = 0});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top),
        child: Text(text, style: cdfText(12, color: context.cdf.sub, height: 1.4)),
      );
}

class BodyText extends StatelessWidget {
  const BodyText(this.text, {super.key, this.top = 0});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top),
        child: Text(text, style: cdfText(14, color: context.cdf.sub, height: 1.5)),
      );
}

class Note extends StatelessWidget {
  const Note(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: CdfLayout.of(context).noteVertical),
        child: Text(text, style: cdfText(12, color: context.cdf.sub, height: 1.5)),
      );
}

/// Decoração de campo com o respiro do contexto (14 no protótipo).
InputDecoration cdfInput(BuildContext context, {String? hint}) => InputDecoration(
      hintText: hint,
      contentPadding: EdgeInsets.all(CdfLayout.of(context).fieldPadding),
    );

class Divider1 extends StatelessWidget {
  const Divider1({super.key, this.vertical = 16});
  final double vertical;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: vertical),
        child: Container(height: 1, color: context.cdf.line),
      );
}

enum BadgeTone { ok, pending }

/// Selo de estado: sempre com texto e ícone (não depende só de cor).
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.text, {super.key, required this.tone, this.small = false, this.icon, this.alignment = Alignment.centerLeft});
  final String text;
  final Alignment alignment;
  final BadgeTone tone;
  final bool small;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    final ok = tone == BadgeTone.ok;
    final fg = ok ? c.success : c.warn;
    return Align(
      alignment: alignment,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: ok ? c.successBg : c.orangeSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon ?? (ok ? Lucide.check : Lucide.cloudOff), size: 14, color: fg),
          const SizedBox(width: 7),
          Flexible(child: Text(text, style: cdfText(small ? 11 : 12, weight: 600, color: fg))),
        ]),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.label, {super.key, required this.onPressed, this.top = 16});
  final String label;
  final VoidCallback? onPressed;
  final double top;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: c.orange,
            foregroundColor: c.onOrange,
            disabledBackgroundColor: c.orange.withValues(alpha: .5),
            disabledForegroundColor: c.onOrange.withValues(alpha: .5),
            minimumSize: const Size.fromHeight(CdfSize.minTouch),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CdfSize.radiusButton)),
            textStyle: cdfText(14, weight: 650),
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton(this.label, {super.key, required this.onPressed, this.top = 16});
  final String label;
  final VoidCallback? onPressed;
  final double top;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: c.paper,
            foregroundColor: c.ink,
            side: BorderSide(color: c.line),
            minimumSize: const Size.fromHeight(CdfSize.minTouch),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CdfSize.radiusButton)),
            textStyle: cdfText(14, weight: 650),
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// Ação de texto sublinhada. Área de toque mínima de 48 (o protótipo usa 40).
class TextAction extends StatelessWidget {
  const TextAction(this.label, {super.key, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: c.ink,
          minimumSize: const Size(CdfSize.minTouch, CdfSize.minTouch),
          padding: const EdgeInsets.symmetric(vertical: 8),
          tapTargetSize: MaterialTapTargetSize.padded,
          alignment: Alignment.centerLeft,
        ),
        child: Text(label,
            style: cdfText(12, color: c.ink, decoration: TextDecoration.underline)),
      ),
    );
  }
}

/// Título de seção com ação opcional à direita.
/// O que vem logo antes do título de seção. No protótipo (CSS) as margens
/// verticais se sobrepõem em vez de somar; aqui o espaço é o complemento.
enum SectionAfter { flow, surface, intro }

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.after = SectionAfter.flow});
  final String title;
  final Widget? action;
  final SectionAfter after;

  @override
  Widget build(BuildContext context) {
    final l = CdfLayout.of(context);
    final top = switch (after) {
      SectionAfter.flow => l.sectionGap,
      SectionAfter.surface => (l.sectionGap - l.surfaceGap).clamp(0.0, double.infinity),
      SectionAfter.intro => (l.sectionGap - l.introGap).clamp(0.0, double.infinity),
    };
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: action == null ? 14 : 4),
      child: Row(children: [Expanded(child: H2(title)), ?action]),
    );
  }
}

/// Linha de evento de detecção (ícone, título, área, horário e selo).
class EventRow extends StatelessWidget {
  const EventRow({
    super.key,
    required this.icon,
    required this.title,
    required this.area,
    required this.time,
    required this.badge,
  });
  final IconData icon;
  final String title;
  final String area;
  final String time;
  final StatusBadge badge;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: CdfSize.icon, color: c.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title, style: cdfText(14, weight: 600, color: c.ink))),
                const SizedBox(width: 12),
                Text(time, style: cdfText(12, color: c.sub)),
              ]),
              const SizedBox(height: 3),
              Text(area, style: cdfText(12, color: c.sub)),
              const SizedBox(height: 8),
              badge,
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Linha de configuração do perfil/permissões.
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.icon, required this.title, required this.subtitle, this.action});
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 17),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: CdfSize.icon, color: c.ink),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: cdfText(14, weight: 650, color: c.ink)),
            const SizedBox(height: 3),
            Text(subtitle, style: cdfText(12, color: c.sub, height: 1.4)),
            ?action,
          ]),
        ),
      ]),
    );
  }
}

/// Rótulo de campo de formulário (13, margem 20/8).
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final l = CdfLayout.of(context);
    return Padding(
      padding: EdgeInsets.only(top: l.fieldLabelTop, bottom: l.fieldLabelBottom),
      child: Text(text, style: cdfText(13, color: context.cdf.ink)),
    );
  }
}

/// Com conta REAL, marca as telas cujos dados ainda são fictícios (as rotas
/// de presença e solicitações não existem no backend). Nada some sem aviso.
class DemoDataNotice extends StatelessWidget {
  const DemoDataNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DemoNoticeScope>();
    if (scope == null || !scope.realMode) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: StatusBadge('Demonstração: dados fictícios nesta tela',
          tone: BadgeTone.pending, icon: Lucide.circleAlert),
    );
  }
}

/// Informa aos componentes se a conta é real (sem acoplar widgets
/// compartilhados aos serviços do app).
class DemoNoticeScope extends InheritedWidget {
  const DemoNoticeScope({super.key, required this.realMode, required super.child});
  final bool realMode;
  @override
  bool updateShouldNotify(DemoNoticeScope old) => old.realMode != realMode;
}

/// Diálogo de confirmação simples.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  required String cancel,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: cdfText(18, weight: 650, color: ctx.cdf.ink)),
      content: Text(message, style: cdfText(14, color: ctx.cdf.sub, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancel)),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirm)),
      ],
    ),
  );
  return r ?? false;
}
