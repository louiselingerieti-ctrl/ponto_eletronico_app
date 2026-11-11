import 'package:flutter/material.dart';

import 'lab/lab_controller.dart';
import 'ui/lab_page.dart';
import 'ui/tokens.dart';

/// LABORATÓRIO WEB SIMULADO do app pessoal de presença.
/// - Não gera ponto oficial.
/// - Não pede localização real e não registra geofence.
/// - Não conecta ao backend real: o servidor é simulado.
/// - Dados só na memória do navegador: recarregar a página apaga tudo.
/// - Não valida SQLite cifrado, Keystore nem execução em segundo plano.
void main() => runApp(LabApp(controller: LabController()));

class LabApp extends StatelessWidget {
  const LabApp({super.key, required this.controller});
  final LabController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Laboratório de presença (simulado)',
      debugShowCheckedModeBanner: false,
      theme: labTheme(Brightness.light),
      darkTheme: labTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: LabPage(controller: controller),
    );
  }
}
