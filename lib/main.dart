import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/bootstrap.dart';
import 'app/mode_gate.dart';
import 'core/logging.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Required by flutter_foreground_task before any service call (PRD §13.3).
  FlutterForegroundTask.initCommunicationPort();

  // Nothing fails silently (PRD §7, CLAUDE.md §8): every uncaught framework or
  // async error is written to the log and shown as a readable panel instead of
  // the red screen of death.
  final crash = log('crash');
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    crash.severe('flutter framework error', details.exception, details.stack);
    priorOnError?.call(details);
  };
  ErrorWidget.builder = (details) => _FriendlyErrorWidget(details: details);
  PlatformDispatcher.instance.onError = (error, stack) {
    crash.severe('uncaught async error', error, stack);
    return true;
  };

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
      // WithForegroundTask lets the plugin manage the app lifecycle cleanly
      // while the host-keep-alive service runs (PRD §13.3).
      home: const WithForegroundTask(child: ModeGate()),
    );
  }
}

/// Replaces Flutter's grey/yellow error box with something an operator can read
/// and report — the message, and (debug only) where it came from.
class _FriendlyErrorWidget extends StatelessWidget {
  const _FriendlyErrorWidget({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NbColors.warn,
      padding: const EdgeInsets.all(NbSpace.md),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bug_report, color: NbColors.onWarn, size: 40),
            const SizedBox(height: NbSpace.sm),
            Text('This screen hit a problem.',
                textAlign: TextAlign.center,
                style: NbType.label.copyWith(color: NbColors.onWarn)),
            const SizedBox(height: NbSpace.xs),
            Text(
              kReleaseMode
                  ? 'Go back and try again — it has been written to the log.'
                  : '${details.exception}',
              textAlign: TextAlign.center,
              style: NbType.body.copyWith(color: NbColors.onWarn),
            ),
          ],
        ),
      ),
    );
  }
}
