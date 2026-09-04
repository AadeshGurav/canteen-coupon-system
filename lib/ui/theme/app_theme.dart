import 'package:flutter/material.dart';

import 'theme_catalog.dart';
import 'tokens.dart';

/// Builds the [ThemeData] for one theme + brightness, and hangs the full token
/// set off it as a [ThemeExtension] so `context.tokens` works everywhere.
///
/// This only sets shared defaults for stock Material widgets; the app's own
/// widgets read tokens directly and opt into an [NbIntensity].
ThemeData buildTiffinTheme(
  TiffinThemeId id,
  Brightness brightness, {
  bool motion = true,
  bool reduceTransparency = false,
}) {
  var tokens = id.tokens(brightness);
  if (!motion) tokens = tokens.copyWith(motion: MotionTokens.still);
  if (reduceTransparency) tokens = tokens.copyWith(shape: tokens.shape.opaque);

  final color = tokens.color;
  final shape = tokens.shape;
  final text = tokens.text;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: color.accent,
    onPrimary: color.onAccent,
    secondary: color.ink,
    onSecondary: color.surface,
    error: color.reject,
    onError: color.onReject,
    surface: color.surface,
    onSurface: color.ink,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: color.surfaceBg,
    fontFamily: text.family,
    // Neobrutalism has no ripple; the softer themes keep the platform one, so
    // touch feedback still arrives within ~100ms on every theme.
    splashFactory: id == TiffinThemeId.neobrutal
        ? NoSplash.splashFactory
        : InkSparkle.splashFactory,
    extensions: [tokens],
  );

  OutlineInputBorder border(Color c, double width) => OutlineInputBorder(
        borderRadius: shape.radius,
        borderSide: BorderSide(color: c, width: width),
      );

  return base.copyWith(
    pageTransitionsTheme: motion
        ? null
        : const PageTransitionsTheme(builders: {
            TargetPlatform.android: _NoTransitionBuilder(),
            TargetPlatform.iOS: _NoTransitionBuilder(),
          }),
    textTheme: base.textTheme.copyWith(
      displayLarge: text.display,
      headlineMedium: text.heading,
      bodyMedium: text.body,
      labelLarge: text.label,
    ),
    appBarTheme: AppBarTheme(
      // Frost's bar is translucent; the blur itself is applied by NbAppBar,
      // which is the only place that can wrap the bar in a BackdropFilter.
      backgroundColor: shape.isTranslucent
          ? color.surface.withValues(alpha: shape.chromeOpacity)
          : color.surface,
      foregroundColor: color.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      shape: Border(
        bottom: BorderSide(color: color.border, width: shape.borderBase),
      ),
      titleTextStyle: text.heading,
    ),
    dividerTheme: DividerThemeData(
      color: color.border,
      thickness: shape.borderHair,
      space: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: color.surface,
      border: border(color.border, shape.borderBase),
      enabledBorder: border(color.border, shape.borderBase),
      // Focus is a colour *and* a weight change, so it survives with colour
      // stripped — a 3px ink border can't be told apart from a resting one by
      // hue alone (§11.5.0 rule 5).
      focusedBorder: border(color.accent, shape.borderBold + 1),
      errorBorder: border(color.reject, shape.borderBase),
      focusedErrorBorder: border(color.reject, shape.borderBold),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: NbSpace.md,
        vertical: NbSpace.md,
      ),
      labelStyle: text.label,
      hintStyle: text.body.copyWith(color: color.inkMuted),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: color.ink,
      contentTextStyle: text.body.copyWith(color: color.surface),
      shape: RoundedRectangleBorder(borderRadius: shape.radius),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: color.surface,
      shape: RoundedRectangleBorder(
        borderRadius: shape.radius,
        side: BorderSide(color: color.border, width: shape.borderBase),
      ),
      titleTextStyle: text.heading,
      contentTextStyle: text.body,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: color.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: shape.radius.topLeft),
        side: BorderSide(color: color.border, width: shape.borderBase),
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.body,
      subtitleTextStyle: text.body.copyWith(color: color.inkMuted),
      iconColor: color.ink,
      selectedColor: color.accent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? color.onAccent : color.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? color.accent
            : color.surfaceMuted,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: color.accent),
    iconTheme: IconThemeData(color: color.ink),
  );
}

/// Used when motion is off: routes swap with no animation at all, rather than
/// a shortened one.
class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
