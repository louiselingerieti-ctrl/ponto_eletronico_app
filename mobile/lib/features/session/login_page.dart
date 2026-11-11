import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/shell.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/layout/cdf_layout.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/cdf_widgets.dart';

/// Login. No modo real autentica no backend (senha ou Google, este só quando
/// o build informa o client ID); na demonstração não autentica nem valida. A
/// senha nunca é guardada.
/// Recuperação de senha não tem tela aprovada.
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

  /// Login pelo Google não usa o formulário: a senha digitada é descartada e
  /// os avisos de campo ("Informe a senha.") somem, para não parecer que o
  /// Google está pedindo senha.
  void _startGoogle(AppServices services) {
    final email = _email.text;
    setState(() => _tried = false);
    _form.currentState?.reset();
    _email.text = email;
    _password.clear();
    services.signInWithGoogle();
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
                if (services.googleAvailable) ...[
                  const _OrDivider(),
                  _GoogleButton(
                      busy: busy,
                      onPressed: busy
                          ? null
                          : () {
                              _startGoogle(services);
                            }),
                ],
                Note(real
                    ? (services.googleAvailable
                        ? 'Use a conta criada pelo RH da sua empresa. O Google só funciona para o e-mail já cadastrado. A senha não fica guardada no aparelho.'
                        : 'Use a conta criada pelo RH da sua empresa. A senha não fica guardada no aparelho.')
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

/// Separador "ou" entre o login por senha e o login pelo Google.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ExcludeSemantics(
        child: Row(children: [
          Expanded(child: Divider(color: c.line, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('ou', style: cdfText(13, color: c.sub)),
          ),
          Expanded(child: Divider(color: c.line, height: 1)),
        ]),
      ),
    );
  }
}

/// Botão "Entrar com Google" no padrão da marca do Google: fundo neutro,
/// o "G" colorido original e texto escuro (no tema escuro, o inverso).
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: c.paper,
            foregroundColor: c.ink,
            disabledForegroundColor: c.sub,
            side: BorderSide(color: c.line),
            minimumSize: const Size.fromHeight(CdfSize.minTouch),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CdfSize.radiusButton)),
            textStyle: cdfText(14, weight: 650),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Opacity(
              opacity: busy ? .5 : 1,
              child: Image.asset('assets/brand/google-g.png',
                  width: 20, height: 20, excludeFromSemantics: true),
            ),
            const SizedBox(width: 10),
            const Flexible(child: Text('Entrar com Google', textAlign: TextAlign.center)),
          ]),
        ),
      ),
    );
  }
}
