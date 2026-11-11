import 'package:flutter/material.dart';

import '../../shared/format/dates_pt.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/cdf_widgets.dart';
import 'punch_controller.dart';
import 'punch_models.dart';

/// Cartão "Seu ponto hoje" da tela inicial (só no modo real): a escala do dia,
/// os pontos já registrados e o botão para registrar o próximo.
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
    final pending = link.pendingAt(controller.nowUtc());
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
        if (confirmed.isEmpty && pending == null)
          const BodyText('Nenhum ponto registrado hoje.', top: 14)
        else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(children: [for (final p in confirmed) _PunchLine(p)]),
          ),
        if (pending != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: StatusBadge('Falta a selfie da ${pending.kind.lower} para o ponto valer', tone: BadgeTone.pending, icon: Lucide.circleAlert),
          ),
        if (!link.hasArea) const Muted('A empresa ainda não cadastrou a área de trabalho: o ponto é registrado, mas sem conferência de local.', top: 10),
        if (link.canPunch)
          PrimaryButton(
            pending != null ? 'Tirar a selfie da ${pending.kind.lower}' : 'Registrar ${link.nextKind.lower}',
            onPressed: () {
              controller.start(link);
              Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => PunchFlowPage(controller: controller)));
            },
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

/// Registro do ponto em duas etapas: 1. localização, 2. selfie.
class PunchFlowPage extends StatelessWidget {
  const PunchFlowPage({super.key, required this.controller});
  final PunchController controller;

  void _close(BuildContext context) {
    controller.closeFlow();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final f = controller.flow;
        return PopScope(
          // Durante o envio não se sai da tela: evita deixar o ponto pela metade sem saber.
          canPop: f == null || (f.step != PunchStep.locating && f.step != PunchStep.confirming),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) controller.closeFlow();
          },
          child: Scaffold(
            appBar: AppBar(title: Text(f == null ? 'Registrar ponto' : 'Registrar ${f.kind.lower}'), centerTitle: false),
            body: SafeArea(child: f == null ? const SizedBox.shrink() : PageBody(children: _content(context, f))),
          ),
        );
      },
    );
  }

  List<Widget> _content(BuildContext context, PunchFlow f) {
    final record = f.record;
    switch (f.step) {
      case PunchStep.locating:
        return const [
          _StepHeader(step: 1, title: 'Localização', active: true),
          Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 12), child: CircularProgressIndicator())),
              BodyText('Lendo a localização do aparelho e registrando no servidor. Se o aparelho perguntar, permita o acesso à localização.'),
            ]),
          ),
          _StepHeader(step: 2, title: 'Selfie', active: false),
        ];

      case PunchStep.failed:
        return [
          const _StepHeader(step: 1, title: 'Localização', active: true),
          Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              StatusBadge((f.failure ?? PunchFailure.server).message, tone: BadgeTone.pending, icon: Lucide.circleAlert),
              const BodyText('Nenhum ponto foi registrado.', top: 10),
              PrimaryButton('Tentar de novo', onPressed: () => controller.start(f.link)),
              SecondaryButton('Voltar', onPressed: () => _close(context)),
            ]),
          ),
        ];

      case PunchStep.located:
      case PunchStep.confirming:
        final busy = f.step == PunchStep.confirming;
        return [
          const _StepHeader(step: 1, title: 'Localização', active: false, done: true),
          Surface(child: _LocationSummary(record: record!, problem: f.locationProblem)),
          const _StepHeader(step: 2, title: 'Selfie', active: true),
          Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const BodyText('Tire uma selfie agora, de frente e em um lugar iluminado. É ela que faz o ponto valer.'),
              const Muted('A foto fica com o registro e pode ser vista por você e pelo RH. O app confere só se há um rosto na foto.', top: 6),
              if (record.faceDeadline != null)
                Muted('Você tem até as ${DatesPt.hm(record.faceDeadline!.toLocal())} para enviar. Depois disso é preciso registrar de novo.', top: 6),
              if (f.selfieProblem != null && f.selfieProblem != SelfieProblem.cancelled)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(liveRegion: true, child: StatusBadge(f.selfieProblem!.message, tone: BadgeTone.pending, icon: Lucide.circleAlert)),
                ),
              if (f.failure != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(liveRegion: true, child: StatusBadge(f.failure!.message, tone: BadgeTone.pending, icon: Lucide.circleAlert)),
                ),
              PrimaryButton(busy ? 'Enviando…' : 'Tirar selfie', onPressed: busy ? null : controller.takeSelfie),
              const Note('Sem a selfie, este registro fica só com a localização e não conta como ponto.'),
            ]),
          ),
        ];

      case PunchStep.expired:
        return [
          Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const StatusBadge('O tempo para a selfie acabou', tone: BadgeTone.pending, icon: Lucide.circleAlert),
              const BodyText('O registro ficou só com a localização e não conta como ponto. Registre de novo: a localização e a selfie precisam ser feitas em seguida.', top: 10),
              PrimaryButton('Registrar de novo', onPressed: () => controller.start(f.link)),
              SecondaryButton('Voltar', onPressed: () => _close(context)),
            ]),
          ),
        ];

      case PunchStep.done:
        return [
          Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              StatusBadge('${f.kind.label} registrada', tone: BadgeTone.ok, icon: Lucide.check),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: H2(record == null ? 'Ponto confirmado' : '${f.kind.label} às ${DatesPt.hm(record.recordedAt.toLocal())}', size: 24),
              ),
              const Muted('Horário oficial do servidor.', top: 4),
              if (record != null) ...[const Divider1(), _LocationSummary(record: record, problem: f.locationProblem)],
              PrimaryButton('Concluir', onPressed: () => _close(context)),
            ]),
          ),
        ];
    }
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.title, required this.active, this.done = false});
  final int step;
  final String title;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    final color = done ? c.success : (active ? c.ink : c.sub);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Semantics(
        header: true,
        label: 'Etapa $step de 2: $title${done ? ', concluída' : ''}',
        child: ExcludeSemantics(
          child: Row(children: [
            Icon(done ? Lucide.check : (step == 1 ? Lucide.mapPin : Lucide.userRound), size: 18, color: color),
            const SizedBox(width: 8),
            Text('$step. $title', style: cdfText(15, weight: 700, color: color)),
          ]),
        ),
      ),
    );
  }
}

/// O que o servidor concluiu sobre o local do ponto, sem mostrar coordenadas.
class _LocationSummary extends StatelessWidget {
  const _LocationSummary({required this.record, this.problem});
  final PunchRecord record;
  final LocationProblem? problem;

  @override
  Widget build(BuildContext context) {
    final ok = record.verdict == LocationVerdict.inside && !record.mockLocation;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StatusBadge(record.locationText, tone: ok ? BadgeTone.ok : BadgeTone.pending, icon: ok ? Lucide.mapPin : Lucide.circleAlert),
      if (problem != null) Muted('${problem!.message} O ponto segue sem a localização e fica sinalizado para o RH.', top: 8),
      if (record.mockLocation) const Muted('O aparelho informou que a localização é simulada. Isso fica registrado.', top: 8),
      if (record.verdict == LocationVerdict.outside) const Muted('O ponto é aceito mesmo fora da área e fica sinalizado para o RH avaliar.', top: 8),
    ]);
  }
}
