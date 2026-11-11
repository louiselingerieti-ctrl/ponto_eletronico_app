import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/shell.dart';
import '../../shared/format/dates_pt.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/widgets/cdf_widgets.dart';
import 'delivery_widgets.dart';

/// Conexão (simulada) separada do estado da fila. "Recebido" só com ACK.
class SyncPage extends StatelessWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    final b = AppScope.backendOf(context);
    final pending = b.pendingCount;
    final ack = b.lastAck;
    final now = b.now();
    final String badge;
    final bool ok;
    if (b.offline) {
      (badge, ok) = ('Sem internet', false);
    } else if (pending > 0) {
      (badge, ok) = ('${pendingText(pending)} ${pending == 1 ? 'pendente' : 'pendentes'}', false);
    } else {
      (badge, ok) = ('Tudo enviado', true);
    }

    return Scaffold(
      body: PageBody(children: [
        const PageIntro('Sincronização', 'Seus eventos, com transparência'),
        Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            StatusBadge(badge, tone: ok ? BadgeTone.ok : BadgeTone.pending,
                icon: b.offline ? Lucide.cloudOff : null),
            const Divider1(),
            BodyText(pending > 0
                ? (pending == 1
                    ? 'O evento está salvo no aparelho. Ele será reenviado quando houver conexão disponível.'
                    : 'Os eventos estão salvos no aparelho. Eles serão reenviados quando houver conexão disponível.')
                : 'O servidor confirmou o recebimento dos eventos desta demonstração.'),
            if (ack != null)
              Muted('Última confirmação do servidor: ${DatesPt.relativeDay(ack, now).split(',').first.toLowerCase()} às ${DatesPt.hm(ack)}',
                  top: 10),
            PrimaryButton(
              b.sending ? 'Enviando…' : (pending > 0 ? 'Simular envio agora' : 'Conferir novamente'),
              onPressed: b.offline || b.sending ? null : b.sendNow,
            ),
          ]),
        ),
        SecondaryButton(
          b.offline ? 'Simular conexão disponível' : 'Simular modo offline',
          top: 0,
          onPressed: () => b.setOffline(!b.offline),
        ),
        const Note('Recebido significa confirmação de entrega. '
            'Não significa que o evento foi convertido em ponto oficial.'),
        TextAction('Voltar ao início', onPressed: () => AppShell.of(context).backToHome()),
      ]),
    );
  }
}
