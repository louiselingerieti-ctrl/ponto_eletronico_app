import 'dart:async';
import 'dart:typed_data';

import 'package:casa_futuro_colaborador/features/punch/punch_controller.dart';
import 'package:casa_futuro_colaborador/features/punch/punch_models.dart';
import 'package:casa_futuro_colaborador/features/registration/registration_controller.dart';
import 'package:casa_futuro_colaborador/features/registration/registration_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Porta controlada pelo teste: cada chamada espera o teste responder.
class StepPort implements RegistrationPort {
  DateTime clock = DateTime(2026, 11, 11, 8);
  Completer<LocationCheck>? location;
  Completer<PhotoResult>? photo;
  Completer<CommitOutcome>? commitCall;
  final drafts = <RegistrationDraft>[];

  @override
  bool get simulated => false;
  @override
  DateTime now() => clock;
  @override
  Duration get evidenceValidity => const Duration(minutes: 5);
  @override
  Future<LocationCheck> validateLocation() => (location = Completer()).future;
  @override
  Future<PhotoResult> takePhoto() => (photo = Completer()).future;
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<CommitOutcome> commit(RegistrationDraft draft) {
    drafts.add(draft);
    return (commitCall = Completer()).future;
  }
}

ValidatedLocation okAt(DateTime at) => ValidatedLocation(areaName: 'Loja Centro', companyName: 'Casa do Futuro', at: at);
CapturedPhoto shot(DateTime at) => CapturedPhoto(at: at, bytes: Uint8List.fromList([1, 2, 3]));

