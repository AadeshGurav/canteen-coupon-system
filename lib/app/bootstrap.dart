import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../core/app_mode.dart';
import '../core/logging.dart';

/// One-time process setup, shared by the real app and by tests.
///
/// Kept out of `main.dart` so `main()` stays a three-liner and every startup
/// side effect has an obvious home (CLAUDE.md §5).
Future<List<Override>> bootstrap() async {
  tzdata.initializeTimeZones(); // IANA database for meal-window resolution

  final prefs = await SharedPreferences.getInstance();
  final modeStore = AppModeStore(prefs);

  // File logging is host-only; enable it once the mode is known (see
  // ModeController). Console logging is always on.
  await AppLogger.configure(toFile: false);

  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    appModeStoreProvider.overrideWithValue(modeStore),
  ];
}

/// Injected, never read as a global (CLAUDE.md §5).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw StateError('sharedPreferencesProvider must be overridden in bootstrap()'),
);

final appModeStoreProvider = Provider<AppModeStore>(
  (_) => throw StateError('appModeStoreProvider must be overridden in bootstrap()'),
);
