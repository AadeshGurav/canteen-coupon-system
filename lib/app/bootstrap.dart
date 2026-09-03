import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../core/app_mode.dart';
import '../core/logging.dart';

/// The process-wide singletons `main()` needs to build its [ProviderScope].
typedef AppBootstrap = ({SharedPreferences prefs, AppModeStore modeStore});

/// One-time process setup, shared by the real app and by tests.
///
/// Kept out of `main.dart` so `main()` stays a three-liner and every startup
/// side effect has an obvious home (CLAUDE.md §5).
Future<AppBootstrap> bootstrap() async {
  tzdata.initializeTimeZones(); // IANA database for meal-window resolution

  final prefs = await SharedPreferences.getInstance();

  // File logging is host-only; the host console turns it on once the mode is
  // known. Console logging is always on.
  await AppLogger.configure(toFile: false);

  return (prefs: prefs, modeStore: AppModeStore(prefs));
}

/// Injected, never read as a global (CLAUDE.md §5). Overridden in `main()` /
/// tests with the values from [bootstrap].
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw StateError('sharedPreferencesProvider must be overridden'),
);

final appModeStoreProvider = Provider<AppModeStore>(
  (_) => throw StateError('appModeStoreProvider must be overridden'),
);
