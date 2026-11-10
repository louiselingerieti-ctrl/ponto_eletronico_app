/// ================================================================
///  LABORATÓRIO — adaptadores SIMULADOS. Não usar no app real.
/// ================================================================
/// - `InMemoryLabPersistence`: em memória, SEM cifra e SEM disco;
/// - `SimulatedPresenceServer`: imita o rascunho `presenca-v1`; não é o
///   backend.
/// Compila para a web. Nada daqui valida SQLite cifrado, Keystore,
/// geofence ou execução em segundo plano.
library;

export 'presenca_core.dart';
export 'src/lab/in_memory_lab_persistence.dart';
export 'src/lab/simulated_presence_server.dart';
