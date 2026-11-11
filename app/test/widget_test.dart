import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_colaborador_lab/lab/lab_controller.dart';
import 'package:ponto_colaborador_lab/main.dart';
import 'package:ponto_colaborador_lab/ui/lab_copy.dart';
import 'package:ponto_colaborador_lab/ui/widgets.dart';

void main() {
  Future<LabController> pumpLab(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = LabController(now: () => DateTime.utc(2026, 11, 10, 14), sendDelay: Duration.zero);
    addTearDown(c.dispose);
    await t.pumpWidget(LabApp(controller: c));
    return c;
  }

  Future<void> tap(WidgetTester t, String label) async {
    final f = find.ancestor(
        of: find.text(label), matching: find.bySubtype<ButtonStyleButton>());
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  for (final size in [const Size(1400, 1000), const Size(800, 1000), const Size(390, 900)]) {
    testWidgets('aviso permanente e estado vazio em ${size.width.toInt()} px', (t) async {
      await pumpLab(t, size);
      expect(find.text(HazardBand.text), findsOneWidget);
      expect(find.text('Nenhum evento ainda.'), findsOneWidget);
      expect(find.text(LabCopy.memoryChip), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'sem overflow de layout');
    });
  }

  testWidgets('fluxo pela tela: configuração, entrada e envio', (t) async {
    await pumpLab(t, const Size(1400, 1100));
    await tap(t, 'Receber configuração');
    await tap(t, 'Persistir');
    await tap(t, 'Confirmar aplicação');
    final receive = t.widget<ButtonStyleButton>(find.ancestor(
        of: find.text('Receber configuração'), matching: find.bySubtype<ButtonStyleButton>()));
    expect(receive.onPressed, isNull, reason: 'desabilitado depois de persistir');
    await tap(t, 'Entrada');
    expect(find.text('Entrada em Unidade Sintética Centro'), findsOneWidget);
    expect(find.text('Marcação de jornada: aguardando política (D-JOR-1)'), findsOneWidget);
    await tap(t, 'Enviar fila agora');
    expect(find.textContaining('recebido(s) pelo servidor simulado'), findsOneWidget);
    expect(find.text('ACK com recibo'), findsWidgets);
    // A faixa continua visível depois de rolar.
    await t.drag(find.byType(SingleChildScrollView), const Offset(0, -800));
    await t.pumpAndSettle();
    expect(find.text(HazardBand.text), findsOneWidget);
  });
}
