import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/session/change_password_page.dart';
import '../features/session/choose_access_page.dart';
import '../features/session/login_page.dart';
import '../shared/theme/tokens.dart';
import '../shared/widgets/cdf_widgets.dart';
import 'app_services.dart';
import 'shell.dart';

class CasaFuturoApp extends StatelessWidget {
  const CasaFuturoApp({super.key, required this.services, this.themeMode = ThemeMode.system});
  final AppServices services;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: DemoNoticeScope(
       realMode: services.realMode,
       child: MaterialApp(
        title: 'Casa do Futuro',
        debugShowCheckedModeBanner: false,
        theme: cdfTheme(Brightness.light),
        darkTheme: cdfTheme(Brightness.dark),
        themeMode: themeMode,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const _Root(),
       ),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (s.restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (s.needsPasswordChange) return const ChangePasswordPage();
    if (s.pendingChoices.isNotEmpty) return const ChooseAccessPage();
    // A chave muda a cada saída: nada da conta anterior sobrevive no shell.
    return s.signedIn ? AppShell(key: ValueKey(s.generation)) : const LoginPage();
  }
}
