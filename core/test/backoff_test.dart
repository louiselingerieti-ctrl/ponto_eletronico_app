import 'package:presenca_core/presenca_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('backoff respeita o teto', () {
    final b = deterministicBackoff();
    expect(b.delay(1), const Duration(seconds: 5));
    expect(b.delay(2), const Duration(seconds: 10));
    expect(b.delay(30), const Duration(minutes: 30));
    expect(b.delay(1000), const Duration(minutes: 30));
  });

  test('Retry-After é piso', () {
    final b = deterministicBackoff();
    expect(b.delay(1, retryAfter: const Duration(minutes: 2)),
        const Duration(minutes: 2));
  });

  test('jitter fica entre zero e o teto exponencial', () {
    final b = Backoff();
    for (var i = 0; i < 200; i++) {
      final d = b.delay(3);
      expect(d >= Duration.zero && d <= const Duration(seconds: 20), isTrue);
    }
  });
}
