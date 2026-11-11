import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/shell.dart';
import '../../shared/format/dates_pt.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/layout/cdf_layout.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/cdf_widgets.dart';
import '../delivery/delivery_widgets.dart';
import '../delivery/sync_page.dart';
import '../permissions/permissions_page.dart';
import '../punch/punch_widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final b = AppScope.backendOf(context);
    final c = context.cdf;
    final now = b.now();
    final granted = b.locationGranted;
    final detections = b.detections;
    final last = detections.isEmpty ? null : detections.first;
    final pending = b.pendingCount;
    final l = CdfLayout.of(context);

    final (summary, summaryIcon) = b.offline
        ? ('Sem conexão com a internet', Lucide.wifiOff)
        : pending > 0
            ? ('${pendingText(pending)} aguardando envio', Lucide.cloudUpload)
            : ('Tudo enviado', Lucide.check);

    return PageBody(children: [
      PageIntro('${DatesPt.greeting(now)}, ${AppScope.of(context).firstName}.', DatesPt.longDay(now)),
      // Modo real: o ponto de hoje é do servidor. O restante da tela ainda é demonstração.
      if (AppScope.of(context).punch case final punch?) PunchTodayCard(controller: punch),
      const DemoDataNotice(),
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Sem permissão, nunca anunciar detecção habilitada.
          StatusBadge(granted ? 'Detecção habilitada' : 'Detecção indisponível',
              tone: granted ? BadgeTone.ok : BadgeTone.pending),
          Padding(
            padding: EdgeInsets.only(top: l.presenceTop, bottom: l.presenceBottom),
            child: Row(children: [
              Container(
                width: l.presenceIcon,
                height: l.presenceIcon,
                decoration: BoxDecoration(color: c.orangeSoft, borderRadius: BorderRadius.circular(18)),
                child: Icon(Lucide.mapPin, size: CdfSize.icon, color: c.orange),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  H2(granted ? 'Última detecção' : 'Verifique as permissões', size: 21),
                  Muted(
                    granted
                        ? (last == null
                            ? 'Nenhuma detecção registrada ainda'
                            : '${last.isEntry ? 'Entrada na' : 'Saída da'} ${last.area} às ${DatesPt.hm(last.detectedAt)}')
                        : 'Localização precisa de atenção',
                    top: 3,
                  ),
                ]),
              ),
            ]),
          ),
          BodyText(granted
              ? 'Acompanhe suas detecções e o envio ao servidor.'
              : 'Ative a localização para permitir a detecção nas áreas autorizadas.'),
          const Divider1(),
          Row(children: [
            Expanded(child: Muted(summary)),
            Icon(summaryIcon, size: CdfSize.icon, color: c.ink),
          ]),
          PrimaryButton(
            granted ? 'Ver sincronização' : 'Revisar permissões',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => granted ? const SyncPage() : const PermissionsPage())),
          ),
        ]),
      ),
      SectionTitle('Atividade recente',
          after: SectionAfter.surface,
          action: TextAction('Ver histórico',
              onPressed: () => AppShell.of(context).goTab(AppTab.history))),
      if (last != null) detectionRow(last) else const Note('Nenhuma detecção ainda.'),
      const Note('Uma detecção de presença não confirma a jornada. '
          'Consulte os registros oficiais no portal da empresa.'),
    ]);
  }
}
