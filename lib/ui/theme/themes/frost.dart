import 'package:flutter/material.dart';

import '../oklch.dart';
import '../tokens.dart';

/// Frost — a flat base with glass on the chrome only (CLAUDE.md §11.5.4).
///
/// Translucency is confined to app bars, sheets and overlays. Content surfaces
/// stay solid: body copy and data tables never sit on a blurred backdrop,
/// because contrast against an unknown background cannot be reasoned about.
/// [TiffinShape.chromeOpacity] is the semi-opaque plate that sits *behind* the
/// blur — blur alone softens a backdrop without bounding it.
TiffinTokens buildFrost(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final palette = dark ? _dark() : _light();
  return TiffinTokens(
    color: palette,
    text: TiffinTypography.scale(family: null, ink: palette.ink),
    shape: TiffinShape(
      radius: BorderRadius.circular(16),
      borderHair: 1,
      borderBase: 1,
      borderBold: 1.5,
      shadowRestrained: [
        BoxShadow(
          color: palette.shadow.withValues(alpha: dark ? 0.42 : 0.10),
          offset: const Offset(0, 2),
          blurRadius: 10,
        ),
      ],
      shadowFull: [
        BoxShadow(
          color: palette.shadow.withValues(alpha: dark ? 0.50 : 0.16),
          offset: const Offset(0, 8),
          blurRadius: 28,
        ),
      ],
      innerHighlight: const [],
      // Capped well under the point where backdrop blur becomes a scroll cost
      // on a mid-range phone (§11.6.8).
      chromeBlur: 14,
      chromeOpacity: dark ? 0.68 : 0.74,
    ),
    motion: const MotionTokens(
      fast: Duration(milliseconds: 120),
      normal: Duration(milliseconds: 200),
      page: Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      entrance: Curves.easeOutCubic,
      pressScale: 0.98,
      staggerStep: Duration(milliseconds: 26),
    ),
  );
}

TiffinPalette _light() {
  const ink = Oklch(0.26, 0.030, 245);
  return TiffinPalette(
    brightness: Brightness.light,
    surfaceBg: const Oklch(0.955, 0.020, 240).toColor(),
    surface: const Oklch(0.995, 0.004, 240).toColor(),
    surfaceMuted: const Oklch(0.945, 0.018, 240).toColor(),
    ink: ink.toColor(),
    inkMuted: ink.withL(0.52).toColor(),
    border: const Oklch(0.58, 0.022, 240).toColor(),
    accent: const Oklch(0.48, 0.17, 232).toColor(),
    accept: const Oklch(0.48, 0.14, 155).toColor(),
    reject: const Oklch(0.48, 0.19, 20).toColor(),
    warn: const Oklch(0.80, 0.14, 78).toColor(),
    shadow: const Oklch(0.30, 0.06, 245).toColor(),
    toneMembers: const Oklch(0.90, 0.070, 230).toColor(),
    toneMoney: const Oklch(0.92, 0.080, 90).toColor(),
    toneKitchen: const Oklch(0.90, 0.075, 165).toColor(),
    toneSystem: const Oklch(0.89, 0.060, 295).toColor(),
    overlayScrim: ink.toColor().withValues(alpha: 0.40),
  );
}

TiffinPalette _dark() {
  const ink = Oklch(0.94, 0.010, 240);
  const ground = Oklch(0.20, 0.025, 245);
  return TiffinPalette(
    brightness: Brightness.dark,
    surfaceBg: ground.toColor(),
    surface: ground.withL(0.26).toColor(),
    surfaceMuted: ground.withL(0.31).toColor(),
    ink: ink.toColor(),
    inkMuted: ink.withL(0.71).toColor(),
    border: ground.withL(0.57).toColor(),
    accent: const Oklch(0.74, 0.14, 232).toColor(),
    accept: const Oklch(0.75, 0.13, 155).toColor(),
    reject: const Oklch(0.68, 0.17, 20).toColor(),
    warn: const Oklch(0.81, 0.13, 78).toColor(),
    shadow: const Oklch(0.05, 0.0, 0).toColor(),
    toneMembers: const Oklch(0.35, 0.070, 230).toColor(),
    toneMoney: const Oklch(0.36, 0.075, 90).toColor(),
    toneKitchen: const Oklch(0.35, 0.070, 165).toColor(),
    toneSystem: const Oklch(0.35, 0.060, 295).toColor(),
    overlayScrim:
        const Oklch(0.08, 0.02, 245).toColor().withValues(alpha: 0.55),
  );
}
