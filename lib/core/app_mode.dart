import 'package:shared_preferences/shared_preferences.dart';

/// Which role this install is playing on the LAN (PRD §13.2). Chosen once on
/// first launch, changeable later from the mode picker. Persisted so the app
/// resumes into the same mode.
enum AppMode { host, client }

/// The meal-unit types tracked everywhere (PRD §5). Saturday is brunch-only.
enum MealType {
  breakfast,
  lunch,
  brunch;

  static MealType fromWire(String v) =>
      MealType.values.firstWhere((m) => m.name == v,
          orElse: () => throw ArgumentError('Unknown meal type: $v'));

  String get wire => name;
}

/// Reads/writes the persisted [AppMode]. Injected, not a global (CLAUDE.md §5).
class AppModeStore {
  AppModeStore(this._prefs);

  static const _key = 'app_mode';

  final SharedPreferences _prefs;

  AppMode? read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    return AppMode.values.where((m) => m.name == raw).firstOrNull;
  }

  Future<void> write(AppMode mode) => _prefs.setString(_key, mode.name);

  Future<void> clear() => _prefs.remove(_key);
}
