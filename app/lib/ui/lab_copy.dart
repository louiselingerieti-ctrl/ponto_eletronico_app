import 'package:flutter/foundation.dart' show kIsWeb;

/// Textos que dependem de onde o laboratório roda. Em qualquer plataforma a
/// persistência é a MESMA: memória, sem cifra, sem disco.
abstract final class LabCopy {
  static String get where => kIsWeb ? 'deste navegador' : 'deste aparelho';

  static String get memoryChip => kIsWeb
      ? 'Memória do navegador: recarregar a página apaga tudo'
      : 'Memória do app: fechar o app apaga tudo';

  static String get memoryPlace =>
      kIsWeb ? 'na memória do navegador' : 'na memória do app';
}
