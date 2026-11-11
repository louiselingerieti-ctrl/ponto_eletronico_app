import 'package:flutter/material.dart';
import 'package:presenca_core/presenca_lab.dart';

import '../lab/lab_controller.dart';
import '../lab/lab_scenario.dart';
import 'event_tile.dart';
import 'lab_copy.dart';
import 'tokens.dart';
import 'widgets.dart';

class LabPage extends StatelessWidget {
  const LabPage({super.key, required this.controller});
  final LabController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const HazardBand(),
            Expanded(
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => _Body(controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.c);
  final LabController c;

  @override
  Widget build(BuildContext context) {
    final scenario = [_LinkPanel(), _ConfigPanel(c), _DecisionsPanel(c)];
    final tools = [_GeneratorPanel(c), _SendPanel(c), _EvaluationPanel(c)];
    final events = _EventsPanel(c);

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      Widget col(List<Widget> ws) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final (i, x) in ws.indexed) ...[if (i > 0) const SizedBox(height: 16), x]],
          );
      final Widget grid;
      if (w >= 1100) {
        grid = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 340, child: col(scenario)),
          const SizedBox(width: 16),
          SizedBox(width: 320, child: col(tools)),
          const SizedBox(width: 16),
          Expanded(child: events),
        ]);
      } else if (w >= 720) {
        grid = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: col(scenario)),
            const SizedBox(width: 16),
            Expanded(child: col(tools)),
          ]),
          const SizedBox(height: 16),
          events,
        ]);
      } else {
        grid = col([...scenario, ...tools, events]);
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 64),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [const _Header(), const SizedBox(height: 20), grid],
            ),
          ),
        ),
      );
    });
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: const Text('Laboratório de presença',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.15)),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            'Simula o caminho de um evento de presença: do aparelho até o servidor e a '
            'avaliação. Os dados são fictícios e nada sai ${LabCopy.where}.',
            style: TextStyle(color: context.lab.ink2, fontSize: 15, height: 1.5),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Chip2(LabCopy.memoryChip),
          const Chip2('Servidor simulado, não é o backend'),
          const Chip2('Plataforma de geofence simulada'),
          const Chip2('Sem localização real'),
        ]),
      ],
    );
  }
}

class _LinkPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Panel(title: 'Vínculo fictício', children: [
      Column(children: [
        const DataRow2('Pessoa', Text(LabScenario.personName), tag: FictitiousTag()),
        const DataRow2('Empresa', Text(LabScenario.companyName)),
        DataRow2('Vínculo',
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: '…${LabScenario.linkId.substring(LabScenario.linkId.length - 8)}',
                  style: const TextStyle(fontFamily: labMono, fontSize: 12.5)),
              const TextSpan(text: ' ativo'),
            ]))),
        const DataRow2('Área',
            Text('${LabScenario.areaLabel}, raio de ${LabScenario.areaRadiusMeters} m'),
            tag: FictitiousTag()),
      ]),
    ]);
  }
}

String _hms(DateTime? t) {
  if (t == null) return '—';
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}

class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel(this.c);
  final LabController c;

  @override
  Widget build(BuildContext context) {
    final s = c.configStep;
    final idx = s.index; // none, received, persisted, applied, applyFailed
    StepTone tone(int step) => idx >= step ? StepTone.received : StepTone.none;
    final cells = [
      StepCell('Recebida', idx >= 1 ? _hms(c.receivedAt) : '—', tone(1)),
      StepCell('Persistida', idx >= 2 ? _hms(c.persistedAt) : '—', tone(2)),
      s == ConfigStep.applyFailed
          ? const StepCell('Aplicada', 'falha no registro (simulada)', StepTone.failure)
          : StepCell('Aplicada', s == ConfigStep.applied ? _hms(c.appliedAt) : '—',
              s == ConfigStep.applied ? StepTone.received : StepTone.none),
    ];
    final vu = c.validUntil?.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return Panel(
      title: 'Configuração ${LabScenario.configRevision}',
      children: [
        StepTrack(cells, semanticsLabel: 'Etapas da configuração'),
        Note(TextSpan(children: [
          TextSpan(text: 'Aqui, "persistida" significa guardada ${LabCopy.memoryPlace}, sem cifra. '
              '"Aplicada" é uma confirmação da '),
          TextSpan(text: 'plataforma simulada', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: '. Nenhum geofence real é registrado.'),
        ])),
        Wrap(spacing: 8, runSpacing: 8, children: [
          // Uma revisão só neste laboratório: depois de persistida, receber de
          // novo não teria efeito visível; o botão fica desabilitado.
          OutlinedButton(
              onPressed: s == ConfigStep.none || s == ConfigStep.received ? c.receiveConfig : null,
              child: const Text('Receber configuração')),
          OutlinedButton(
              onPressed: s == ConfigStep.received ? c.persistConfig : null,
              child: const Text('Persistir')),
          OutlinedButton(
              onPressed: s == ConfigStep.persisted || s == ConfigStep.applyFailed
                  ? c.confirmApply
                  : null,
              child: const Text('Confirmar aplicação')),
          OutlinedButton(
              onPressed: s == ConfigStep.persisted ? c.failApply : null,
              child: const Text('Simular falha de registro')),
        ]),
        Column(children: [
          DataRow2('Válida até',
              Text(vu == null ? '—' : '${two(vu.day)}/${two(vu.month)}/${vu.year}, ${_hms(vu)}'),
              tag: vu == null ? null : const FictitiousTag()),
          const DataRow2('Relógio', Text('tolerância de 5 s'),
              tag: FictitiousTag('só na simulação')),
          const DataRow2('Nova tentativa', Text('5 s, dobrando até 30 min'),
              tag: FictitiousTag('só na simulação')),
        ]),
      ],
    );
  }
}

