import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/cdf_widgets.dart';
import '../permissions/permissions_page.dart';
import '../punch/punch_models.dart';

/// Só as áreas autorizadas ao vínculo. No modo real, as que o servidor
/// informa (nome e raio, sem coordenadas); na demonstração, fictícias.
/// Abre pelo Início ou pelo Perfil, com Início selecionado. Sem mapa contínuo.
class AreasPage extends StatelessWidget {
  const AreasPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final punch = s.punch;
    final children = <Widget>[const PageIntro('Minhas áreas', 'Locais autorizados pela sua empresa')];
    if (punch != null) {
      children.add(ListenableBuilder(
        listenable: punch,
        builder: (context, _) {
          final a = punch.attendance;
          final pairs = a == null ? const <(String, WorkArea)>[] : [for (final l in a.links) for (final w in l.areas) (l.companyName, w)];
          if (a == null) return Note(punch.loading ? 'Buscando suas áreas…' : (punch.error?.message ?? 'Não foi possível buscar suas áreas.'));
          if (pairs.isEmpty) {
            return const Surface(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                StatusBadge('Nenhuma área cadastrada', tone: BadgeTone.pending, icon: Lucide.circleAlert),
                BodyText('A empresa ainda não cadastrou a área de trabalho. Sem ela não é possível validar o local nem registrar o ponto. Procure o RH.', top: 12),
              ]),
            );
          }
          return Column(children: [
            for (final (company, w) in pairs)
              Surface(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: H2(w.name)),
                    Icon(Lucide.mapPin, size: CdfSize.icon, color: context.cdf.ink),
                  ]),
                  BodyText(company, top: 10),
                  const Divider1(),
                  const StatusBadge('Cadastrada pela empresa', tone: BadgeTone.ok, icon: Lucide.check),
                  BodyText('Para registrar o ponto, você precisa estar a até ${w.radiusM} m do centro desta área.', top: 16),
                ]),
              ),
          ]);
        },
      ));
    } else {
      final b = s.backend;
      final cfg = b.areaConfig;
      children.addAll([
        const DemoDataNotice(),
        Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: H2(b.profile.areaLabel)),
              Icon(Lucide.mapPin, size: CdfSize.icon, color: context.cdf.ink),
            ]),
            BodyText(b.profile.company, top: 10),
            const Divider1(),
            StatusBadge(cfg.label, tone: cfg.ok ? BadgeTone.ok : BadgeTone.pending, icon: cfg.ok ? Lucide.check : Lucide.circleAlert),
            const BodyText('A detecção pode ocorrer ao entrar ou sair desta área. O sistema do celular pode atrasar os avisos.', top: 16),
          ]),
        ),
      ]);
    }
    children.addAll([
      SecondaryButton('Ver permissões do celular',
          top: 0, onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PermissionsPage()))),
      Align(
        alignment: Alignment.centerLeft,
        child: TextAction('Voltar ao início', onPressed: () => Navigator.of(context).maybePop()),
      ),
      const Note('Você recebe somente as áreas autorizadas para seu vínculo. Este app não apresenta um mapa de localização contínua.'),
    ]);
    return Scaffold(body: PageBody(onRefresh: s.refresh, children: children));
  }
}
