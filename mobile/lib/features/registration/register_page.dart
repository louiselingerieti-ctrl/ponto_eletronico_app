import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/shell.dart';
import '../../shared/format/dates_pt.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/cdf_widgets.dart';
import '../punch/punch_models.dart';
import 'registration_controller.dart';
import 'registration_models.dart';

/// + Registrar: 1. localização → 2. foto → 3. Entrada/Saída e confirmação.
/// Cada etapa só aparece depois da anterior. O menu mantém "Registrar"
/// selecionado em todas elas.
class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final r = AppScope.of(context).registration;
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) => PageBody(children: _content(context, r)),
    );
  }

  List<Widget> _content(BuildContext context, RegistrationController r) {
    final sim = r.simulated;
    if (r.port == null) {
      return const [
        PageIntro('Registrar ponto', 'Localização, foto e confirmação.'),
        Note('O registro de ponto não está disponível nesta versão do app.'),
      ];
    }
    switch (r.step) {
      case RegStep.idle:
        return [
          const PageIntro('Registrar ponto', 'Primeiro, vamos conferir o local do registro.'),
          const _Steps(current: 1),
          PrimaryButton('Começar registro', top: 0, onPressed: r.begin),
          const Note('A localização é conferida na hora, depois vem a foto e, por último, a escolha entre Entrada e Saída.'),
        ];

      case RegStep.locating:
        return [
          const PageIntro('Validando localização', 'Primeiro, vamos conferir o local do registro.'),
          const _Steps(current: 1),
          _Panel(
            icon: Lucide.locateFixed,
            title: 'Conferindo sua posição…',
            message: 'Aguarde a verificação de uma área autorizada.',
            children: [
              if (sim)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: StatusBadge('Validação simulada em andamento', tone: BadgeTone.pending, small: true, alignment: Alignment.center),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3))),
                ),
            ],
          ),
          Note(sim
              ? 'Usaremos uma localização atual para este registro, separada da última detecção automática.'
              : 'Usaremos uma localização atual para este registro, separada da última detecção automática. Se o celular perguntar, permita o acesso à localização.'),
        ];

      case RegStep.locationFailed:
        final f = r.locationFailure!;
        final outside = f == LocationFailure.outside && r.nearestDistanceM != null
            ? ' Você está a ${_distance(r.nearestDistanceM!)} de ${r.nearestArea}.'
            : '';
        return [
          const PageIntro('Não foi possível continuar', 'Valide o local antes de tirar a foto.'),
          const _Steps(current: 1),
          _Panel(
            icon: Lucide.mapPinOff,
            title: f.title,
            message: '${f.message}$outside',
            live: true,
            children: [PrimaryButton('Tentar novamente', onPressed: r.begin)],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextAction('Relatar um problema', onPressed: () => AppShell.of(context).openNewRequest()),
          ),
        ];

      case RegStep.photo:
      case RegStep.capturing:
        final busy = r.step == RegStep.capturing;
        final cameraOff = r.photoProblem == SelfieProblem.unavailable;
        return [
          const PageIntro('Agora, tire sua foto', 'Enquadre seu rosto para continuar.'),
          const _Steps(current: 2),
          _Evidence(icon: Lucide.mapPinCheck, title: 'Localização validada', subtitle: '${r.location!.areaName} · consulta deste registro'),
          if (cameraOff)
            _Panel(
              icon: Lucide.cameraOff,
              title: 'Câmera indisponível',
              message: 'Permita o uso da câmera para tirar a foto. Sem foto, o ponto não pode ser registrado.',
              live: true,
              children: [SecondaryButton(busy ? 'Abrindo a câmera…' : 'Tentar novamente', onPressed: busy ? null : r.takePhoto)],
            )
          else ...[
            _Frame(caption: sim ? 'Prévia ilustrativa da câmera frontal' : 'A câmera frontal abre ao tocar no botão'),
            if (r.photoProblem != null || r.commitError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: StatusBadge((r.photoProblem?.message ?? r.commitError)!, tone: BadgeTone.pending, icon: Lucide.circleAlert),
                ),
              ),
            _IconButton(
              icon: Lucide.camera,
              label: busy ? 'Abrindo a câmera…' : (sim ? 'Tirar foto (simulação)' : 'Tirar foto'),
              onPressed: busy ? null : r.takePhoto,
            ),
          ],
          Note(sim
              ? 'Nenhuma câmera real é aberta. A foto é uma etapa do registro; este protótipo não executa reconhecimento facial.'
              : 'A foto vai com o ponto e pode ser vista por você e pelo RH. O app só confere se há um rosto na foto; não faz reconhecimento facial.'),
          _CancelLink(onPressed: () => _cancel(context, r)),
        ];

      case RegStep.review:
        return [
          const PageIntro('Confira sua foto', 'Você pode refazer antes de continuar.'),
          const _Steps(current: 2),
          _Frame(caption: sim ? 'Foto capturada · ilustração' : 'Foto capturada', photo: r.photo, accepted: true),
          PrimaryButton('Usar esta foto', onPressed: r.usePhoto),
          SecondaryButton('Tirar outra foto', onPressed: r.takePhoto),
          const Note('Sua localização já foi validada. Nenhum ponto foi salvo ainda.'),
        ];

      case RegStep.choose:
        final suggested = r.location!.suggested;
        return [
          const PageIntro('Registrar ponto', 'Local validado e foto capturada.'),
          const _Steps(current: 3),
          Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Evidence(icon: Lucide.mapPinCheck, title: r.location!.areaName, subtitle: 'Localização validada', inSurface: true),
              const _Evidence(icon: Lucide.camera, title: 'Foto capturada', subtitle: 'Associada a este registro', inSurface: true),
              const Divider1(),
              const H2('Qual registro deseja fazer?', size: 18),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _KindTile(kind: PunchKind.entry, hint: 'Início ou retorno', onTap: () => r.choose(PunchKind.entry))),
                const SizedBox(width: 12),
                Expanded(child: _KindTile(kind: PunchKind.exit, hint: 'Intervalo ou término', onTap: () => r.choose(PunchKind.exit))),
              ]),
              if (suggested != null) Muted('Pela sequência de hoje, o próximo previsto é a ${suggested.lower}.', top: 12),
            ]),
          ),
          _CancelLink(onPressed: () => _cancel(context, r)),
        ];

      case RegStep.confirm:
      case RegStep.committing:
        final k = r.kind!;
        final busy = r.step == RegStep.committing;
        final now = r.port!.now();
        final name = AppScope.of(context).fullName;
        return [
          PageIntro('Confirmar ${k.lower}', 'Confira os dados do seu ponto.'),
          const _Steps(current: 3),
          Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _IconTile(icon: k == PunchKind.entry ? Lucide.logIn : Lucide.logOut),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    H2(k.label, size: 22),
                    Muted('${DatesPt.numeric(now)} · ${DatesPt.hm(now)}', top: 3),
                  ]),
                ),
              ]),
              const Divider1(),
              _Evidence(icon: Lucide.mapPinCheck, title: r.location!.areaName, subtitle: 'Localização validada nesta sessão', inSurface: true),
              _Evidence(icon: Lucide.camera, title: 'Foto capturada', subtitle: '${name.isEmpty ? 'Você' : name} · este registro', inSurface: true),
              if (r.commitError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(liveRegion: true, child: StatusBadge(r.commitError!, tone: BadgeTone.pending, icon: Lucide.circleAlert)),
                ),
              PrimaryButton(
                busy ? 'Registrando…' : '${r.commitError != null && r.recovery == CommitRecovery.retry ? 'Tentar de novo: confirmar' : 'Confirmar'} ${k.lower}${sim ? ' (simulação)' : ''}',
                onPressed: busy ? null : r.confirm,
              ),
              if (!busy)
                Align(alignment: Alignment.centerLeft, child: TextAction('Alterar tipo de registro', onPressed: r.changeKind)),
            ]),
          ),
          Note(sim
              ? 'O horário definitivo será obtido no momento da gravação. Horário e evidências desta prévia são fictícios.'
              : 'O horário oficial é o do servidor, no momento em que você confirmar.'),
        ];

      case RegStep.done:
        final rc = r.receipt!;
        final t = rc.recordedAt.toLocal();
        final verb = rc.kind == PunchKind.entry ? 'Entrada' : 'Saída';
        return [
          const SizedBox(height: 24),
          Center(child: Icon(Lucide.circleCheck, size: 44, color: rc.received ? context.cdf.success : context.cdf.sub)),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(rc.received ? '$verb registrada' : '$verb salva no aparelho',
                textAlign: TextAlign.center, style: cdfText(28, weight: 650, color: context.cdf.ink, height: 1.2)),
          ),
          const SizedBox(height: 8),
          Text('${DatesPt.numeric(t)} · ${DatesPt.hm(t)}${rc.received ? ' · horário do servidor' : ' · demonstração'}',
              textAlign: TextAlign.center, style: cdfText(14, color: context.cdf.sub)),
          const SizedBox(height: 8),
          Text(rc.received ? 'Localização e foto associadas a este registro em ${rc.areaName}.' : 'Localização e foto associadas a este registro simulado.',
              textAlign: TextAlign.center, style: cdfText(14, color: context.cdf.sub, height: 1.5)),
          const SizedBox(height: 16),
          rc.received
              ? const StatusBadge('Recebido pelo servidor', tone: BadgeTone.ok, icon: Lucide.check, alignment: Alignment.center)
              : const StatusBadge('Aguardando envio', tone: BadgeTone.pending, icon: Lucide.cloudOff, alignment: Alignment.center),
          if (rc.serverNote != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(rc.serverNote!, textAlign: TextAlign.center, style: cdfText(13, color: context.cdf.sub, height: 1.5))),
          PrimaryButton('Ver no histórico', top: 24, onPressed: () {
            r.leave();
            AppShell.of(context).goTab(AppTab.history);
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextAction('Voltar ao início', onPressed: () {
              r.leave();
              AppShell.of(context).goTab(AppTab.home);
            }),
          ),
          Note(rc.received
              ? 'Recebido significa que o servidor guardou o ponto. A apuração da jornada é feita pela empresa.'
              : 'Gravação e envio são etapas diferentes. Nenhum ponto real foi registrado nesta prévia.'),
        ];
    }
  }

  static void _cancel(BuildContext context, RegistrationController r) {
    r.cancel();
    AppShell.of(context).goTab(AppTab.home);
  }

  static String _distance(int m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km' : '$m m';
}

