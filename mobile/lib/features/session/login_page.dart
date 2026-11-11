import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/shell.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/layout/cdf_layout.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/cdf_widgets.dart';

/// Login VISUAL: não autentica, não valida credenciais no servidor e não
/// guarda a senha. Recuperação de senha não tem tela aprovada.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  static String? _validateEmail(String? v) {
    final t = (v ?? '').trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) return 'Informe um e-mail válido.';
    return null;
  }

  String? _validatePassword(String? v) {
    final p = v ?? '';
    if (p.isEmpty) return 'Informe a senha.';
    // Na demonstração qualquer senha fictícia serve; a regra real é do servidor.
    if (!AppScope.of(context).realMode && p.length < 4) {
      return 'A senha precisa ter pelo menos 4 caracteres.';
    }
    return null;
  }

  Future<void> _submit() async {
    setState(() => _tried = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    final services = AppScope.of(context);
    final email = _email.text;
    final password = _password.text;
    // A senha não fica guardada em memória de widget nem em lugar nenhum.
    _password.clear();
    await services.signIn(email: email, password: password);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final busy = services.authenticating;
    final real = services.realMode;
    final failure = services.lastFailure;
    final c = context.cdf;
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
                  padding: EdgeInsets.only(top: CdfLayout.of(context).loginTop),
                  child: const PageIntro('Seu dia.\nSeu espaço.',
                      'Acompanhe sua presença na Casa do Futuro.', big: true),
                ),
                const FieldLabel('E-mail'),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  style: cdfText(16, color: c.ink),
                  decoration: cdfInput(context, hint: 'voce@empresa.com.br'),
                  validator: _validateEmail,
                  enabled: !busy,
                ),
                const FieldLabel('Senha'),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  style: cdfText(16, color: c.ink),
                  decoration: cdfInput(context, hint: 'Sua senha'),
                  validator: _validatePassword,
                  enabled: !busy,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (failure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: StatusBadge(failure.message,
                          tone: BadgeTone.pending, icon: Lucide.circleAlert),
                    ),
                  ),
                PrimaryButton(
                    busy ? 'Entrando…' : (real ? 'Entrar' : 'Entrar na demonstração'),
                    top: CdfLayout.of(context).formButtonTop,
                    onPressed: busy ? null : _submit),
                Note(real
                    ? 'Use a conta criada pelo RH da sua empresa. A senha não fica guardada no aparelho.'
                    : 'Use dados fictícios. Este protótipo não autentica nem envia informações.'),
              ]),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: const DemoFooter(),
    );
  }
}
