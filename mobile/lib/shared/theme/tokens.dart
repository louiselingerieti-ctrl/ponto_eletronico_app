import 'package:flutter/material.dart';

/// Tokens da identidade Casa do Futuro (relatório v1.0, seção 4).
/// Nenhuma cor literal fora deste arquivo.
@immutable
class CdfColors extends ThemeExtension<CdfColors> {
  const CdfColors({
    required this.bg,
    required this.paper,
    required this.ink,
    required this.sub,
    required this.line,
    required this.successBg,
    required this.success,
    required this.orangeSoft,
    required this.warn,
  });

  final Color bg, paper, ink, sub, line, successBg, success, orangeSoft, warn;

  /// Laranja da marca: ação central e ação principal (igual nos dois temas).
  Color get orange => const Color(0xFFF36B39);

  /// Texto sobre o laranja.
  Color get onOrange => const Color(0xFF251B15);

  static const light = CdfColors(
    bg: Color(0xFFF4F5F6),
    paper: Color(0xFFFFFFFF),
    ink: Color(0xFF252624),
    sub: Color(0xFF646B68),
    line: Color(0xFFE6E9E7),
    successBg: Color(0xFFEAF4EE),
    success: Color(0xFF28633C),
    orangeSoft: Color(0xFFFFF0E9),
    warn: Color(0xFF875017),
  );

  static const dark = CdfColors(
    bg: Color(0xFF171918),
    paper: Color(0xFF232624),
    ink: Color(0xFFF4F5F2),
    sub: Color(0xFFB2BCB6),
    line: Color(0xFF3B423D),
    successBg: Color(0xFF243C2D),
    success: Color(0xFF9FDBAC),
    orangeSoft: Color(0xFF412C22),
    warn: Color(0xFFF4C58C),
  );

  @override
  CdfColors copyWith() => this;

  @override
  CdfColors lerp(ThemeExtension<CdfColors>? other, double t) =>
      other is CdfColors && t >= .5 ? other : this;
}

const cdfFont = 'PublicSans';

/// Estilo de texto com peso real da fonte variável (eixo `wght`).
/// Pesos do protótipo: 400, 600, 650, 700.
TextStyle cdfText(
  double size, {
  double weight = 400,
  Color? color,
  double? height,
  double? spacing,
  TextDecoration? decoration,
}) =>
    TextStyle(
      fontFamily: cdfFont,
      fontSize: size,
      fontWeight: weight >= 650
          ? FontWeight.w700
          : weight >= 600
              ? FontWeight.w600
              : FontWeight.w400,
      // A Public Sans parece mais leve que a Segoe UI do protótipo: o 650 é
      // aproximado com 700 (relatório v1.0, seção 4).
      fontVariations: [FontVariation('wght', weight == 650 ? 700 : weight)],
      color: color,
      height: height,
      letterSpacing: spacing,
      decoration: decoration,
      decorationColor: color,
    );

/// Medidas do protótipo (logical pixels).
abstract final class CdfSize {
  static const radiusSurface = 20.0;
  static const radiusButton = 14.0;
  static const radiusField = 12.0;
  static const surfacePadding = 20.0;
  static const minTouch = 48.0;
  static const icon = 20.0;
  // Margens e escala que variam com o dispositivo: ver CdfLayout.
}

ThemeData cdfTheme(Brightness b) {
  final c = b == Brightness.dark ? CdfColors.dark : CdfColors.light;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    fontFamily: cdfFont,
    scaffoldBackgroundColor: c.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.orange,
      brightness: b,
      surface: c.paper,
    ).copyWith(
      primary: c.orange,
      onPrimary: c.onOrange,
      onSurface: c.ink,
      outline: c.line,
      error: b == Brightness.dark ? const Color(0xFFFF9C86) : const Color(0xFFB3261E),
    ),
    extensions: [c],
  );
  OutlineInputBorder border(Color color, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(CdfSize.radiusField),
        borderSide: BorderSide(color: color, width: w),
      );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: cdfFont, bodyColor: c.ink, displayColor: c.ink),
    dividerColor: c.line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.paper,
      contentPadding: const EdgeInsets.all(14),
      hintStyle: cdfText(16, color: c.sub),
      border: border(c.line),
      enabledBorder: border(c.line),
      focusedBorder: border(c.orange, 2),
      errorBorder: border(base.colorScheme.error),
      focusedErrorBorder: border(base.colorScheme.error, 2),
      errorStyle: cdfText(12, color: base.colorScheme.error),
    ),
    datePickerTheme: DatePickerThemeData(backgroundColor: c.paper),
    timePickerTheme: TimePickerThemeData(backgroundColor: c.paper),
    dialogTheme: DialogThemeData(backgroundColor: c.paper),
  );
}

extension CdfContext on BuildContext {
  CdfColors get cdf => Theme.of(this).extension<CdfColors>()!;
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}
