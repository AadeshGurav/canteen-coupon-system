import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/bootstrap.dart';
import 'app/mode_gate.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final b = await bootstrap();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(b.prefs),
        appModeStoreProvider.overrideWithValue(b.modeStore),
      ],
      child: const CanteenApp(),
    ),
  );
}

class CanteenApp extends StatelessWidget {
  const CanteenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Canteen Coupon System',
      debugShowCheckedModeBanner: false,
      theme: buildNeobrutalismTheme(),
      // i18n-ready from day one (CLAUDE.md §13) even though only en ships now.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: const ModeGate(),
    );
  }
}
