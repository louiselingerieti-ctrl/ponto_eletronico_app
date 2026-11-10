import 'dart:math';

/// Backoff exponencial com "full jitter" e teto. Valores PROVISÓRIOS da prova
/// de conceito; os definitivos dependem de bateria e da política offline.
class Backoff {
  Backoff({
    this.base = const Duration(seconds: 5),
    this.cap = const Duration(minutes: 30),
    Random? random,
  }) : _random = random ?? Random.secure();

  final Duration base;
  final Duration cap;
  final Random _random;

  /// [attempt] começa em 1. [retryAfter] do servidor é piso, nunca ignorado.
  Duration delay(int attempt, {Duration? retryAfter}) {
    final exp = base * pow(2, min(attempt - 1, 20)).toInt();
    final ceiling = exp > cap ? cap : exp;
    final jittered = Duration(
        milliseconds: (_random.nextDouble() * ceiling.inMilliseconds).round());
    if (retryAfter != null && retryAfter > jittered) return retryAfter;
    return jittered;
  }
}
