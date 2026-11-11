/// Decisões operacionais AINDA NÃO TOMADAS.
///
/// O núcleo não escolhe por ninguém: quem monta o app precisa passar cada
/// opção explicitamente (não há valor padrão). Enquanto o app Flutter não
/// existir, nenhuma opção foi escolhida. Os testes exercitam as duas.
library;

import 'package:meta/meta.dart';

/// O que fazer com uma detecção quando ocorre o caso pendente.
enum PendingCaseHandling {
  /// Grava o fato na fila, com marcação local do contexto. O envio segue o
  /// fluxo normal; o servidor avalia.
  recordAndFlag,

  /// Não grava. O caso de uso devolve a recusa com o identificador da
  /// decisão pendente, para a camada de cima informar.
  refuse,
}

@immutable
class PendingPolicies {
  const PendingPolicies({
    required this.expiredConfig,
    required this.revokedLink,
    required this.afterAuthLoss,
  });

  /// D-CFG-1: detecção com a configuração aplicada vencida (`validUntil`).
  final PendingCaseHandling expiredConfig;

  /// D-LINK-1: detecção para vínculo marcado como revogado no aparelho.
  final PendingCaseHandling revokedLink;

  /// D-AUTH-2: detecção depois que o envio parou por 401/403 (sessão
  /// expirada ou instalação revogada) e antes de nova autenticação.
  final PendingCaseHandling afterAuthLoss;
}

/// Identificadores das decisões, para relatório e tela.
abstract final class PendingDecision {
  static const expiredConfig = 'D-CFG-1';
  static const revokedLink = 'D-LINK-1';
  static const afterAuthLoss = 'D-AUTH-2';
}
