import 'package:flutter/foundation.dart' show immutable;

/// Conta autenticada (GET /v1/me). Vem do servidor; o app não inventa.
@immutable
class SessionUser {
  const SessionUser({
    required this.accountId,
    required this.email,
    required this.name,
    required this.mustChangePassword,
    required this.sessionExpiresAt,
  });

  final String accountId;
  final String email;
  final String name;
  final bool mustChangePassword;
  final DateTime sessionExpiresAt;

  String get firstName {
    final t = name.trim();
    if (t.isEmpty) return email.split('@').first;
    return t.split(RegExp(r'\s+')).first;
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return email.isEmpty ? '?' : email[0].toUpperCase();
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}

/// Acesso a um grupo (GET /v1/me/memberships).
@immutable
class Membership {
  const Membership({
    required this.tenantId,
    required this.tenantSlug,
    required this.tenantName,
    required this.tenantActive,
    required this.membershipActive,
    required this.roles,
  });

  final String tenantId;
  final String tenantSlug;
  final String tenantName;
  final bool tenantActive;
  final bool membershipActive;
  final List<String> roles;

  bool get usable => tenantActive && membershipActive;

  /// O app é só para o COLABORADOR: exige o papel `employee`. Papéis de
  /// gestão (tenant_admin, hr, manager) não dão acesso ao app.
  bool get isEmployee => roles.contains('employee');
}

/// Falhas de autenticação, já traduzidas para o que a tela precisa mostrar.
/// Nunca carregam senha, cookie ou corpo da resposta.
enum AuthFailure {
  invalidCredentials('E-mail ou senha incorretos.'),
  accountInactive('Esta conta está desativada. Procure o RH.'),
  passwordChangeRequired(
      'Sua senha é temporária. Troque-a pelo portal da empresa antes de usar o app.'),
  noActiveAccess('Sua conta não tem um acesso ativo a uma empresa. Procure o RH.'),
  notEmployee('Este app é só para colaboradores. Para administrar, use o portal.'),
  sessionExpired('Sua sessão terminou. Entre novamente.'),
  rateLimited('Muitas tentativas. Aguarde um minuto e tente de novo.'),
  currentPasswordWrong('A senha temporária não confere.'),
  weakPassword('A nova senha precisa ter de 12 a 128 caracteres.'),
  passwordChangeUnavailable(
      'Não foi possível trocar a senha pelo app agora. Tente pelo portal da empresa.'),
  network('Sem conexão com o servidor. Verifique a internet e tente de novo.'),
  server('O servidor não respondeu como esperado. Tente de novo em instantes.');

  const AuthFailure(this.message);
  final String message;
}

final class AuthException implements Exception {
  const AuthException(this.failure);
  final AuthFailure failure;
  @override
  String toString() => 'AuthException(${failure.name})';
}

/// Porta de autenticação. Implementações:
/// - `BackendAuthGateway` (lib/integration): backend real, sessão por cookie
///   (provisório até o backend aceitar token para o app — D-AUTH-1);
/// - nenhuma no modo demonstração (sessão simulada em AppServices).
abstract interface class AuthGateway {
  /// Entra com e-mail e senha. A senha não é guardada em lugar nenhum.
  Future<SessionUser> signIn(String email, String password);

  /// Retoma a sessão guardada no aparelho, se ainda válida no servidor.
  Future<SessionUser?> restore();

  Future<List<Membership>> memberships();

  /// Troca a própria senha (ex.: senha temporária no primeiro acesso).
  /// Encerra as outras sessões da conta. Devolve a conta atualizada.
  Future<SessionUser> changePassword(String currentPassword, String newPassword);

  /// Encerra a sessão no servidor (quando possível) e apaga do aparelho.
  Future<void> signOut();
}
