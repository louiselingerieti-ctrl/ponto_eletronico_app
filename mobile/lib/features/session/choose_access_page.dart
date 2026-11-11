import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/shell.dart';
import '../../shared/widgets/cdf_widgets.dart';

/// Mais de um acesso ativo: escolha explícita (nada é associado sozinho).
class ChooseAccessPage extends StatelessWidget {
  const ChooseAccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const BrandHeader(),
          Expanded(
            child: PageBody(children: [
              PageIntro('Olá, ${s.firstName}.', 'Escolha a empresa que você quer acompanhar.'),
              for (final m in s.pendingChoices)
                SecondaryButton(m.tenantName, onPressed: () => s.chooseMembership(m)),
              TextAction('Sair', onPressed: s.signOut),
            ]),
          ),
        ]),
      ),
    );
  }
}
