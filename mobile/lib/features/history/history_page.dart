import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../demo/demo_backend.dart';
import '../../shared/format/dates_pt.dart';
import '../../shared/widgets/cdf_widgets.dart';
import '../delivery/delivery_widgets.dart';

/// Detecções agrupadas por dia, com o estado de ENTREGA. Não converte
/// alternância de entrada/saída em jornada.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final b = AppScope.backendOf(context);
    final now = b.now();
    final groups = <DateTime, List<DetectionView>>{};
    for (final d in b.detections) {
      groups.putIfAbsent(DatesPt.dateOnly(d.detectedAt), () => []).add(d);
    }
    return PageBody(onRefresh: AppScope.of(context).refresh, children: [
      const PageIntro('Meu histórico', 'Detecções e situação de envio'),
      const DemoDataNotice(),
      if (groups.isEmpty)
        const Note('Nenhuma detecção registrada ainda.')
      else
        for (final (i, MapEntry(key: day, value: items)) in groups.entries.indexed) ...[
          SectionTitle(DatesPt.relativeDay(day, now),
              after: i == 0 ? SectionAfter.intro : SectionAfter.flow),
          for (final d in items) detectionRow(d),
        ],
      const Note('Os horários exibidos são de detecção pelo aparelho. '
          'A avaliação pelo servidor é uma etapa separada.'),
    ]);
  }
}
