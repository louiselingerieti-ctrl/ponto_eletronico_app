import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fronteiras do laboratório web:
/// - só usa presenca_core / presenca_lab (nunca o armazenamento nativo);
/// - não importa dart:io/ffi nem pacotes de localização, HTTP ou geofence;
/// - não usa a API de geolocalização do navegador.
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('não importa armazenamento nativo, IO, rede ou localização', () {
    final forbidden = RegExp(
        r"import '(package:presenca_core/presenca_core_native\.dart|dart:io|dart:ffi|"
        r"package:http|package:dio|package:geolocator|package:location|package:geofenc|"
        r"package:web/|dart:html|dart:js)");
    for (final f in files) {
      expect(forbidden.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });

  test('não usa geolocalização do navegador', () {
    for (final f in files) {
      expect(f.readAsStringSync().contains('geolocation'), isFalse, reason: f.path);
    }
  });

  test('pubspec só depende do flutter e do core', () {
    final deps = File('pubspec.yaml')
        .readAsStringSync()
        .split('dev_dependencies:')
        .first
        .split('dependencies:')
        .last;
    for (final bad in ['geolocator', 'location', 'http', 'dio', 'geofenc', 'google_fonts']) {
      expect(deps.contains(bad), isFalse, reason: bad);
    }
  });
}