class _DecisionsPanel extends StatelessWidget {
  const _DecisionsPanel(this.c);
  final LabController c;

  static const _labels = {
    LabDecision.expiredConfig: ('D-CFG-1', 'Detecção com a configuração vencida'),
    LabDecision.revokedLink: ('D-LINK-1', 'Detecção para vínculo revogado'),
    LabDecision.afterAuthLoss: ('D-AUTH-2', 'Detecção depois de a sessão expirar'),
  };

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    return Panel(title: 'Decisões pendentes', children: [
      const Note(TextSpan(children: [
        TextSpan(text: 'Estas regras ainda não foram decididas. O laboratório precisa de uma opção '
            'para rodar. A escolha abaixo vale '),
        TextSpan(text: 'só nesta simulação', style: TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: ' e não é política aprovada. Esta versão do laboratório ainda não simula '
            'vencimento, revogação ou sessão expirada.'),
      ])),
      for (final d in LabDecision.values)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              border: Border.all(color: lab.line), borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(style: const TextStyle(fontSize: 13), children: [
              TextSpan(text: '${_labels[d]!.$1} ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: _labels[d]!.$2),
            ])),
            const SizedBox(height: 6),
            SegmentedButton<PendingCaseHandling>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: PendingCaseHandling.recordAndFlag, label: Text('Gravar e marcar')),
                ButtonSegment(value: PendingCaseHandling.refuse, label: Text('Recusar')),
              ],
              selected: {c.decisions[d]!},
              onSelectionChanged: (s) => c.setDecision(d, s.single),
            ),
          ]),
        ),
    ]);
  }
}

class _GeneratorPanel extends StatefulWidget {
  const _GeneratorPanel(this.c);
  final LabController c;

  @override
  State<_GeneratorPanel> createState() => _GeneratorPanelState();
}

class _GeneratorPanelState extends State<_GeneratorPanel> {
  static const _statuses = [
    (DetectionStatus.backgroundLocationRevoked, 'Permissão de localização revogada'),
    (DetectionStatus.locationServicesDisabled, 'Localização desligada'),
    (DetectionStatus.batteryRestrictionDetected, 'Restrição de bateria'),
    (DetectionStatus.appRestarted, 'App reiniciado'),
  ];
  DetectionStatus _status = DetectionStatus.backgroundLocationRevoked;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Panel(title: 'Gerar evento sintético', children: [
      Note.plain('Estes botões são ferramentas de teste. No produto não há botão: os eventos vêm '
          'do sistema operacional.'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton(
            onPressed: () => c.generateTransition(Transition.enter), child: const Text('Entrada')),
        OutlinedButton(
            onPressed: () => c.generateTransition(Transition.exit), child: const Text('Saída')),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: double.infinity,
          child: DropdownButtonFormField<DetectionStatus>(
            initialValue: _status,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Tipo de status', border: OutlineInputBorder(), isDense: true),
            items: [
              for (final (s, l) in _statuses) DropdownMenuItem(value: s, child: Text(l)),
            ],
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => c.generateStatus(_status), child: const Text('Gerar status')),
      ]),
      if (c.generatorNotice != null) Note.plain(c.generatorNotice!),
    ]);
  }
}

class _SendPanel extends StatelessWidget {
  const _SendPanel(this.c);
  final LabController c;

