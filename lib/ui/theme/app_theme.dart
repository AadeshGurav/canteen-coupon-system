import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the [ThemeData] from the neobrutalism tokens (PRD §14.4). Individual
/// widgets still opt into an [NbIntensity]; this only sets the shared defaults
/// (colours, type scale, the "no rounding, hard border" baseline).
ThemeData buildNeobrutalismTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: NbColors.accent,
    onPrimary: NbColors.onAccent,
    secondary: NbColors.ink,
    onSecondary: NbColors.surface,
    error: NbColors.reject,
    onError: NbColors.onReject,
    surface: NbColors.surface,
    onSurface: NbColors.ink,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: NbColors.surfaceBg,
    fontFamily: NbType.family,
    splashFactory: NoSplash.splashFactory, // neobrutalism: no ripple
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displayLarge: NbType.display,
      headlineMedium: NbType.heading,
      bodyMedium: NbType.body,
      labelLarge: NbType.label,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: NbColors.surface,
      foregroundColor: NbColors.ink,
      elevation: 0,
      centerTitle: false,
      shape: Border(bottom: BorderSide(color: NbColors.ink, width: NbBorders.base)),
      titleTextStyle: NbType.heading,
    ),
    dividerTheme: const DividerThemeData(color: NbColors.ink, thickness: NbBorders.hair, space: 0),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: NbColors.surface,
      border: OutlineInputBorder(
        borderRadius: NbBorders.radius,
        borderSide: BorderSide(color: NbColors.ink, width: NbBorders.base),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: NbBorders.radius,
        borderSide: BorderSide(color: NbColors.ink, width: NbBorders.base),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: NbBorders.radius,
        borderSide: BorderSide(color: NbColors.accent, width: NbBorders.bold),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: NbBorders.radius,
        borderSide: BorderSide(color: NbColors.reject, width: NbBorders.base),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: NbSpace.md, vertical: NbSpace.md),
      labelStyle: NbType.label,
    ),
  );
}
