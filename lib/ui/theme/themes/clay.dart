import 'package:flutter/material.dart';

import '../oklch.dart';
import '../tokens.dart';

/// Clay — puffy, rounded and warm (CLAUDE.md §11.5.6).
///
/// Unlike neumorphism, clay surfaces sit on a *contrasting* ground rather than
/// a matched one, so the shape boundary survives without relying on a shadow
/// pair. The pastel palettes this style invites are the risk, so lightness is
/// pulled down until dark ink clears AA on every fill — holding the pleasant
/// hue while fixing contrast is exactly what OKLCH makes easy.
TiffinTokens buildClay(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final palette = dark ? _dark() : _light();
  return TiffinTokens(
    color: palette,
    text: TiffinTypography.scale(family: null, ink: palette.ink),
    shape: TiffinShape(
      radius: BorderRadius.circular(28),
      borderHair: 1,
      borderBase: 1.5,
      borderBold: 2.5,
      shadowRestrained: [
        BoxShadow(
          color: palette.shadow.withValues(alpha: dark ? 0.46 : 0.22),
          offset: const Offset(0, 8),
          blurRadius: 18,
        ),
      ],
      shadowFull: [
        BoxShadow(
          color: palette.shadow.withValues(alpha: dark ? 0.55 : 0.32),
          offset: const Offset(0, 14),
          blurRadius: 28,
        ),
      ],
      innerHighlight: [
        BoxShadow(
          color: (dark ? Colors.white : Colors.white).withValues(
            alpha: dark ? 0.06 : 0.55,
          ),
          offset: const Offset(0, 4),
          blurRadius: 12,
          spreadRadius: -6,
        ),
      ],
    ),
    // Overshoots — the puffy look wants a little squash and bounce.
    motion: const MotionTokens(
      fast: Duration(milliseconds: 130),
      normal: Duration(milliseconds: 220),
      page: Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      entrance: Curves.elasticOut,
      pressScale: 0.955,
      staggerStep: Duration(milliseconds: 34),
    ),
  );
}

TiffinPalette _light() {
  const ink = Oklch(0.28, 0.060, 300);
  return TiffinPalette(
    brightness: Brightness.light,
    surfaceBg: const Oklch(0.945, 0.035, 300).toColor(),
    surface: const Oklch(0.975, 0.020, 300).toColor(),
    surfaceMuted: const Oklch(0.905, 0.045, 300).toColor(),
    ink: ink.toColor(),
    inkMuted: ink.withL(0.50).toColor(),
    border: const Oklch(0.58, 0.055, 300).toColor(),
    accent: const Oklch(0.48, 0.19, 310).toColor(),
    accept: const Oklch(0.48, 0.15, 155).toColor(),
    reject: const Oklch(0.48, 0.19, 20).toColor(),
    warn: const Oklch(0.81, 0.14, 70).toColor(),
    shadow: const Oklch(0.55, 0.10, 300).toColor(),
    toneMembers: const Oklch(0.87, 0.085, 250).toColor(),
    toneMoney: const Oklch(0.89, 0.095, 80).toColor(),
    toneKitchen: const Oklch(0.87, 0.090, 160).toColor(),
    toneSystem: const Oklch(0.86, 0.080, 330).toColor(),
    overlayScrim: ink.toColor().withValues(alpha: 0.45),
  );
}

TiffinPalette _dark() {
  const ink = Oklch(0.94, 0.020, 300);
  const ground = Oklch(0.20, 0.030, 300);
  return TiffinPalette(
    brightness: Brightness.dark,
    surfaceBg: ground.toColor(),
    surface: ground.withL(0.27).toColor(),
    surfaceMuted: ground.withL(0.33).toColor(),
    ink: ink.toColor(),
    inkMuted: ink.withL(0.72).toColor(),
    border: ground.withL(0.57).toColor(),
    accent: const Oklch(0.74, 0.15, 310).toColor(),
    accept: const Oklch(0.75, 0.13, 155).toColor(),
    reject: const Oklch(0.69, 0.17, 20).toColor(),
    warn: const Oklch(0.82, 0.13, 70).toColor(),
    shadow: const Oklch(0.06, 0.02, 300).toColor(),
    toneMembers: const Oklch(0.37, 0.080, 250).toColor(),
    toneMoney: const Oklch(0.38, 0.085, 80).toColor(),
    toneKitchen: const Oklch(0.37, 0.080, 160).toColor(),
    toneSystem: const Oklch(0.37, 0.075, 330).toColor(),
    overlayScrim:
        const Oklch(0.08, 0.02, 300).toColor().withValues(alpha: 0.55),
  );
}
