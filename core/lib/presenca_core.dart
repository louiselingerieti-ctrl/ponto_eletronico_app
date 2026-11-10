/// Núcleo do app pessoal de presença — domínio e casos de uso.
///
/// Dart puro, sem `dart:io`, `dart:ffi` ou SQLite: compila para a web e para
/// o nativo. NÃO contém armazenamento: escolha explicitamente
/// - `presenca_core_native.dart` → SQLite SEMPRE cifrado (dados reais);
/// - `presenca_lab.dart` → adaptadores SIMULADOS (laboratório e testes).
///
/// PROVA DE CONCEITO: não gera marcação oficial.
library;

export 'src/application/backoff.dart';
export 'src/application/config_lifecycle.dart';
export 'src/application/persistence.dart';
export 'src/application/ports.dart';
export 'src/application/record_detection.dart';
export 'src/application/sync_engine.dart';
export 'src/domain/clock_quality.dart';
export 'src/domain/pending_policies.dart';
export 'src/domain/presence_config.dart';
export 'src/domain/presence_event.dart';
export 'src/domain/queued_event.dart';
