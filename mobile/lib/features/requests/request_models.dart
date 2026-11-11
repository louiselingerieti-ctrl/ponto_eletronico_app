import 'package:flutter/material.dart' show TimeOfDay;

/// Categorias do relatório v1.0 (seção 6). A lista final virá do catálogo do
/// servidor (contrato proposto, não implementado).
enum RequestCategory {
  detectionProblem('Problema na detecção'),
  recordReview('Solicitar revisão de registro'),
  absenceJustification('Justificativa de ausência'),
  other('Outro assunto');

  const RequestCategory(this.label);
  final String label;
}

/// Estados mostrados ao colaborador. "Respondida" é apresentação de uma
/// resposta, não necessariamente aprovação. O cliente nunca atribui estado
/// administrativo.
enum RequestStatus {
  /// Só no aparelho, sem envio (sem conexão). Não é "recebido".
  localDraft('Rascunho local'),
  underReview('Em análise'),
  answered('Respondida');

  const RequestStatus(this.label);
  final String label;
}

class EmployeeRequest {
  const EmployeeRequest({
    required this.displayId,
    required this.clientRequestId,
    required this.category,
    required this.date,
    required this.description,
    required this.status,
    required this.reply,
    this.time,
  });

  /// Identificador de EXEMPLO (#1042…). Não é regra para o ID de produção.
  final int displayId;

  /// Chave idempotente gerada no aparelho (contrato proposto).
  final String clientRequestId;
  final RequestCategory category;

  /// Data civil do ocorrido (sem fuso; não convertida para UTC).
  final DateTime date;
  final TimeOfDay? time;
  final String description;
  final RequestStatus status;

  /// Resposta da empresa ou próxima etapa.
  final String reply;
}

/// Dados digitados no formulário.
class RequestDraft {
  const RequestDraft({
    required this.category,
    required this.date,
    required this.description,
    this.time,
  });

  final RequestCategory category;
  final DateTime date;
  final TimeOfDay? time;
  final String description;

  static const minDescription = 10;
  static const maxDescription = 2000;

  /// Regra de REFERÊNCIA (10 a 2000). A final deve ser a mesma do backend.
  static String? validateDescription(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Descreva o ocorrido.';
    if (t.length < minDescription) {
      return 'Escreva pelo menos $minDescription caracteres.';
    }
    if (t.length > maxDescription) {
      return 'Use no máximo $maxDescription caracteres.';
    }
    return null;
  }
}

/// Porta de solicitações. Implementação atual: SIMULADA (lib/demo).
abstract interface class RequestsRepository {
  List<EmployeeRequest> list();
  EmployeeRequest? byDisplayId(int id);

  /// Sem conexão, guarda como rascunho local; nunca marca como recebido.
  Future<EmployeeRequest> submit(RequestDraft draft, {required bool online});
}
