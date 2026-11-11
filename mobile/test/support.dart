import 'dart:io';
import 'dart:ui' as ui;

import 'package:casa_futuro_colaborador/app/app.dart';
import 'package:casa_futuro_colaborador/app/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Horário FIXO e fictício das capturas do álbum (quarta-feira, 11/11/2026).
final demoNow = DateTime(2026, 11, 11, 9, 41);

Future<void> loadAppFonts() async {
  Future<void> load(String family, String asset) async {
    final l = FontLoader(family)..addFont(rootBundle.load(asset));
    await l.load();
  }

  await load('PublicSans', 'assets/fonts/PublicSans-wght.ttf');
  await load('Lucide', 'assets/icons/lucide.ttf');
}

final rootKey = GlobalKey();

Future<AppServices> pumpApp(
  WidgetTester t, {
  Size size = const Size(400, 860),
  bool dark = false,
  bool signedIn = true,
  double textScale = 1,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    t.view.reset();
    t.platformDispatcher.clearTextScaleFactorTestValue();
  });
  final s = AppServices(now: () => demoNow, signedIn: signedIn);
  addTearDown(s.dispose);
  await t.pumpWidget(RepaintBoundary(
    key: rootKey,
    child: CasaFuturoApp(services: s, themeMode: dark ? ThemeMode.dark : ThemeMode.light),
  ));
  await t.pumpAndSettle();
  return s;
}

Finder navItem(String label) => find.bySemanticsLabel(label);

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text);
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
  await t.tap(f.first);
  await t.pumpAndSettle();
}

Future<void> tapNav(WidgetTester t, String label) async {
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

/// Grava um PNG (2x) do app inteiro em build/screenshots/(nome).png.
Future<void> capture(WidgetTester t, String name) async {
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      final w = e.widget as Image;
      await precacheImage(w.image, e);
    }
  });
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final boundary = rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image img = await boundary.toImage(pixelRatio: 2);
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('build/screenshots/$name.png');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(data!.buffer.asUint8List());
  });
}
