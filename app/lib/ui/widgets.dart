import 'package:flutter/material.dart';

import 'tokens.dart';

/// Faixa permanente do laboratório. Fica fora da área de rolagem: nunca some.
class HazardBand extends StatelessWidget {
  const HazardBand({super.key});

  static const text = 'Laboratório simulado — não gera ponto oficial';

  @override
  Widget build(BuildContext context) {
    final c = context.lab;
    return Semantics(
      container: true,
      label: text,
      child: CustomPaint(
        painter: _StripesPainter(c.amber, c.amberInk),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.amber, borderRadius: BorderRadius.circular(6)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: ExcludeSemantics(
                  child: Text(text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: c.amberInk, fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StripesPainter extends CustomPainter {
  _StripesPainter(this.a, this.b);
  final Color a, b;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = a);
    final p = Paint()..color = b;
    const w = 14.0;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (double x = -size.height; x < size.width + size.height; x += w * 2) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + w, size.height)
        ..lineTo(x + w + size.height, 0)
        ..lineTo(x + size.height, 0)
        ..close();
      canvas.drawPath(path, p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripesPainter old) => old.a != a || old.b != b;
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.title, required this.children, this.trailing});
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LabSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              ?trailing,
            ],
          ),
          for (final w in children) ...[const SizedBox(height: 14), w],
        ],
      ),
    );
  }
}

/// Superfície com borda. É um `Material` (não um fundo pintado) para que o
/// efeito de toque de ListTile/RadioListTile/ExpansionTile apareça.
class LabSurface extends StatelessWidget {
  const LabSurface({super.key, required this.child, required this.padding});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.lab;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class Note extends StatelessWidget {
  const Note(this.text, {super.key});
  final InlineSpan text;

  factory Note.plain(String s) => Note(TextSpan(text: s));

  @override
  Widget build(BuildContext context) {
    final c = context.lab;
    return Container(
      decoration: BoxDecoration(color: c.noteBg, borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text.rich(text, style: TextStyle(fontSize: 13, color: c.ink2, height: 1.45)),
    );
  }
}

class FictitiousTag extends StatelessWidget {
  const FictitiousTag([this.label = 'fictício', Key? key]) : super(key: key);
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.lab;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
          border: Border.all(color: c.line), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 12, color: c.ink2)),
    );
  }
}

class Chip2 extends StatelessWidget {
  const Chip2(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.lab;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.lineStrong),
      ),
      child: Text(label, style: TextStyle(fontSize: 13, color: c.ink2)),
    );
  }
}

/// Linha "rótulo: valor" de uma lista de dados.
class DataRow2 extends StatelessWidget {
  const DataRow2(this.label, this.value, {super.key, this.tag});
  final String label;
  final Widget value;
  final Widget? tag;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: TextStyle(fontSize: 14, color: context.lab.ink2)),
          ),
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center,
                children: [DefaultTextStyle.merge(style: const TextStyle(fontSize: 14), child: value), ?tag]),
          ),
        ],
      ),
    );
  }
}

enum StepTone { none, saved, sent, received, evaluated, failure, inProgress }

class StepCell {
  const StepCell(this.title, this.detail, this.tone);
  final String title;
  final String detail;
  final StepTone tone;
}

/// Trilho de etapas (segmentos com borda superior colorida).
class StepTrack extends StatelessWidget {
  const StepTrack(this.cells, {super.key, this.semanticsLabel});
  final List<StepCell> cells;
  final String? semanticsLabel;

  Color _color(LabColors c, StepTone t) => switch (t) {
        StepTone.none => c.line,
        StepTone.saved => c.saved,
        StepTone.sent || StepTone.inProgress => c.sent,
        StepTone.received => c.received,
        StepTone.evaluated => c.evaluated,
        StepTone.failure => c.failure,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.lab;
    final dur = context.reduceMotion ? LabMotion.reduzido : LabMotion.medio;
    return Semantics(
      label: semanticsLabel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, cell) in cells.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: dur,
                    height: 5,
                    decoration: BoxDecoration(
                      color: cell.tone == StepTone.inProgress
                          ? _color(c, cell.tone).withValues(alpha: .45)
                          : _color(c, cell.tone),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(cell.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cell.tone == StepTone.failure
                            ? c.failure
                            : cell.tone == StepTone.none
                                ? c.ink2
                                : c.ink,
                      )),
                  Text(cell.detail,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: cell.tone == StepTone.failure ? c.failure : c.ink2)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Entrada de elemento novo: sobe 8px + opacidade (motion-ll); com movimento
/// reduzido, só opacidade.
class EnterOnce extends StatelessWidget {
  const EnterOnce({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduce ? LabMotion.reduzido : LabMotion.medio,
      curve: reduce ? Curves.ease : LabMotion.saida,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: reduce ? child : Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
