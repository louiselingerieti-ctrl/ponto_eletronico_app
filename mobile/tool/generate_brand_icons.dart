// Gera o ícone do app e a imagem da tela de abertura (Android) a partir da
// marca Casa do Futuro (mesma geometria de PORTAL/public/brand-mark.svg):
// círculo laranja #FF5A1F, "C" preto e ponta branca, numa caixa de 240.
//
// Rodar (de mobile/):  flutter test tool/generate_brand_icons.dart
// Não faz parte da suíte de testes; só (re)gera os PNGs em android/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const orange = Color(0xFFFF5A1F);
const black = Color(0xFF111214);
const white = Color(0xFFFFFFFF);

Path _c() => Path()
  ..moveTo(88, 50)
  ..lineTo(153, 50)
  ..lineTo(153, 73)
  ..lineTo(90, 73)
  ..lineTo(90, 120)
  ..lineTo(153, 120)
  ..lineTo(153, 143)
  ..lineTo(69, 143)
  ..lineTo(69, 62)
  ..close();

Path _tip() => Path()
  ..moveTo(71, 140)
  ..lineTo(92, 140)
  ..lineTo(71, 185)
  ..close();

/// Desenha a marca na escala [s] (px por unidade do SVG), com o centro do
/// círculo (120, 120) em [center].
void _paint(Canvas canvas, double s, Offset center, {required bool circle}) {
  canvas.save();
  canvas.translate(center.dx - 120 * s, center.dy - 120 * s);
  canvas.scale(s);
  final p = Paint()..isAntiAlias = true;
  if (circle) canvas.drawCircle(const Offset(120, 120), 116, p..color = orange);
  canvas.drawPath(_c(), p..color = black);
  canvas.drawPath(_tip(), p..color = white);
  canvas.restore();
}

Future<void> _png(String path, int size, void Function(Canvas, double) draw) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  draw(canvas, size.toDouble());
  final img = await rec.endRecording().toImage(size, size);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  final f = File(path)..parent.createSync(recursive: true);
  f.writeAsBytesSync(data!.buffer.asUint8List());
  // ignore: avoid_print
  print('gerado $path (${size}px)');
}

void main() {
  test('gera ícones e abertura', () async {
    const res = 'android/app/src/main/res';
    const densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      for (final MapEntry(key: d, value: k) in densities.entries) {
        // Ícone clássico (Android 7 e anteriores): a marca inteira, 48 dp.
        final legacy = (48 * k).round();
        await _png('$res/mipmap-$d/ic_launcher.png', legacy, (c, n) => _paint(c, n / 240, Offset(n / 2, n / 2), circle: true));

        // Ícone adaptativo (Android 8+): frente de 108 dp, só o "C" e a ponta,
        // no tamanho que a marca tem dentro de um círculo de 72 dp. O fundo
        // laranja vem de @color/ic_launcher_background.
        final fg = (108 * k).round();
        await _png('$res/mipmap-$d/ic_launcher_foreground.png', fg, (c, n) => _paint(c, n / 108 * 72 / 232, Offset(n / 2, n / 2), circle: false));

        // Tela de abertura (Android 11 e anteriores): a marca inteira, 120 dp.
        final splash = (120 * k).round();
        await _png('$res/drawable-$d/splash_logo.png', splash, (c, n) => _paint(c, n / 240, Offset(n / 2, n / 2), circle: true));

        // Tela de abertura do Android 12+: ícone de 288 dp; o sistema mostra
        // só o círculo central de 192 dp. A marca ocupa 180 dp dele.
        final s12 = (288 * k).round();
        await _png('$res/drawable-$d/splash_icon.png', s12, (c, n) => _paint(c, n / 288 * 180 / 232, Offset(n / 2, n / 2), circle: true));
      }
    });
  });
}