/// 1 Localização · 2 Foto · 3 Ponto.
class _Steps extends StatelessWidget {
  const _Steps({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    const names = ['Localização', 'Foto', 'Ponto'];
    return Semantics(
      label: 'Etapa $current de 3: ${names[current - 1]}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(children: [
          for (var i = 1; i <= 3; i++) ...[
            if (i > 1) const Spacer(),
            _StepDot(n: i, label: names[i - 1], done: i < current, active: i == current),
          ],
        ]),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.n, required this.label, required this.done, required this.active});
  final int n;
  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    final bg = active ? c.orange : (done ? c.successBg : c.paper);
    final fg = active ? c.onOrange : (done ? c.success : c.sub);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: active ? null : Border.all(color: c.line)),
        alignment: Alignment.center,
        child: done ? Icon(Lucide.check, size: 14, color: fg) : Text('$n', style: cdfText(12, weight: 650, color: fg)),
      ),
      const SizedBox(width: 8),
      Text(label, style: cdfText(13, weight: active ? 700 : 400, color: active ? c.ink : c.sub)),
    ]);
  }
}

/// Cartão central de estado (ícone, título, texto e ações).
class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, required this.message, this.children = const [], this.live = false});
  final IconData icon;
  final String title;
  final String message;
  final List<Widget> children;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 8),
        Center(child: _IconTile(icon: icon, size: 72)),
        const SizedBox(height: 18),
        Semantics(
          liveRegion: live,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, textAlign: TextAlign.center, style: cdfText(17, weight: 700, color: c.ink)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: cdfText(14, color: c.sub, height: 1.5)),
          ]),
        ),
        ...children,
      ]),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, this.size = 56});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.orangeSoft, borderRadius: BorderRadius.circular(size / 3.5)),
      alignment: Alignment.center,
      child: Icon(icon, size: size * .4, color: c.orange),
    );
  }
}

