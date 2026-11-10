import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_colaborador_lab/lab/lab_controller.dart';
import 'package:presenca_core/presenca_lab.dart';

void main() {
  late DateTime now;
  late LabController c;

  setUp(() {
    now = DateTime.utc(2026, 11, 10, 14);
    c = LabController(now: () => now, sendDelay: Duration.zero);
  });
  tearDown(() => c.dispose());

  void applyConfig() {
    c.receiveConfig();
    expect(c.configStep, ConfigStep.received);
    expect(c.persistence.configs.current('00000000-0000-4000-8000-00000000e001'), isNull,
        reason: 'recebida não persiste');
    c.persistConfig();
    expect(c.configStep, ConfigStep.persisted);
    c.confirmApply();
    expect(c.configStep, ConfigStep.applied);
  }

  List<DeliveryState> states() => [for (final e in c.events) e.event.state];

  test('o laboratório declara que não cifra em disco', () {
    expect(c.persistence.isEncryptedAtRest, isFalse);
  });

  test('sem configuração aplicada, a transição não é gerada', () {
    c.generateTransition(Transition.enter);
    expect(c.events, isEmpty);
    expect(c.generatorNotice, contains('Aplique a configuração'));
  });

  test('fluxo feliz: salvo → recebido → avaliado (simulado), sem marcação', () async {
    applyConfig();
    c.generateTransition(Transition.enter);
    final ev = c.events.first;
    expect(ev.isTransition, isTrue);
    expect(ev.payload['observedAt'], isNull);
    expect(ev.payload['observedAtSource'], 'none');
    expect((ev.payload['clock'] as Map)['quality'], 'uncertain');
    expect(ev.payload.containsKey('location'), isFalse);

    await c.sendNow();
    expect(states().every((s) => s == DeliveryState.received), isTrue);
    expect(c.report.tone, ReportTone.ok);

    c.evaluateReceived(SimEvaluation.needsReview);
    final evaluated = c.events.where((e) => e.evaluation != null).toList();
    expect(evaluated.single.isTransition, isTrue, reason: 'status não é avaliado');
  });

  test('rede ausente: volta à fila com backoff; depois do tempo, envia', () async {
    applyConfig();
    c.generateTransition(Transition.enter);
    c.setNextSend(NextSend.networkDown);
    await c.sendNow();
    expect(c.nextSend, NextSend.normal, reason: 'a falha vale para um envio só');
    expect(c.report.message, startsWith('Rede ausente'));
    expect(c.events.first.lastFailure, 'sem resposta');
    expect(states().contains(DeliveryState.received), isFalse);

    await c.sendNow(); // ainda no backoff
    expect(c.report.message, startsWith('Aguardando'));

    now = now.add(const Duration(minutes: 1));
    await c.sendNow();
    expect(states().every((s) => s == DeliveryState.received), isTrue);
  });

  test('503: nada gravado no servidor simulado', () async {
    applyConfig();
    c.generateTransition(Transition.exit);
    c.setNextSend(NextSend.transient503);
    await c.sendNow();
    expect(c.server.stored, isEmpty);
    expect(c.events.first.lastFailure, '503');
  });

  test('ACK parcial: o último volta à fila e depois vira duplicado com o recibo original',
      () async {
    applyConfig(); // gera config_applied
    c.generateTransition(Transition.enter);
    c.generateTransition(Transition.exit);
    c.setNextSend(NextSend.partialAck);
    await c.sendNow();
    final pending = c.events.where((e) => e.event.state == DeliveryState.savedLocally).single;
    expect(pending.lastFailure, 'sem confirmação');
    expect(c.report.message, startsWith('ACK parcial'));
    final original = c.server.stored[pending.event.eventId]!;

    now = now.add(const Duration(minutes: 1));
    await c.sendNow();
    final after = c.events.firstWhere((e) => e.event.eventId == pending.event.eventId);
    expect(after.event.state, DeliveryState.received);
    expect(after.isDuplicate, isTrue);
    expect(after.event.receiptId, original.receiptId);
  });

  test('falha de registro simulada gera status e permite nova confirmação', () {
    c.receiveConfig();
    c.persistConfig();
    c.failApply();
    expect(c.configStep, ConfigStep.applyFailed);
    expect(c.events.single.payload['status'], 'geofence_registration_failed');
    c.confirmApply();
    expect(c.configStep, ConfigStep.applied);
  });

  test('novo controlador começa vazio (equivale a recarregar a página)', () async {
    applyConfig();
    c.generateTransition(Transition.enter);
    final fresh = LabController(now: () => now, sendDelay: Duration.zero);
    addTearDown(fresh.dispose);
    expect(fresh.events, isEmpty);
    expect(fresh.configStep, ConfigStep.none);
  });
}
