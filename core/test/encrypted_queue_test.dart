import 'dart:convert';
import 'dart:io';

import 'package:presenca_core/presenca_core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Viabilidade do SQLite cifrado (SQLite3MultipleCiphers) — NO DESKTOP.
/// Não comprova o comportamento no Android/iOS: isso exige build e teste no
/// aparelho (ver docs/matriz-testes-fisicos.md).
void main() {
  // Chaves SINTÉTICAS de 32 bytes, só para teste.
  final key = '0f1e2d3c' * 8;
  final wrong = 'a1b2c3d4' * 8;
  final t0 = DateTime.utc(2026, 11, 10, 11);
  late TempDb tmp;

  setUp(() => tmp = TempDb());
  tearDown(() => tmp.dispose());

  test('arquivo cifrado: sem chave ou com chave errada não abre', () {
    final q = SqliteEventQueue.open(tmp.path, hexKey: key);
    final e = q.append(transition(Transition.enter, t0), now: t0);
    q.close();

    expect(() => SqliteEventQueue.open(tmp.path), throwsA(anything));
    expect(() => SqliteEventQueue.open(tmp.path, hexKey: wrong), throwsA(anything));

    final again = SqliteEventQueue.open(tmp.path, hexKey: key);
    expect(again.all().single.eventId, e.eventId);
    again.close();
  });

  test('conteúdo não aparece em claro nos arquivos do banco', () {
    final q = SqliteEventQueue.open(tmp.path, hexKey: key);
    final e = q.append(transition(Transition.enter, t0), now: t0);
    q.close();

    for (final f in tmp.dir.listSync().whereType<File>()) {
      final bytes = f.readAsBytesSync();
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(text.startsWith('SQLite format 3'), isFalse, reason: f.path);
      expect(text.contains(e.eventId), isFalse, reason: f.path);
      expect(text.contains('area_transition'), isFalse, reason: f.path);
    }
  });

  test('chave em formato inválido é recusada antes de abrir', () {
    expect(() => SqliteEventQueue.open(tmp.path, hexKey: "abc'; DROP"),
        throwsArgumentError);
  });
}
