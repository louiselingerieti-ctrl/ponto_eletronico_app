import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/shell.dart';
import '../../demo/demo_backend.dart';
import '../../shared/format/dates_pt.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/layout/cdf_layout.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/cdf_widgets.dart';
import '../delivery/delivery_widgets.dart';
import '../delivery/sync_page.dart';
import '../permissions/permissions_page.dart';
import '../punch/punch_controller.dart';
import '../punch/punch_widgets.dart';

/// Início: saudação, ponto de hoje (modo real), Minha área, envio e
/// atividade recente. A localização mostrada aqui é a da ÚLTIMA detecção (ou
/// a área cadastrada); ela nunca substitui a validação atual do + Registrar.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final b = s.backend;
    final now = b.now();
    final detections = b.detections;
    final last = detections.isEmpty ? null : detections.first;
    final punch = s.punch;

    return PageBody(onRefresh: s.refresh, children: [
      PageIntro('${DatesPt.greeting(now)}, ${s.firstName}.', DatesPt.longDay(now)),
      // Modo real: o ponto de hoje e as áreas são do servidor.
      if (punch != null) ...[
        PunchTodayCard(controller: punch),
        _RealAreaCard(controller: punch),
      ],
      const DemoDataNotice(),
      if (punch == null) _DemoAreaCard(backend: b, last: last),
      _DeliveryRow(backend: b),
      SectionTitle('Atividade recente',
          after: SectionAfter.surface,
          action: TextAction('Ver histórico', onPressed: () => AppShell.of(context).goTab(AppTab.history))),
      if (last != null) detectionRow(last) else const Note('Nenhuma detecção ainda.'),
      const Note('A detecção de área é uma evidência de presença. Ela não confirma automaticamente sua jornada.'),
    ]);
  }
}

/// Cabeçalho "Minha área" + "Ver todas".
class _AreaHeader extends StatelessWidget {
  const _AreaHeader();

  @override
  Widget build(BuildContext context) => Row(children: [
        const Expanded(child: H2('Minha área')),
        TextAction('Ver todas', onPressed: () => AppShell.of(context).openAreas()),
      ]);
}

class _AreaTitle extends StatelessWidget {
  const _AreaTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    final l = CdfLayout.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 10, bottom: l.presenceBottom),
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
            H2(title, size: 21),
            Muted(subtitle, top: 3),
          ]),
        ),
      ]),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Icon(icon, size: 16, color: c.sub),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: cdfText(13, color: c.sub))),
      ]),
    );
  }
}

/// "Consultar minhas áreas autorizadas ›".
class _AreasLink extends StatelessWidget {
  const _AreasLink();

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Semantics(
      button: true,
      label: 'Consultar minhas áreas autorizadas',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => AppShell.of(context).openAreas(),
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: CdfSize.minTouch),
          child: Row(children: [
            Expanded(child: Text('Consultar minhas áreas autorizadas', style: cdfText(14, weight: 500, color: c.ink))),
            Icon(Lucide.chevronRight, size: CdfSize.icon, color: c.ink),
          ]),
        ),
      ),
    );
  }
}

/// Modo real: as áreas que o servidor autorizou ao vínculo. Sem coordenadas.
class _RealAreaCard extends StatelessWidget {
  const _RealAreaCard({required this.controller});
  final PunchController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final a = controller.attendance;
        if (a == null) return const SizedBox.shrink();
        final pairs = [for (final l in a.links) for (final w in l.areas) (l, w)];
        final first = pairs.isEmpty ? null : pairs.first;
        final company = first?.$1.companyName ?? (a.links.isEmpty ? AppScope.of(context).companyName : a.links.first.companyName);
        return Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const _AreaHeader(),
            _AreaTitle(title: first?.$2.name ?? 'Área não cadastrada', subtitle: company),
            if (first != null)
              const StatusBadge('Cadastrada pela empresa', tone: BadgeTone.ok, icon: Lucide.check)
            else
              const StatusBadge('Sem área para validar o ponto', tone: BadgeTone.pending, icon: Lucide.circleAlert),
            if (pairs.length > 1) Muted('E mais ${pairs.length - 1} ${pairs.length == 2 ? 'área autorizada' : 'áreas autorizadas'}.', top: 10),
            BodyText(
              first != null
                  ? 'Sua posição é conferida na hora de registrar o ponto, pelo + Registrar. O app não acompanha você em tempo real.'
                  : 'Sem área cadastrada não é possível validar o local nem registrar o ponto. Procure o RH.',
              top: 12,
            ),
            const Divider1(),
            const _AreasLink(),
          ]),
        );
      },
    );
  }
}

/// Demonstração: área fictícia e estado da última detecção simulada.
class _DemoAreaCard extends StatelessWidget {
  const _DemoAreaCard({required this.backend, required this.last});
  final DemoBackend backend;
  final DetectionView? last;

  @override
  Widget build(BuildContext context) {
    final granted = backend.locationGranted;
    final d = last;
    final updated = d == null ? null : DatesPt.hm(d.detectedAt);
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _AreaHeader(),
        _AreaTitle(title: granted ? backend.profile.areaLabel : 'Localização indisponível', subtitle: backend.profile.company),
        if (!granted) ...[
          const StatusBadge('Permissão precisa de atenção', tone: BadgeTone.pending, icon: Lucide.cloudOff),
          const BodyText('Revise as permissões para permitir novas detecções nas áreas autorizadas.', top: 12),
        ] else if (d != null) ...[
          StatusBadge(d.isEntry ? 'Dentro na última detecção' : 'Fora na última detecção',
              tone: d.isEntry ? BadgeTone.ok : BadgeTone.pending, icon: d.isEntry ? Lucide.check : null),
          BodyText('${d.isEntry ? 'Entrada' : 'Saída'} detectada às ${DatesPt.hm(d.detectedAt)}. O estado pode levar um tempo para atualizar.', top: 12),
        ] else
          const BodyText('Nenhuma detecção registrada ainda.', top: 4),
        if (updated != null) _InfoLine(Lucide.clock, 'Última atualização: $updated'),
        _InfoLine(Lucide.shieldCheck, granted ? 'Detecção habilitada' : 'Detecção indisponível'),
        if (!granted)
          SecondaryButton('Revisar permissões',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PermissionsPage()))),
        const Divider1(),
        const _AreasLink(),
      ]),
    );
  }
}

/// Situação do envio ao servidor (fila da demonstração).
class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.backend});
  final DemoBackend backend;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    final pending = backend.pendingCount;
    final (icon, title, subtitle) = backend.offline
        ? (Lucide.wifiOff, 'Sem internet', 'Dados locais preservados na simulação')
        : pending > 0
            ? (Lucide.cloudUpload, '${pendingText(pending)} aguardando envio', 'Consulte a confirmação de entrega')
            : (Lucide.check, 'Tudo enviado', 'Nenhum evento aguardando envio');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: CdfSize.icon, color: c.ink),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: cdfText(13, weight: 600, color: c.ink)),
            Text(subtitle, style: cdfText(12, color: c.sub)),
          ]),
        ),
        TextAction('Ver detalhes',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SyncPage()))),
      ]),
    );
  }
}
