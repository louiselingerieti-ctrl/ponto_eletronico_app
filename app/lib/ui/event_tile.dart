import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:presenca_core/presenca_lab.dart';

import '../lab/lab_controller.dart';
import '../lab/lab_scenario.dart';
import 'tokens.dart';
import 'widgets.dart';

const statusLabels = <String, String>{
  'config_applied': 'Configuração aplicada (plataforma simulada)',
  'geofence_registration_failed': 'Falha ao registrar as áreas (simulada)',
  'background_location_revoked': 'Permissão de localização revogada',
  'location_services_disabled': 'Localização desligada',
  'battery_restriction_detected': 'Restrição de bateria detectada',
  'app_restarted': 'App reiniciado',
  'config_expired': 'Configuração vencida',
};

const evaluationLabels = {
  SimEvaluation.inside: 'dentro da área',
  SimEvaluation.outside: 'fora da área',
  SimEvaluation.uncertain: 'incerto',
  SimEvaluation.needsReview: 'em análise pelo RH',
};

const _qualityLabels = {
  'trusted': 'confiável',
  'drift_suspected': 'suspeita de desvio',
  'uncertain': 'incerta',
};

class EventTile extends StatelessWidget {
  const EventTile(this.v, {super.key});
  final LabEventView v;

  String get _title {
    if (v.isTransition) {
      return v.payload['transition'] == 'enter'
          ? 'Entrada em ${LabScenario.areaLabel}'
          : 'Saída de ${LabScenario.areaLabel}';
    }
    final s = v.payload['status'] as String;
    return statusLabels[s] ?? s;
  }

  List<StepCell> _cells() {
    final e = v.event;
    final reached = switch (e.state) {
      DeliveryState.savedLocally => 0,
      DeliveryState.sending => 1,
      _ => 2,
    };
    StepCell sent;
    if (e.state == DeliveryState.sending) {
      sent = StepCell('Enviado', 'tentativa ${e.attempts}', StepTone.inProgress);
    } else if (e.state == DeliveryState.savedLocally && v.lastFailure != null) {
      sent = StepCell('Enviado', '${v.lastFailure}, volta à fila', StepTone.failure);
    } else if (reached >= 2) {
      sent = StepCell('Enviado', '${e.attempts} tentativa(s)', StepTone.sent);
    } else {
      sent = const StepCell('Enviado', '—', StepTone.none);
    }

    final StepCell received = switch (e.state) {
      DeliveryState.received => StepCell('Recebido',
          v.isDuplicate ? 'duplicado, recibo original' : 'ACK com recibo', StepTone.received),
      DeliveryState.conflict => const StepCell('Recebido', 'conflito: mantido para análise', StepTone.failure),
      DeliveryState.rejected => StepCell('Recebido', 'recusado: ${e.outcomeCode}', StepTone.failure),
      _ => const StepCell('Recebido', '—', StepTone.none),
    };

    final StepCell evaluated;
    if (v.evaluation != null) {
      evaluated = StepCell(
          'Avaliado', '${evaluationLabels[v.evaluation]} (simulado)', StepTone.evaluated);
    } else if (e.state == DeliveryState.received) {
      evaluated = StepCell('Avaliado', v.isTransition ? 'pendente' : 'não se aplica', StepTone.none);
    } else {
      evaluated = const StepCell('Avaliado', '—', StepTone.none);
    }
    return [const StepCell('Salvo', 'no aparelho', StepTone.saved), sent, received, evaluated];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lab;
    final clock = v.payload['clock'] as Map;
    final detected = DateTime.parse(clock['detectedAt'] as String).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final hms = '${two(detected.hour)}:${two(detected.minute)}:${two(detected.second)}';
    final quality = _qualityLabels[clock['quality']] ?? '${clock['quality']}';
    final meta = TextStyle(fontSize: 13, color: c.ink2);

    return LabSurface(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
              Text(_title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Text.rich(TextSpan(style: meta, children: [
                TextSpan(text: 'nº ${v.event.installationSequence}   '),
                TextSpan(
                    text: v.event.eventId.substring(0, 8),
                    style: const TextStyle(fontFamily: labMono, fontSize: 12.5)),
              ])),
            ],
          ),
          const SizedBox(height: 6),
          Text('Detectado às $hms pelo relógio do aparelho. Qualidade do relógio: $quality.',
              style: meta),
          if (v.isTransition)
            Text('Instante do cruzamento: não informado pela plataforma simulada.', style: meta),
          const SizedBox(height: 10),
          StepTrack(_cells(), semanticsLabel: 'Etapas do evento'),
          const SizedBox(height: 6),
          if (v.isTransition) ...[
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Chip2('Marcação de jornada: aguardando política (D-JOR-1)'),
            ),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            dense: true,
            title: Text('Ver conteúdo enviado', style: TextStyle(fontSize: 13, color: c.ink2)),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.noteBg, borderRadius: BorderRadius.circular(6)),
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(v.payload),
                  style: const TextStyle(fontFamily: labMono, fontSize: 12, height: 1.45),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