void main() {
  group('sessão de registro (controlador)', () {
    late StepPort port;
    late RegistrationController r;
    var n = 0;
    setUp(() {
      port = StepPort();
      r = RegistrationController(port, newId: () => 'tentativa-${++n}');
    });

    Future<void> toConfirm() async {
      unawaited(r.begin());
      port.location!.complete(LocationCheck.ok(okAt(port.clock)));
      await pumpEventQueue();
      unawaited(r.takePhoto());
      port.photo!.complete(PhotoResult.ok(shot(port.clock)));
      await pumpEventQueue();
      r.usePhoto();
      r.choose(PunchKind.entry);
    }

    test('sem localização não abre câmera; sem foto não escolhe tipo; sem tipo não grava', () async {
      unawaited(r.takePhoto());
      expect(port.photo, isNull);
      r.choose(PunchKind.entry);
      unawaited(r.confirm());
      expect(port.commitCall, isNull);
      expect(r.step, RegStep.idle);

      unawaited(r.begin());
      expect(r.step, RegStep.locating);
      r.usePhoto();
      r.choose(PunchKind.entry);
      expect(r.step, RegStep.locating);
    });

    test('resposta que chega depois de cancelar é ignorada (localização e foto)', () async {
      unawaited(r.begin());
      final stale = port.location!;
      r.cancel();
      stale.complete(LocationCheck.ok(okAt(port.clock)));
      await pumpEventQueue();
      expect(r.step, RegStep.idle);
      expect(r.location, isNull);

      unawaited(r.begin());
      port.location!.complete(LocationCheck.ok(okAt(port.clock)));
      await pumpEventQueue();
      unawaited(r.takePhoto());
      final stalePhoto = port.photo!;
      unawaited(r.begin()); // voltou ao +: recomeça
      stalePhoto.complete(PhotoResult.ok(shot(port.clock)));
      await pumpEventQueue();
      expect(r.photo, isNull, reason: 'foto de outra tentativa não libera o registro');
      expect(r.step, RegStep.locating);
    });

    test('toque duplo em confirmar grava uma vez; tentar de novo reaproveita a mesma tentativa', () async {
      await toConfirm();
      unawaited(r.confirm());
      unawaited(r.confirm());
      expect(port.drafts, hasLength(1));
      port.commitCall!.complete(const CommitOutcome.failed('sem rede', CommitRecovery.retry));
      await pumpEventQueue();
      expect(r.step, RegStep.confirm);
      unawaited(r.confirm());
      expect(port.drafts.map((d) => d.attemptId).toSet(), {'tentativa-1'});
    });

    test('sair durante a gravação não descarta o resultado; sair da conta descarta', () async {
      await toConfirm();
      unawaited(r.confirm());
      r.leave();
      expect(r.step, RegStep.committing);
      port.commitCall!.complete(CommitOutcome.ok(RegistrationReceipt(kind: PunchKind.entry, recordedAt: port.clock, areaName: 'Loja Centro', received: true)));
      await pumpEventQueue();
      expect(r.step, RegStep.done);

      await toConfirm();
      unawaited(r.confirm());
      final pending = port.commitCall!;
      r.discard();
      pending.complete(CommitOutcome.ok(RegistrationReceipt(kind: PunchKind.entry, recordedAt: port.clock, areaName: 'x', received: true)));
      await pumpEventQueue();
      expect(r.step, RegStep.idle);
      expect(r.receipt, isNull);
    });

    test('evidência vencida volta à localização em qualquer etapa', () async {
      unawaited(r.begin());
      port.location!.complete(LocationCheck.ok(okAt(port.clock)));
      await pumpEventQueue();
      port.clock = port.clock.add(const Duration(minutes: 5, seconds: 1));
      unawaited(r.takePhoto());
      expect(port.photo, isNull);
      expect(r.locationFailure, LocationFailure.expired);
    });

    test('distância (haversine) bate com o esperado', () {
      expect(distanceMeters(-23.5, -46.6, -23.4996, -46.6), closeTo(44.5, 1));
      expect(distanceMeters(-23.5, -46.6, -23.49, -46.6), closeTo(1112, 5));
    });
  });

  group('+ Registrar na demonstração', () {
    setUpAll(loadAppFonts);

    testWidgets('fluxo completo simulado: salvo no aparelho, aguardando envio, e aparece no histórico', (t) async {
      final s = await pumpApp(t);
      await tapNav(t, 'Registrar');
      expect(find.text('Agora, tire sua foto'), findsOneWidget);
      expect(find.text('Tirar foto (simulação)'), findsOneWidget);
      await tapText(t, 'Tirar foto (simulação)');
      expect(find.text('Foto capturada · ilustração'), findsOneWidget);
      await tapText(t, 'Usar esta foto');
      await chooseKind(t, 'Entrada');
      await tapText(t, 'Confirmar entrada (simulação)');
      expect(find.text('Entrada salva no aparelho'), findsOneWidget);
      expect(find.text('Aguardando envio'), findsOneWidget);
      expect(find.text('Recebido pelo servidor'), findsNothing);
      expect(s.backend.manualPunches, hasLength(1));
      await tapText(t, 'Ver no histórico');
      expect(find.text('Entrada manual').hitTestable(), findsOneWidget);
    });

    testWidgets('permissão simulada desligada: bloqueia antes da foto', (t) async {
      final s = await pumpApp(t);
      s.backend.setLocationGranted(false);
      await t.pumpAndSettle();
      await tapNav(t, 'Registrar');
      expect(find.text('Permita a localização'), findsOneWidget);
      expect(find.text('Tirar foto (simulação)'), findsNothing);
    });

    testWidgets('validação em andamento mostra o aviso de simulação', (t) async {
      await pumpApp(t);
      await t.tap(find.text('Registrar').last);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Validando localização'), findsOneWidget);
      expect(find.text('Validação simulada em andamento'), findsOneWidget);
      await t.pumpAndSettle();
    });

    for (final dark in [false, true]) {
      testWidgets('capturas da demonstração (${dark ? 'escuro' : 'claro'})', (t) async {
        final sfx = dark ? 'escuro' : 'claro';
        await pumpApp(t, dark: dark);
        await capture(t, 'v2-01-inicio-$sfx');
        await t.tap(find.text('Registrar').last);
        await t.pump(const Duration(milliseconds: 300));
        await capture(t, 'v2-11-validando-$sfx');
        await t.pumpAndSettle();
        await capture(t, 'v2-12-foto-$sfx');
        await tapText(t, 'Tirar foto (simulação)');
        await capture(t, 'v2-13-conferir-$sfx');
        await tapText(t, 'Usar esta foto');
        await capture(t, 'v2-14-tipo-$sfx');
        await chooseKind(t, 'Entrada');
        await capture(t, 'v2-15-confirmar-$sfx');
        await tapText(t, 'Confirmar entrada (simulação)');
        await capture(t, 'v2-16-salva-$sfx');
        await tapText(t, 'Ver no histórico');
        await capture(t, 'v2-17-historico-$sfx');
      });
    }

    testWidgets('menu em 320 px', (t) async {
      await pumpApp(t, size: const Size(320, 700), dark: true);
      await capture(t, 'v2-30-menu-320');
      expect(t.takeException(), isNull);
    });
  });
}
