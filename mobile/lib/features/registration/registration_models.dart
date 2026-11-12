import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

import '../punch/punch_models.dart';

/// + Registrar, em ordem obrigatória:
///   1. validar a localização ATUAL (dentro de uma área autorizada);
///   2. tirar uma foto frontal nova e conferir;
///   3. escolher Entrada ou Saída e confirmar.
/// Sem localização validada não há câmera; sem foto não há ponto. Nada é
/// gravado antes da confirmação.

/// Por que a localização não foi validada. Toda falha bloqueia o registro.
enum LocationFailure {
  outside('Você está fora da área',
      'A posição informada não está dentro de uma área autorizada. A câmera e o registro permanecem bloqueados.'),
  denied('Permita a localização',
      'Sem acesso à localização, não é possível validar o local para registrar o ponto.'),
  blocked('Permita a localização',
      'O acesso à localização está bloqueado nas configurações do celular. Libere-o para o app e tente novamente.'),
  serviceOff('Ligue a localização',
      'A localização do celular está desligada. Ligue-a e tente novamente.'),
  imprecise('Localização imprecisa',
      'Não foi possível confirmar uma posição atual com precisão suficiente. Tente novamente em um local com melhor sinal.'),
  unavailable('Localização indisponível',
      'O celular não conseguiu obter a posição a tempo. Tente novamente em um local com melhor sinal.'),
  noArea('Área de trabalho não cadastrada',
      'A empresa ainda não cadastrou a área de trabalho, então não é possível validar o local. Procure o RH.'),
  noLink('Sem vínculo ativo',
      'Sua conta não está ligada a um vínculo ativo, então não há ponto para registrar. Procure o RH.'),
  companyInactive('Empresa desativada', 'A empresa está desativada no sistema. Procure o RH.'),
  network('Sem conexão com o servidor',
      'Não foi possível buscar suas áreas autorizadas. Verifique a internet e tente novamente.'),
  sessionExpired('Sua sessão terminou', 'Entre novamente para registrar o ponto.'),
  expired('A validação expirou',
      'A localização e a foto valem por pouco tempo. Valide o local de novo para registrar.');

  const LocationFailure(this.title, this.message);
  final String title;
  final String message;
}

/// Localização conferida NESTA sessão de registro.
@immutable
class ValidatedLocation {
  const ValidatedLocation({
    required this.areaName,
    required this.companyName,
    required this.at,
    this.linkId,
    this.location,
    this.suggested,
  });
  final String areaName;
  final String companyName;

  /// Quando foi validada (relógio do aparelho): define a validade.
  final DateTime at;

  /// Só no modo real: vínculo e posição enviados ao servidor na confirmação.
  final String? linkId;
  final DeviceLocation? location;

  /// O que o servidor espera como próximo ponto, quando ele informa.
  final PunchKind? suggested;
}

@immutable
class LocationCheck {
  const LocationCheck.ok(ValidatedLocation this.location)
      : failure = null,
        areaName = null,
        distanceM = null;
  const LocationCheck.failed(LocationFailure this.failure, {this.areaName, this.distanceM}) : location = null;
  final ValidatedLocation? location;
  final LocationFailure? failure;

  /// Fora da área: a mais próxima e a distância até o centro dela.
  final String? areaName;
  final int? distanceM;
}

/// Foto tirada nesta sessão. [bytes] null = ilustração da demonstração.
@immutable
class CapturedPhoto {
  const CapturedPhoto({required this.at, this.bytes});
  final DateTime at;
  final Uint8List? bytes;
}

@immutable
class PhotoResult {
  const PhotoResult.ok(CapturedPhoto this.photo)
      : problem = null,
        detail = null;
  const PhotoResult.failed(SelfieProblem this.problem, {this.detail}) : photo = null;
  final CapturedPhoto? photo;
  final SelfieProblem? problem;

  /// Código curto para diagnóstico (mostrado junto do aviso).
  final String? detail;
}

/// O que vai para a confirmação. [attemptId] é estável enquanto a pessoa
/// tenta de novo: o servidor não duplica o ponto.
@immutable
class RegistrationDraft {
  const RegistrationDraft({required this.attemptId, required this.kind, required this.location, required this.photo});
  final String attemptId;
  final PunchKind kind;
  final ValidatedLocation location;
  final CapturedPhoto photo;
}

/// Ponto gravado.
@immutable
class RegistrationReceipt {
  const RegistrationReceipt({required this.kind, required this.recordedAt, required this.areaName, required this.received, this.serverNote});
  final PunchKind kind;

  /// Horário do registro (no modo real, o oficial do servidor).
  final DateTime recordedAt;
  final String areaName;

  /// true = o servidor confirmou o recebimento; false = só salvo no aparelho
  /// (demonstração), aguardando envio.
  final bool received;

  /// Observação do servidor sobre o local (ex.: sinalizado para o RH).
  final String? serverNote;
}

/// Se a confirmação falhar, o que a pessoa pode fazer.
enum CommitRecovery {
  /// Tentar de novo com os mesmos dados (o servidor não duplica).
  retry,

  /// Tirar outra foto (o servidor recusou a foto).
  retakePhoto,

  /// Começar de novo pela localização.
  restart,

  /// Não há o que tentar agora (ex.: ponto repetido em menos de um minuto).
  none,
}

@immutable
class CommitOutcome {
  const CommitOutcome.ok(RegistrationReceipt this.receipt)
      : message = null,
        recovery = CommitRecovery.none;
  const CommitOutcome.failed(String this.message, this.recovery) : receipt = null;
  final RegistrationReceipt? receipt;
  final String? message;
  final CommitRecovery recovery;
}

/// O que o registro precisa do mundo de fora. Implementações:
/// - modo real: PunchRegistrationPort (GPS, câmera e servidor de verdade);
/// - demonstração: DemoRegistrationPort em lib/demo (tudo simulado).
abstract interface class RegistrationPort {
  /// Tudo simulado (a tela avisa e muda os textos).
  bool get simulated;

  DateTime now();

  /// Por quanto tempo a localização validada (e a foto) valem até a confirmação.
  Duration get evidenceValidity;

  Future<LocationCheck> validateLocation();
  Future<PhotoResult> takePhoto();
  Future<CommitOutcome> commit(RegistrationDraft draft);

  /// Abre as configurações do app no celular (liberar câmera ou localização).
  Future<void> openAppSettings();
}