  static const _options = [
    (NextSend.normal, 'Normal', null),
    (NextSend.networkDown, 'Rede ausente', 'Sem resposta. Os eventos voltam para a fila.'),
    (NextSend.transient503, 'Falha transitória (503)', 'O servidor não grava nada. Nova tentativa depois.'),
    (NextSend.partialAck, 'ACK parcial', 'O servidor grava tudo, mas não confirma o último evento do lote.'),
  ];

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final r = c.report;
    final (border, bg) = switch (r.tone) {
      ReportTone.error => (lab.failure, lab.failureBg),
      ReportTone.ok => (lab.received, lab.noteBg),
      ReportTone.neutral => (lab.lineStrong, lab.noteBg),
    };
    return Panel(title: 'Envio', children: [
      InputDecorator(
        decoration: const InputDecoration(
            labelText: 'Próximo envio', border: OutlineInputBorder(), isDense: true),
        child: RadioGroup<NextSend>(
          groupValue: c.nextSend,
          onChanged: (v) => c.setNextSend(v ?? NextSend.normal),
          child: Column(children: [
            for (final (v, t, s) in _options)
              RadioListTile<NextSend>(
                value: v,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(t, style: const TextStyle(fontSize: 14)),
                subtitle: s == null ? null : Text(s, style: TextStyle(fontSize: 12.5, color: lab.ink2)),
              ),
          ]),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: c.sending ? null : c.sendNow,
          child: Text(c.sending ? 'Enviando…' : 'Enviar fila agora'),
        ),
      ),
      Semantics(
        liveRegion: true,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            border: Border(left: BorderSide(color: border, width: 4)),
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.message, style: const TextStyle(fontSize: 14)),
            if (r.detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(r.detail!, style: TextStyle(fontSize: 12.5, color: lab.ink2)),
              ),
          ]),
        ),
      ),
    ]);
  }
}

class _EvaluationPanel extends StatefulWidget {
  const _EvaluationPanel(this.c);
  final LabController c;

  @override
  State<_EvaluationPanel> createState() => _EvaluationPanelState();
}

class _EvaluationPanelState extends State<_EvaluationPanel> {
  SimEvaluation _v = SimEvaluation.inside;

  @override
  Widget build(BuildContext context) {
    return Panel(title: 'Avaliação simulada', children: [
      const Note(TextSpan(children: [
        TextSpan(text: 'No sistema real, quem avalia é o servidor. Aqui o resultado é escolhido à mão '
            'e é fictício. Avaliar presença '),
        TextSpan(text: 'não', style: TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: ' cria marcação de jornada.'),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: double.infinity,
          child: DropdownButtonFormField<SimEvaluation>(
            initialValue: _v,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Resultado fictício', border: OutlineInputBorder(), isDense: true),
            items: [
              for (final e in SimEvaluation.values)
                DropdownMenuItem(value: e, child: Text(_cap(evaluationLabels[e]!))),
            ],
            onChanged: (v) => setState(() => _v = v ?? _v),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
            onPressed: () => widget.c.evaluateReceived(_v), child: const Text('Avaliar recebidos')),
      ]),
    ]);
  }

  static String _cap(String s) => s[0].toUpperCase() + s.substring(1);
}

class _EventsPanel extends StatelessWidget {
  const _EventsPanel(this.c);
  final LabController c;

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final evs = c.events;
    final counts = {for (final s in DeliveryState.values) s: 0};
    for (final e in evs) {
      counts[e.event.state] = counts[e.event.state]! + 1;
    }
    final evaluated = evs.where((e) => e.evaluation != null).length;
    Widget count(Color color, String label, int n) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$label: $n', style: const TextStyle(fontSize: 14)),
        ]);

    return Panel(
      title: 'Eventos',
      trailing: Wrap(spacing: 14, runSpacing: 4, children: [
        count(lab.saved, 'Salvos', counts[DeliveryState.savedLocally]!),
        count(lab.sent, 'Enviando', counts[DeliveryState.sending]!),
        count(lab.received, 'Recebidos', counts[DeliveryState.received]! - evaluated),
        count(lab.evaluated, 'Avaliados', evaluated),
      ]),
      children: [
        if (evs.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
                border: Border.all(color: lab.lineStrong), borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              const Text('Nenhum evento ainda.', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Receba, persista e aplique a configuração. Depois gere uma entrada.',
                  textAlign: TextAlign.center, style: TextStyle(color: lab.ink2)),
            ]),
          )
        else
          Column(children: [
            for (final (i, e) in evs.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              EnterOnce(key: ValueKey(e.event.eventId), child: EventTile(e)),
            ],
          ]),
      ],
    );
  }
}
