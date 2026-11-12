import 'package:flutter/material.dart';

import '../../app/shell.dart';
import '../../shared/format/dates_pt.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/cdf_widgets.dart';
import 'punch_controller.dart';
import 'punch_models.dart';

/// Cartão "Seu ponto hoje" da tela inicial (só no modo real): a escala do dia,
/// os pontos já registrados e o atalho para o + Registrar.
class PunchTodayCard extends StatelessWidget {
  const PunchTodayCard({super.key, required this.controller});
  final PunchController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final a = controller.attendance;
        if (a == null) {
          return Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const H2('Seu ponto hoje', size: 21),
              if (controller.loading)
                const Muted('Buscando sua jornada de hoje…', top: 6)
              else ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: StatusBadge((controller.error ?? PunchFailure.server).message, tone: BadgeTone.pending, icon: Lucide.circleAlert),
                ),
                SecondaryButton('Tentar de novo', onPressed: controller.refresh),
              ],
            ]),
          );
        }
        if (a.links.isEmpty) {
          return const Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              H2('Seu ponto hoje', size: 21),
              BodyText('Sua conta ainda não está ligada a um vínculo ativo, então não há ponto para registrar. Procure o RH.', top: 6),
            ]),
          );
        }
        return Column(children: [
          for (final link in a.links) _LinkCard(controller: controller, link: link, showCompany: a.links.length > 1),
          _RemindersRow(controller: controller),
        ]);
      },
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.controller, required this.link, required this.showCompany});
  final PunchController controller;
  final LinkAttendance link;
  final bool showCompany;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    final today = link.today;
    final confirmed = link.punchesToday.where((p) => p.confirmed).toList();
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.orangeSoft, borderRadius: BorderRadius.circular(16)),
            child: Icon(Lucide.clock, size: CdfSize.icon, color: c.orange),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              H2(showCompany ? link.companyName : 'Seu ponto hoje', size: 21),
              Muted(today == null ? 'Sem escala definida' : 'Escala de hoje: ${today.summary}', top: 3),
            ]),
          ),
        ]),
        if (confirmed.isEmpty)
          const BodyText('Nenhum ponto registrado hoje.', top: 14)
        else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(children: [for (final p in confirmed) _PunchLine(p)]),
          ),
        if (!link.hasArea)
          const Muted('A empresa ainda não cadastrou a área de trabalho. Sem ela não é possível validar o local nem registrar o ponto. Procure o RH.', top: 10),
        if (link.canPunch)
          PrimaryButton(
            'Registrar ponto',
            onPressed: () => AppShell.of(context).goTab(AppTab.register),
          )
        else
          const Muted('A empresa está desativada no sistema. Procure o RH.', top: 10),
      ]),
    );
  }
}

class _PunchLine extends StatelessWidget {
  const _PunchLine(this.punch);
  final PunchRecord punch;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(punch.flagged ? Lucide.circleAlert : Lucide.check, size: 18, color: punch.flagged ? c.warn : c.success),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${punch.kind.label} às ${DatesPt.hm(punch.recordedAt.toLocal())}', style: cdfText(15, weight: 650, color: c.ink)),
            Text(punch.mockLocation ? '${punch.locationText} · localização simulada' : punch.locationText, style: cdfText(13, color: c.sub)),
          ]),
        ),
      ]),
    );
  }
}

/// Avisos no horário da escala: o celular vibra e mostra a mensagem.
class _RemindersRow extends StatelessWidget {
  const _RemindersRow({required this.controller});
  final PunchController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.remindersOn) {
      final n = controller.scheduledReminders;
      return Note(n == 0
          ? 'Avisos no horário da escala: ativados. Não há horário de escala nos próximos dias.'
          : 'Avisos no horário da escala: ativados. O celular vibra e avisa na hora de registrar ($n ${n == 1 ? 'aviso agendado' : 'avisos agendados'}).');
    }
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const H2('Avisos no horário'),
        const BodyText('O celular pode vibrar e avisar no horário de entrada e de saída da sua escala. O aviso só lembra: quem registra o ponto é você.', top: 4),
        SecondaryButton('Ativar avisos', onPressed: controller.enableReminders),
      ]),
    );
  }
}
