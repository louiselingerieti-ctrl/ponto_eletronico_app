import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/shell.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/widgets/cdf_widgets.dart';

/// Explica a finalidade da localização ANTES de qualquer pedido nativo.
/// Nesta demonstração a permissão é simulada: nada é solicitado ao sistema.
class PermissionsPage extends StatelessWidget {
  const PermissionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final b = AppScope.backendOf(context);
    final granted = b.locationGranted;
    return Scaffold(
      body: PageBody(children: [
        const PageIntro('Você no controle', 'Permissões para detectar presença'),
        const Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            H2('Por que usar localização?'),
            BodyText('Para identificar entradas e saídas das áreas autorizadas, '
                'inclusive quando o app estiver fechado.', top: 10),
          ]),
        ),
        SettingRow(
          icon: Lucide.locateFixed,
          title: 'Localização precisa',
          subtitle: granted ? 'Permitida nesta demonstração' : 'Permissão pendente',
        ),
        const SettingRow(
          icon: Lucide.mapPinned,
          title: 'Localização em segundo plano',
          subtitle: 'Necessária para detecção automática',
        ),
        const Note('Sem rastreamento contínuo, selfie ou reconhecimento facial. '
            'A precisão e o tempo de detecção dependem do celular.'),
        // Ferramenta de demonstração; não faz parte do produto.
        PrimaryButton(
          granted ? 'Simular permissão desativada' : 'Simular permissão habilitada',
          top: 0,
          onPressed: () => b.setLocationGranted(!granted),
        ),
        TextAction('Voltar ao início', onPressed: () => AppShell.of(context).backToHome()),
      ]),
    );
  }
}
