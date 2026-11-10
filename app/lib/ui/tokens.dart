import 'package:flutter/material.dart';

/// Tokens do LABORATÓRIO (identidade aprovada só para o laboratório em
/// 10/11/2026; não é a identidade do produto). Nenhuma cor literal fora daqui.
@immutable
class LabColors extends ThemeExtension<LabColors> {
  const LabColors({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.ink2,
    required this.line,
    required this.lineStrong,
    required this.amber,
    required this.amberInk,
    required this.saved,
    required this.sent,
    required this.received,
    required this.evaluated,
    required this.failure,
    required this.failureBg,
    required this.noteBg,
    required this.focus,
  });

  final Color paper, surface, ink, ink2, line, lineStrong, amber, amberInk;
  final Color saved, sent, received, evaluated, failure, failureBg, noteBg, focus;

  static const light = LabColors(
    paper: Color(0xFFF5F6F4), surface: Color(0xFFFFFFFF), ink: Color(0xFF1C2226),
    ink2: Color(0xFF55606A), line: Color(0xFFD9DDDA), lineStrong: Color(0xFFB8BEBA),
    amber: Color(0xFFE3A91A), amberInk: Color(0xFF1C2226),
    saved: Color(0xFF64748B), sent: Color(0xFF2D6BD6), received: Color(0xFF18866A),
    evaluated: Color(0xFF6B55C9), failure: Color(0xFFBF3B26), failureBg: Color(0xFFFBEDEA),
    noteBg: Color(0xFFEEF1EF), focus: Color(0xFF2D6BD6),
  );

  static const dark = LabColors(
    paper: Color(0xFF14181B), surface: Color(0xFF1C2226), ink: Color(0xFFE7EAE8),
    ink2: Color(0xFFA3ACB3), line: Color(0xFF2E363C), lineStrong: Color(0xFF465057),
    amber: Color(0xFFE3A91A), amberInk: Color(0xFF1C2226),
    saved: Color(0xFF94A3B8), sent: Color(0xFF6E9CF0), received: Color(0xFF4CC09C),
    evaluated: Color(0xFFA08CF0), failure: Color(0xFFF07A64), failureBg: Color(0xFF3A221D),
    noteBg: Color(0xFF232A2F), focus: Color(0xFF6E9CF0),
  );

  @override
  LabColors copyWith() => this;

  @override
  LabColors lerp(ThemeExtension<LabColors>? other, double t) =>
      other is LabColors && t >= .5 ? other : this;
}

/// Tokens de movimento (motion-ll).
abstract final class LabMotion {
  static const instante = Duration(milliseconds: 100);
  static const rapido = Duration(milliseconds: 160);
  static const medio = Duration(milliseconds: 220);
  static const reduzido = Duration(milliseconds: 140);
  static const saida = Cubic(0.16, 1, 0.3, 1);
}

const labFont = 'PublicSans';
const labMono = 'JetBrainsMono';

ThemeData labTheme(Brightness b) {
  final c = b == Brightness.dark ? LabColors.dark : LabColors.light;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    fontFamily: labFont,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.ink, brightness: b, surface: c.surface,
    ).copyWith(primary: c.ink, onPrimary: c.paper, outline: c.lineStrong),
    scaffoldBackgroundColor: c.paper,
    extensions: [c],
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
  final pad = const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink, minimumSize: const Size(44, 40), padding: pad, shape: shape,
        side: BorderSide(color: c.lineStrong),
        textStyle: const TextStyle(fontFamily: labFont, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.ink, foregroundColor: c.paper, minimumSize: const Size(44, 40),
        padding: pad, shape: shape,
        textStyle: const TextStyle(fontFamily: labFont, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    dividerColor: c.line,
  );
}

extension LabTheme on BuildContext {
  LabColors get lab => Theme.of(this).extension<LabColors>()!;
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}
