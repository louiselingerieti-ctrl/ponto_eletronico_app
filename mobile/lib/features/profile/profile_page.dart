import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/shell.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/widgets/cdf_widgets.dart';
import '../delivery/delivery_widgets.dart';
import '../delivery/sync_page.dart';
import '../permissions/permissions_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _signOut(BuildContext context) async {
    final services = AppScope.of(context);
    final pending = services.backend.pendingCount;
    // Política real de saída com pendências: pendente. Aqui, os dados da
    // demonstração são descartados e nada passa para a próxima pessoa.
    final pendingPart = pending > 0
        ? 'Há ${pendingText(pending)} salvo${pending == 1 ? '' : 's'} no aparelho sem confirmação do servidor. '
        : '';
    final ok = await confirmDialog(
      context,
      title: 'Sair da conta?',
      message: services.realMode
          ? '${pendingPart}A sessão será encerrada neste aparelho e no servidor. Sem conexão, '
              'ela deixa de valer no servidor quando expirar (em até 12 horas).'
          : '${pendingPart}Nesta demonstração, sair apaga os dados fictícios deste aparelho.',
      confirm: 'Sair',
      cancel: 'Cancelar',
    );
    if (ok) await services.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final b = s.backend;
    final pending = b.pendingCount;
    void push(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    return PageBody(onRefresh: AppScope.of(context).refresh, children: [
      PageIntro('Meu perfil', s.fullName),
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          H2(s.companyName),
          // Vínculo e estabelecimento ainda não são expostos ao funcionário
          // pelo backend: no modo real, mostra só o que o servidor informou.
          Muted(s.realMode ? (s.email ?? '') : 'Vínculo ativo • ${b.profile.establishment}', top: 3),
        ]),
      ),
      SettingRow(
        icon: Lucide.mapPin,
        title: 'Áreas autorizadas',
        subtitle: 'Locais de detecção do seu vínculo',
        action: TextAction('Consultar áreas', onPressed: () => AppShell.of(context).goTab(AppTab.areas)),
      ),
      SettingRow(
        icon: Lucide.shieldCheck,
        title: 'Permissões e privacidade',
        subtitle: 'Localização e detecção em segundo plano',
        action: TextAction('Consultar', onPressed: () => push(const PermissionsPage())),
      ),
      SettingRow(
        icon: Lucide.cloudUpload,
        title: 'Sincronização',
        subtitle: pending > 0
            ? '${pendingText(pending)} salvo${pending == 1 ? '' : 's'} no aparelho'
            : 'Nenhum evento pendente',
        action: TextAction('Ver detalhes', onPressed: () => push(const SyncPage())),
      ),
      SecondaryButton('Sair da conta', onPressed: () => _signOut(context)),
      const Note('App do colaborador • demonstração visual'),
    ]);
  }
}
