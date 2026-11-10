@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Guarda de fronteiras:
/// - domínio, aplicação e laboratório não importam nada nativo nem adaptador
///   (senão a web quebra ou o laboratório passa a depender do real);
/// - `presenca_core.dart` não exporta armazenamento nem simulação;
/// - só `presenca_lab.dart` exporta os adaptadores simulados.
void main() {
  final forbidden = RegExp(r"^import '(dart:io|dart:ffi|package:sqlite3|\.\./adapters/)",
      multiLine: true);

  for (final dir in ['lib/src/domain', 'lib/src/application', 'lib/src/lab']) {
    test('$dir não importa nativo nem adaptadores', () {
      for (final f in Directory(dir).listSync().whereType<File>()) {
        expect(forbidden.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });
  }

  test('presenca_core.dart só exporta domínio e aplicação', () {
    final s = File('lib/presenca_core.dart').readAsStringSync();
    expect(s.contains('src/adapters/'), isFalse);
    expect(s.contains('src/lab/'), isFalse);
  });

  test('presenca_core_native.dart não exporta o laboratório', () {
    expect(File('lib/presenca_core_native.dart').readAsStringSync().contains('src/lab/'),
        isFalse);
  });
}
