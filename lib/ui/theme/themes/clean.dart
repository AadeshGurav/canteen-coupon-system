import 'package:flutter/material.dart';

import '../oklch.dart';
import '../tokens.dart';

/// Clean — flat, minimal, calm (CLAUDE.md §11.5.1).
///
/// The theme for long admin sessions: hierarchy carried by size, weight and
/// space rather than ornament. Hairline borders stay even in the flat look so
/// a tappable surface is still identifiable as one — flat must not mean
/// ambiguous.
TiffinTokens buildClean(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final palette = dark ? _dark() : _light();
  return TiffinTokens(
    color: palette,
    text: TiffinTypography.scale(family: null, ink: palette.ink),
    shape: TiffinShape(
      radius: BorderRadius.circular(8),
      borderHair: 1,
      borderBase: 1,
      borderBold: 2,
      shadowRestrained: [
        BoxShadow(
          color: palette.shadow.withValues(alpha: dark ? 0.44 : 0.07),
          offset: const Offset(0, 1),
          blurRadius: 3,
        ),
      ],
      shadowFull: [
        BoxShadow(
          color: palette.shadow.withValues(alpha: dark ? 0.52 : 0.11),
          offset: const Offset(0, 4),
          blurRadius: 12,
        ),
      ],
      innerHighlight: const [],
    ),
    motion: const MotionTokens(
      fast: Duration(milliseconds: 110),
      normal: Duration(milliseconds: 180),
      page: Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      entrance: Curves.easeOut,
      pressScale: 0.985,
      staggerStep: Duration(milliseconds: 22),
    ),
  );
}

TiffinPalette _light() {
  const ink = Oklch(0.25, 0.020, 250);
  return TiffinPalette(
    brightness: Brightness.light,
    surfaceBg: const Oklch(0.985, 0.003, 250).toColor(),
    surface: const Oklch(1.0, 0.0, 0).toColor(),
    surfaceMuted: const Oklch(0.965, 0.005, 250).toColor(),
    ink: ink.toColor(),
    inkMuted: ink.withL(0.52).toColor(),
    border: const Oklch(0.58, 0.014, 250).toColor(),
    accent: const Oklch(0.48, 0.17, 250).toColor(),
    accept: const Oklch(0.48, 0.14, 150).toColor(),
    reject: const Oklch(0.48, 0.19, 27).toColor(),
    warn: const Oklch(0.78, 0.14, 80).toColor(),
    shadow: const Oklch(0.20, 0.03, 250).toColor(),
    toneMembers: const Oklch(0.93, 0.045, 235).toColor(),
    toneMoney: const Oklch(0.94, 0.055, 100).toColor(),
    toneKitchen: const Oklch(0.93, 0.050, 155).toColor(),
    toneSystem: const Oklch(0.93, 0.035, 300).toColor(),
    overlayScrim: ink.toColor().withValues(alpha: 0.45),
  );
}

TiffinPalette _dark() {
  const ink = Oklch(0.93, 0.008, 250);
  const ground = Oklch(0.18, 0.012, 250);
  return TiffinPalette(
    brightness: Brightness.dark,
    surfaceBg: ground.toColor(),
    // Elevation inverts in dark mode: a raised surface gets lighter, it does
    // not gain a heavier shadow (§11.5.10).
    surface: ground.withL(0.235).toColor(),
    surfaceMuted: ground.withL(0.29).toColor(),
    ink: ink.toColor(),
    inkMuted: ink.withL(0.70).toColor(),
    border: ground.withL(0.55).toColor(),
    accent: const Oklch(0.72, 0.14, 250).toColor(),
    accept: const Oklch(0.74, 0.13, 150).toColor(),
    reject: const Oklch(0.67, 0.17, 27).toColor(),
    warn: const Oklch(0.80, 0.13, 80).toColor(),
    shadow: const Oklch(0.05, 0.0, 0).toColor(),
    toneMembers: const Oklch(0.32, 0.055, 235).toColor(),
    toneMoney: const Oklch(0.33, 0.060, 100).toColor(),
    toneKitchen: const Oklch(0.32, 0.055, 155).toColor(),
    toneSystem: const Oklch(0.32, 0.045, 300).toColor(),
    overlayScrim: const Oklch(0.08, 0.01, 250).toColor().withValues(alpha: 0.6),
  );
}
