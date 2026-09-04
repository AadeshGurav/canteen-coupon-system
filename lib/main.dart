import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/appearance_providers.dart';
import 'app/bootstrap.dart';
import 'app/mode_gate.dart';
import 'app/providers.dart';
import 'core/app_mode.dart';
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
      child: const TiffinApp(),
    ),
  );
}

class TiffinApp extends ConsumerWidget {
  const TiffinApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Light and dark are both built and handed to MaterialApp so "system"
    // follows the OS without us watching for brightness changes ourselves.
    final appearance = ref.watch(effectiveAppearanceProvider);
    ThemeData themeFor(Brightness brightness) => buildTiffinTheme(
          appearance.theme,
          brightness,
          motion: appearance.motion,
        );

    return MaterialApp(
      title: 'Tiffin',
      debugShowCheckedModeBanner: false,
      theme: themeFor(Brightness.light),
      darkTheme: themeFor(Brightness.dark),
      themeMode: appearance.mode,
      // i18n-ready from day one (CLAUDE.md §13) even though only en ships now.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      // WithForegroundTask lets the plugin manage the app lifecycle cleanly
      // while the host-keep-alive service runs (PRD §13.3).
      home: const WithForegroundTask(child: _AppRoot()),
    );
  }
}

/// Re-arms the LAN layer whenever the app comes back to the foreground: a
/// client that was asleep re-runs discovery, a host re-checks its server is
/// up. Discovery and mDNS registration both go stale across sleep/wake and
/// Wi-Fi changes (CLAUDE.md §4.6).
class _AppRoot extends ConsumerStatefulWidget {
  const _AppRoot();

  @override
  ConsumerState<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<_AppRoot>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    switch (ref.read(currentModeProvider)) {
      case AppMode.client:
        ref.read(hostBrowserProvider).restart();
      case AppMode.host:
        ref.read(hostServingProvider.notifier).ensureStarted();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => const ModeGate();
}

/// Replaces Flutter's grey/yellow error box with something an operator can read
/// and report — the message, and (debug only) where it came from.
class _FriendlyErrorWidget extends StatelessWidget {
  const _FriendlyErrorWidget({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    // This can be asked to render above MaterialApp — i.e. with no theme at
    // all. A last-resort error screen that itself throws for want of a token
    // would replace a readable message with Flutter's red box, so it falls
    // back to fixed colours rather than asserting.
    final t = context.maybeTokens;
    final background = t?.color.warn ?? const Color(0xFFE8A317);
    final foreground = t?.color.onWarn ?? const Color(0xFF1A1A1A);
    final labelStyle = (t?.text.label ?? const TextStyle(fontSize: 13))
        .copyWith(color: foreground);
    final bodyStyle = (t?.text.body ?? const TextStyle(fontSize: 16))
        .copyWith(color: foreground);

    return Container(
      color: background,
      padding: const EdgeInsets.all(NbSpace.md),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bug_report, color: foreground, size: 40),
            const SizedBox(height: NbSpace.sm),
            Text('This screen hit a problem.',
                textAlign: TextAlign.center, style: labelStyle),
            const SizedBox(height: NbSpace.xs),
            Text(
              kReleaseMode
                  ? 'Go back and try again — it has been written to the log.'
                  : '${details.exception}',
              textAlign: TextAlign.center,
              style: bodyStyle,
            ),
          ],
        ),
      ),
    );
  }
}
