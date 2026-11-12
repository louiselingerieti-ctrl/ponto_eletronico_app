import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../demo/demo_backend.dart';
import '../../shared/format/dates_pt.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/widgets/cdf_widgets.dart';
import '../delivery/delivery_widgets.dart';
import '../punch/punch_controller.dart';
import '../punch/punch_models.dart';

/// Pontos registrados (+ Registrar: localização + foto) e detecções
/// automáticas, sempre separados, cada um com o seu estado de envio. Não
/// converte alternância de entrada/saída em jornada.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final b = s.backend;
    final now = b.now();
    final groups = <DateTime, List<DetectionView>>{};
    for (final d in b.detections) {
      groups.putIfAbsent(DatesPt.dateOnly(d.detectedAt), () => []).add(d);
    }
    final punch = s.punch;
    return PageBody(onRefresh: s.refresh, children: [
      const PageIntro('Meu histórico', 'Detecções, registros manuais e envio'),
      if (punch != null) _RealPunches(controller: punch),
      const DemoDataNotice(),
      if (punch == null)
        for (final m in b.manualPunches) _manualRow(m),
      if (groups.isEmpty)
        const Note('Nenhuma detecção registrada ainda.')
      else
        for (final (i, MapEntry(key: day, value: items)) in groups.entries.indexed) ...[
          SectionTitle(DatesPt.relativeDay(day, now), after: i == 0 && b.manualPunches.isEmpty ? SectionAfter.intro : SectionAfter.flow),
          for (final d in items) detectionRow(d),
        ],
      const Note('Os horários exibidos são de detecção pelo aparelho. A avaliação pelo servidor é uma etapa separada.'),
    ]);
  }

  static Widget _manualRow(ManualPunchView m) => EventRow(
        icon: Lucide.hand,
        title: m.title,
        area: '${DatesPt.numeric(m.at)} às ${DatesPt.hm(m.at)} · demonstração\n${m.area} · localização validada + foto, separado da detecção automática',
        time: DatesPt.hm(m.at),
        badge: const StatusBadge('Salvo no aparelho', tone: BadgeTone.pending, small: true, icon: Lucide.cloudOff),
      );
}

/// Modo real: os pontos de hoje que o servidor confirmou.
class _RealPunches extends StatelessWidget {
  const _RealPunches({required this.controller});
  final PunchController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final a = controller.attendance;
        if (a == null) return const SizedBox.shrink();
        final punches = [for (final l in a.links) ...l.punchesToday.where((p) => p.confirmed)]..sort((x, y) => y.recordedAt.compareTo(x.recordedAt));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('Seus pontos de hoje', after: SectionAfter.intro),
          if (punches.isEmpty)
            const Note('Nenhum ponto registrado hoje. Use o + Registrar.')
          else
            for (final p in punches)
              EventRow(
                icon: p.kind == PunchKind.entry ? Lucide.logIn : Lucide.logOut,
                title: '${p.kind.label} registrada',
                area: '${p.mockLocation ? '${p.locationText} · localização simulada' : p.locationText}\nLocalização + foto · separado da detecção automática',
                time: DatesPt.hm(p.recordedAt.toLocal()),
                badge: p.flagged
                    ? const StatusBadge('Recebido · sinalizado para o RH', tone: BadgeTone.pending, small: true, icon: Lucide.circleAlert)
                    : const StatusBadge('Recebido pelo servidor', tone: BadgeTone.ok, small: true, icon: Lucide.check),
              ),
          const SizedBox(height: 12),
        ]);
      },
    );
  }
}