/// Evidência já conferida nesta sessão (com ✓).
class _Evidence extends StatelessWidget {
  const _Evidence({required this.icon, required this.title, required this.subtitle, this.inSurface = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool inSurface;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Semantics(
      label: '$title, $subtitle, conferido',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: inSurface ? 12 : 16),
        child: Row(children: [
          Icon(icon, size: CdfSize.icon, color: c.success),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: cdfText(14, weight: 650, color: c.ink)),
              const SizedBox(height: 2),
              Text(subtitle, style: cdfText(12, color: c.sub)),
            ]),
          ),
          Icon(Lucide.check, size: CdfSize.icon, color: c.success),
        ]),
      ),
    );
  }
}

/// Moldura da câmera frontal: guia oval; depois da captura, a foto (ou a
/// ilustração da demonstração).
class _Frame extends StatelessWidget {
  const _Frame({required this.caption, this.photo, this.accepted = false});
  final String caption;
  final CapturedPhoto? photo;
  final bool accepted;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    final bytes = photo?.bytes;
    return Semantics(
      image: true,
      label: bytes != null ? 'Sua foto' : caption,
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: 1.25,
        child: Container(
          decoration: BoxDecoration(color: Color.lerp(c.bg, c.line, .9), borderRadius: BorderRadius.circular(CdfSize.radiusSurface)),
          clipBehavior: Clip.antiAlias,
          child: Stack(alignment: Alignment.center, children: [
            if (bytes != null)
              Positioned.fill(
                child: Image.memory(bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    // Foto que o aparelho não consegue mostrar: fica só o aviso.
                    errorBuilder: (context, _, _) => Icon(Lucide.camera, size: 40, color: c.sub)),
              )
            else
              LayoutBuilder(builder: (context, box) {
                final h = box.maxHeight * .72;
                return Container(
                  width: h * .66,
                  height: h,
                  decoration: BoxDecoration(
                    border: Border.all(color: accepted ? c.success : c.orange, width: 2),
                    borderRadius: BorderRadius.all(Radius.elliptical(h * .33, h * .5)),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Lucide.userRound, size: h * .38, color: c.sub),
                );
              }),
            Positioned(
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: bytes == null ? null : BoxDecoration(color: c.paper.withValues(alpha: .85), borderRadius: BorderRadius.circular(8)),
                child: Text(caption, style: cdfText(12, color: c.sub)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({required this.kind, required this.hint, required this.onTap});
  final PunchKind kind;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Semantics(
      button: true,
      label: '${kind.label}: $hint',
      excludeSemantics: true,
      child: Material(
        color: c.orangeSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.orange.withValues(alpha: .18)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(kind == PunchKind.entry ? Lucide.logIn : Lucide.logOut, size: 26, color: c.orange),
                const SizedBox(height: 12),
                Text(kind.label, style: cdfText(18, weight: 650, color: c.ink)),
                const SizedBox(height: 6),
                Text(hint, textAlign: TextAlign.center, style: cdfText(12, color: c.sub)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão principal com ícone (ex.: câmera).
class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.cdf;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: CdfSize.icon),
          label: Text(label, textAlign: TextAlign.center),
          style: FilledButton.styleFrom(
            backgroundColor: c.orange,
            foregroundColor: c.onOrange,
            disabledBackgroundColor: c.orange.withValues(alpha: .45),
            disabledForegroundColor: c.onOrange.withValues(alpha: .7),
            minimumSize: const Size.fromHeight(CdfSize.minTouch),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CdfSize.radiusButton)),
            textStyle: cdfText(15, weight: 700),
          ),
        ),
      ),
    );
  }
}

class _CancelLink extends StatelessWidget {
  const _CancelLink({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.centerLeft, child: TextAction('Cancelar registro', onPressed: onPressed));
}
