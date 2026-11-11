import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../shared/format/dates_pt.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/cdf_widgets.dart';
import 'new_request_page.dart';
import 'request_detail_page.dart';
import 'request_models.dart';

/// Centro de solicitações (botão central "+ Solicitar").
class RequestsPage extends StatelessWidget {
  const RequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.backendOf(context);
    final items = repo.list();
    return PageBody(children: [
      const PageIntro('Minhas solicitações', 'Relate um problema e acompanhe a resposta.'),
      const DemoDataNotice(),
      PrimaryButton('Nova solicitação',
          top: 0,
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const NewRequestPage()))),
      const SizedBox(height: 20),
      const H2('Acompanhamento'),
      if (items.isEmpty)
        const _EmptyRequests()
      else
        for (final r in items) _RequestCard(r),
      const Note('Uma solicitação não altera automaticamente seus registros. '
          'A empresa precisa analisar o caso.'),
    ]);
  }
}

BadgeTone requestTone(RequestStatus s) =>
    s == RequestStatus.answered ? BadgeTone.ok : BadgeTone.pending;

class _RequestCard extends StatelessWidget {
  const _RequestCard(this.r);
  final EmployeeRequest r;

  @override
  Widget build(BuildContext context) => Surface(
        margin: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Muted('${DatesPt.numeric(r.date)} • #${r.displayId}'),
          const SizedBox(height: 12),
          H2(r.category.label),
          const SizedBox(height: 12),
          StatusBadge(r.status.label, tone: requestTone(r.status)),
          TextAction('Ver solicitação e resposta',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => RequestDetailPage(displayId: r.displayId)))),
        ]),
      );
}

class _EmptyRequests extends StatelessWidget {
  const _EmptyRequests();

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        Icon(Lucide.inbox, size: 40, color: c.sub),
        const SizedBox(height: 18),
        Text('Nenhuma solicitação ainda', style: cdfText(14, weight: 650, color: c.ink)),
        const SizedBox(height: 6),
        Text('Use Nova solicitação para relatar um problema na detecção '
            'ou justificar uma ausência.',
            textAlign: TextAlign.center, style: cdfText(12, color: c.sub, height: 1.5)),
      ]),
    );
  }
}
