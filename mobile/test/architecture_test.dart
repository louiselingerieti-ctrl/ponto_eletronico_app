import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fronteiras:
/// - rede e armazenamento seguro SÓ em lib/integration (adaptadores reais);
/// - nada de IO nativo, localização, WebView ou armazenamento cifrado nativo
///   (presenca_core_native) por enquanto;
/// - só lib/demo conhece os adaptadores simulados (presenca_lab);
/// - telas não usam a fila do núcleo diretamente;
/// - manifesto Android: só INTERNET, nunca localização.
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
  String rel(File f) => f.path.replaceAll(r'\', '/');

  test('sem IO nativo, localização, WebView ou armazenamento nativo', () {
    final bad = RegExp(r"import '(dart:io|dart:ffi|dart:html|package:dio|package:geolocator|"
        r"package:location|package:webview|package:presenca_core/presenca_core_native)");
    for (final f in files) {
      expect(bad.hasMatch(f.readAsStringSync()), isFalse, reason: rel(f));
    }
  });

  test('HTTP e armazenamento seguro só em lib/integration', () {
    final net = RegExp(r"import 'package:(http|flutter_secure_storage)/");
    for (final f in files) {
      if (rel(f).contains('lib/integration/')) continue;
      expect(net.hasMatch(f.readAsStringSync()), isFalse, reason: rel(f));
    }
  });

  test('plugin do Google só em lib/integration/google; telas falam com a porta', () {
    for (final f in files) {
      if (rel(f).contains('lib/integration/google/')) continue;
      expect(f.readAsStringSync().contains('package:google_sign_in'), isFalse, reason: rel(f));
    }
  });

  test('client ID do Google e segredos não ficam fixos no código', () {
    for (final f in files) {
      final src = f.readAsStringSync();
      expect(RegExp(r'\d{6,}-[a-z0-9]+\.apps\.googleusercontent\.com').hasMatch(src), isFalse, reason: rel(f));
      expect(src.contains('GOCSPX-'), isFalse, reason: rel(f));
    }
  });

  test('endereço do servidor não fica fixo no código', () {
    for (final f in files) {
      expect(f.readAsStringSync().contains('margemshop'), isFalse, reason: rel(f));
    }
  });

  test('adaptadores simulados só em lib/demo', () {
    for (final f in files) {
      if (rel(f).contains('lib/demo/')) continue;
      expect(f.readAsStringSync().contains('package:presenca_core/presenca_lab'), isFalse,
          reason: rel(f));
    }
  });

  test('widgets das telas não usam a fila do núcleo diretamente', () {
    for (final f in files.where((f) => rel(f).contains('lib/features/'))) {
      expect(f.readAsStringSync().contains('package:presenca_core'), isFalse, reason: rel(f));
    }
  });

  test('manifesto Android: só INTERNET, nunca localização', () {
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final perms = RegExp(r'android:name="(android\.permission\.[A-Z_]+)"')
        .allMatches(m)
        .map((x) => x.group(1))
        .toSet();
    expect(perms, {'android.permission.INTERNET'});
    expect(m.contains('LOCATION'), isFalse);
  });

  test('não desenha relógio/bateria falsos', () {
    for (final f in files) {
      expect(f.readAsStringSync().contains('09:41'), isFalse, reason: rel(f));
    }
  });
}
