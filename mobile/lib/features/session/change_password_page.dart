import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/shell.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/layout/cdf_layout.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/cdf_widgets.dart';

/// Primeiro acesso com senha temporária: a pessoa cria a própria senha no
/// app (POST /v1/auth/change-password). Regra de tamanho = a do backend
/// (12 a 128). Nenhuma senha fica guardada.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  static const minLength = 12;
  static const maxLength = 128;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validateCurrent(String? v) =>
      (v ?? '').isEmpty ? 'Informe a senha temporária.' : null;

  String? _validateNext(String? v) {
    final p = v ?? '';
    if (p.length < ChangePasswordPage.minLength || p.length > ChangePasswordPage.maxLength) {
      return 'Use de ${ChangePasswordPage.minLength} a ${ChangePasswordPage.maxLength} caracteres.';
    }
    if (p == _current.text) return 'A nova senha precisa ser diferente da temporária.';
    return null;
  }

  String? _validateConfirm(String? v) =>
      v != _next.text ? 'As senhas não conferem.' : null;

  Future<void> _submit() async {
    setState(() => _tried = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    final s = AppScope.of(context);
    final current = _current.text;
    final next = _next.text;
    // Nada de senha guardada em memória de widget depois do envio.
    _current.clear();
    _next.clear();
    _confirm.clear();
    setState(() => _tried = false);
    await s.changePassword(current, next);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final busy = s.authenticating;
    final failure = s.lastFailure;
    final c = context.cdf;
    final l = CdfLayout.of(context);

    Widget field(String label, TextEditingController ctl, String? Function(String?) validator,
            {TextInputAction action = TextInputAction.next, List<String> hints = const []}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FieldLabel(label),
          TextFormField(
            controller: ctl,
            obscureText: true,
            enabled: !busy,
            autofillHints: hints,
            textInputAction: action,
            style: cdfText(16, color: c.ink),
            decoration: cdfInput(context),
            validator: validator,
            onFieldSubmitted: action == TextInputAction.done ? (_) => _submit() : null,
          ),
        ]);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const BrandHeader(),
          Expanded(
            child: Form(
              key: _form,
              autovalidateMode: _tried ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
              child: PageBody(children: [
                Padding(
                  padding: EdgeInsets.only(top: l.loginTop / 2),
                  child: PageIntro(
                    'Crie sua senha',
                    'Olá, ${s.passwordChangeFirstName}. Sua senha atual é temporária. '
                        'Defina uma nova para continuar.',
                  ),
                ),
                field('Senha temporária', _current, _validateCurrent,
                    hints: const [AutofillHints.password]),
                field('Nova senha', _next, _validateNext,
                    hints: const [AutofillHints.newPassword]),
                field('Confirme a nova senha', _confirm, _validateConfirm,
                    action: TextInputAction.done, hints: const [AutofillHints.newPassword]),
                const Note('Use de 12 a 128 caracteres. Ao salvar, outros aparelhos conectados '
                    'com esta conta são desconectados.'),
                if (failure != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Semantics(
                      liveRegion: true,
                      child: StatusBadge(failure.message,
                          tone: BadgeTone.pending, icon: Lucide.circleAlert),
                    ),
                  ),
                PrimaryButton(busy ? 'Salvando…' : 'Salvar nova senha',
                    top: l.formButtonTop, onPressed: busy ? null : _submit),
                TextAction('Sair', onPressed: s.signOut),
              ]),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: const DemoFooter(),
    );
  }
}
