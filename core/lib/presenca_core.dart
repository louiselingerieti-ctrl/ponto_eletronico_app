/// Núcleo do app pessoal de presença — PROVA DE CONCEITO.
/// Não gera marcação oficial. O servidor simulado não é o backend real.
library;

export 'src/adapters/simulated_presence_server.dart';
export 'src/adapters/sqlite_event_queue.dart';
export 'src/application/backoff.dart';
export 'src/application/ports.dart';
export 'src/application/sync_engine.dart';
export 'src/domain/presence_event.dart';
export 'src/domain/queued_event.dart';
