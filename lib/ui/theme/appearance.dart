import 'package:flutter/material.dart' show Brightness, ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_catalog.dart';

/// How this device looks: which theme, light or dark, and whether it animates.
///
/// Held per device rather than per account, because it is a property of the
/// screen someone is looking at, not of who is signed in — the scan-point
/// phone by the window and the admin's phone want different answers. The host
/// can override all three when a site wants one consistent look
/// (see [AppearancePolicy]).
class Appearance {
  const Appearance({
    required this.theme,
    required this.mode,
    required this.motion,
  });

  factory Appearance.fromWire(Map<String, dynamic> j) => Appearance(
        theme: TiffinThemeId.fromWire(j['theme'] as String?),
        mode: _modeFromWire(j['mode'] as String?),
        motion: j['motion'] as bool? ?? true,
      );

  static const defaults = Appearance(
    theme: TiffinThemeId.defaultTheme,
    mode: ThemeMode.system,
    motion: true,
  );

  final TiffinThemeId theme;
  final ThemeMode mode;
  final bool motion;

  Appearance copyWith({
    TiffinThemeId? theme,
    ThemeMode? mode,
    bool? motion,
  }) =>
      Appearance(
        theme: theme ?? this.theme,
        mode: mode ?? this.mode,
        motion: motion ?? this.motion,
      );

  Map<String, dynamic> toWire() => {
        'theme': theme.wire,
        'mode': mode.name,
        'motion': motion,
      };

  /// Resolves [mode] against the device's own light/dark setting.
  Brightness brightness(Brightness platformBrightness) => switch (mode) {
        ThemeMode.system => platformBrightness,
        ThemeMode.light => Brightness.light,
        ThemeMode.dark => Brightness.dark,
      };

  static ThemeMode _modeFromWire(String? wire) => switch (wire) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// What the host says about appearance. When [enforced] is true every device
/// on this host renders [appearance] and its own controls go read-only —
/// visibly so, rather than silently ignoring taps (§11.1 heuristic 1).
class AppearancePolicy {
  const AppearancePolicy({required this.enforced, required this.appearance});

  factory AppearancePolicy.fromWire(Map<String, dynamic> j) => AppearancePolicy(
        enforced: j['enforceAppearance'] as bool? ?? false,
        appearance: Appearance.fromWire(j),
      );

  static const none =
      AppearancePolicy(enforced: false, appearance: Appearance.defaults);

  final bool enforced;
  final Appearance appearance;

  /// The host's choice when it is enforcing, otherwise the device's own.
  Appearance resolve(Appearance device) => enforced ? appearance : device;
}

/// Device-local persistence, mirroring [AppModeStore]'s shape.
class AppearanceStore {
  AppearanceStore(this._prefs);

  final SharedPreferences _prefs;
  static const _themeKey = 'appearance_theme';
  static const _modeKey = 'appearance_mode';
  static const _motionKey = 'appearance_motion';

  Appearance read() => Appearance(
        theme: TiffinThemeId.fromWire(_prefs.getString(_themeKey)),
        mode: Appearance._modeFromWire(_prefs.getString(_modeKey)),
        motion: _prefs.getBool(_motionKey) ?? true,
      );

  Future<void> write(Appearance appearance) async {
    await _prefs.setString(_themeKey, appearance.theme.wire);
    await _prefs.setString(_modeKey, appearance.mode.name);
    await _prefs.setBool(_motionKey, appearance.motion);
  }
}
