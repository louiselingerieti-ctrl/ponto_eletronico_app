import 'dart:convert';
import 'dart:io';

import 'package:presenca_core/presenca_core_native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Cifra obrigatória — verificada NO DESKTOP (Windows). Não comprova o
/// comportamento no Android/iOS (ver docs/matriz-testes-fisicos.md).
void main() {
  final t0 = DateTime.utc(2026, 11, 10, 11);
  late TempDir tmp;

  setUp(() => tmp = TempDir());
  tearDown(() => tmp.dispose());

  test('sem chave: não abre e não cria arquivo', () {
    expect(
        () => LocalStore.open(tmp.path,
            obtainKey: () => throw StateError('keystore indisponível')),
        throwsA(isA<EncryptionUnavailable>()));
    expect(File(tmp.path).existsSync(), isFalse);
  });

  test('chave errada: não abre', () {
    openStore(tmp.path).close();
    expect(() => openStore(tmp.path, seed: 99), throwsA(isA<EncryptionUnavailable>()));
  });

  test('arquivo existente em claro: recusado e não modificado', () {
    final plain = sqlite3.open(tmp.path);
    plain.execute('CREATE TABLE t (x TEXT); INSERT INTO t VALUES (\'dado\');');
    plain.close();
    final before = File(tmp.path).readAsBytesSync();
    expect(() => openStore(tmp.path), throwsA(isA<EncryptionUnavailable>()));
    expect(File(tmp.path).readAsBytesSync(), before);
  });

  test('base em memória ou URI é recusada', () {
    expect(() => LocalStore.open(':memory:', obtainKey: syntheticKey), throwsArgumentError);
    expect(() => LocalStore.open('file:x?mode=memory', obtainKey: syntheticKey),
        throwsArgumentError);
  });

  test('chave inválida é recusada; toString não expõe a chave', () {
    expect(() => EncryptionKey.fromBytes(List.filled(31, 1)), throwsArgumentError);
    expect(() => EncryptionKey.fromBytes(List.filled(32, 0)), throwsArgumentError);
    expect(syntheticKey().toString(), 'EncryptionKey(***)');
  });

  test('eventos e configuração não aparecem em claro em nenhum arquivo', () {
    final s = openStore(tmp.path);
    final e = s.queue.append(transition(Transition.enter, t0), now: t0);
    final lc = ConfigLifecycle(store: s, stamper: stamperFor(s), appVersion: 't');
    lc.persist(
        lc.receive(encode(configJson()), expectedLinkId: linkA, receivedAt: t0),
        now: t0);
    s.close();

    final files = tmp.dir.listSync().whereType<File>().toList();
    expect(files, isNotEmpty);
    for (final f in files) {
      final text = latin1.decode(f.readAsBytesSync(), allowInvalid: true);
      for (final needle in [
        'SQLite format 3', e.eventId, 'area_transition', 'Unidade Sintética',
        'Unidade Sint', linkA, 'cfg-1',
      ]) {
        expect(text.contains(needle), isFalse, reason: '${f.path}: $needle');
      }
    }
    final again = openStore(tmp.path);
    expect(again.queue.all().single.eventId, e.eventId);
    expect(again.configs.current(linkA), isNotNull);
    again.close();
  });

  test('evento gravado é imutável e não pode ser apagado', () {
    final s = openStore(tmp.path);
    final e = s.queue.append(transition(Transition.enter, t0), now: t0);
    expect(() => s.db.execute('UPDATE outbox SET payload = ? WHERE event_id = ?',
        ['{}', e.eventId]), throwsA(isA<SqliteException>()));
    expect(() => s.db.execute('UPDATE outbox SET seq = 99 WHERE event_id = ?',
        [e.eventId]), throwsA(isA<SqliteException>()));
    expect(() => s.db.execute('DELETE FROM outbox'), throwsA(isA<SqliteException>()));
    expect(s.queue.all().single.payloadJson, e.payloadJson);
    s.close();
  });

  test('base de versão de esquema sem migração é recusada com mensagem clara', () {
    final s = openStore(tmp.path);
    s.db.execute("UPDATE meta SET value = '1' WHERE key = 'schema_version'");
    s.close();
    expect(() => openStore(tmp.path),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('sem migração'))));
  });

  test('falha dentro da transação não deixa gravação parcial', () {
    final s = openStore(tmp.path);
    expect(
        () => s.db.tx(() {
              s.queue.append(transition(Transition.enter, t0), now: t0);
              throw StateError('falha simulada');
            }),
        throwsStateError);
    expect(s.queue.all(), isEmpty);
    // A sequência também não avançou.
    expect(s.queue.append(transition(Transition.enter, t0), now: t0)
        .installationSequence, 1);
    s.close();
  });
}
