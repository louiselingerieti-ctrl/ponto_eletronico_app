import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/cdf_widgets.dart';
import '../permissions/permissions_page.dart';

/// Só as áreas autorizadas ao vínculo (aqui, fictícias). Sem mapa contínuo.
class AreasPage extends StatelessWidget {
  const AreasPage({super.key});

  @override
  Widget build(BuildContext context) {
    final b = AppScope.backendOf(context);
    final cfg = b.areaConfig;
    return PageBody(children: [
      const PageIntro('Minhas áreas', 'Locais autorizados pela sua empresa'),
      const DemoDataNotice(),
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: H2(b.profile.areaLabel)),
            Icon(Lucide.mapPin, size: CdfSize.icon, color: context.cdf.ink),
          ]),
          BodyText(b.profile.company, top: 10),
          const Divider1(),
          StatusBadge(cfg.label,
              tone: cfg.ok ? BadgeTone.ok : BadgeTone.pending,
              icon: cfg.ok ? null : Lucide.circleAlert),
          const BodyText('A detecção pode ocorrer ao entrar ou sair desta área. '
              'O sistema do celular pode atrasar os avisos.', top: 16),
        ]),
      ),
      SecondaryButton('Ver permissões do celular',
          top: 0,
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const PermissionsPage()))),
      const Note('Você recebe somente as áreas autorizadas para seu vínculo. '
          'Este app não apresenta um mapa de localização contínua.'),
    ]);
  }
}
