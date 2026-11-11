import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../shared/format/dates_pt.dart';
import '../../shared/widgets/cdf_widgets.dart';
import 'request_models.dart';
import 'requests_page.dart';

class RequestDetailPage extends StatelessWidget {
  const RequestDetailPage({super.key, required this.displayId});
  final int displayId;

  @override
  Widget build(BuildContext context) {
    final r = AppScope.backendOf(context).byDisplayId(displayId);
    if (r == null) {
      return Scaffold(
        body: PageBody(children: [
          const PageIntro('Solicitação não encontrada', 'Ela não está disponível neste aparelho.'),
          SecondaryButton('Voltar para solicitações', onPressed: () => Navigator.of(context).pop()),
        ]),
      );
    }
    final time = r.time;
    return Scaffold(
      body: PageBody(children: [
        PageIntro('Sua solicitação', '#${r.displayId} • ${DatesPt.numeric(r.date)}'),
        Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            StatusBadge(r.status.label, tone: requestTone(r.status)),
            const SizedBox(height: 18),
            H2(r.category.label),
            Muted(time == null
                ? 'Sem horário informado'
                : 'Horário informado: ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                top: 3),
            const Divider1(),
            BodyText(r.description),
          ]),
        ),
        Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            H2(r.status == RequestStatus.answered ? 'Resposta da empresa' : 'Próxima etapa'),
            BodyText(r.reply, top: 12),
          ]),
        ),
        SecondaryButton('Voltar para solicitações',
            top: 0, onPressed: () => Navigator.of(context).pop()),
      ]),
    );
  }
}
