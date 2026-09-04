import 'package:flutter/material.dart';

import '../oklch.dart';
import '../tokens.dart';

/// Neobrutalism — the app's original identity, now carrying colour.
///
/// Hard ink borders, zero rounding, and an offset shadow with no blur. The
/// vivid fills live in the category tones rather than the accent: a yellow
/// border on white cannot clear the 3:1 UI-boundary rule, so the accent stays
/// a strong indigo and the liveliness comes from the tiles.
TiffinTokens buildNeobrutal(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final palette = dark ? _dark() : _light();
  return TiffinTokens(
    color: palette,
    text: TiffinTypography.scale(family: 'RobotoMono', ink: palette.ink),
    shape: TiffinShape(
      radius: BorderRadius.zero,
      borderHair: 1.5,
      borderBase: 3,
      borderBold: 5,
      shadowRestrained: [
        BoxShadow(color: palette.shadow, offset: const Offset(3, 3)),
      ],
      shadowFull: [
        BoxShadow(color: palette.shadow, offset: const Offset(6, 6)),
      ],
      innerHighlight: const [],
    ),
    // Snaps. No easing softness — the shadow offset pops and stops.
    motion: const MotionTokens(
      fast: Duration(milliseconds: 90),
      normal: Duration(milliseconds: 150),
      page: Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      entrance: Curves.easeOutBack,
      pressScale: 0.97,
      staggerStep: Duration(milliseconds: 28),
    ),
  );
}

TiffinPalette _light() {
  const ink = Oklch(0.20, 0.010, 60);
  return TiffinPalette(
    brightness: Brightness.light,
    surfaceBg: const Oklch(0.955, 0.018, 90).toColor(),
    surface: const Oklch(1.0, 0.0, 0).toColor(),
    surfaceMuted: const Oklch(0.92, 0.025, 88).toColor(),
    ink: ink.toColor(),
    inkMuted: ink.withL(0.45).toColor(),
    border: ink.toColor(),
    accent: const Oklch(0.48, 0.20, 265).toColor(),
    accept: const Oklch(0.48, 0.15, 150).toColor(),
    reject: const Oklch(0.48, 0.20, 27).toColor(),
    warn: const Oklch(0.80, 0.15, 85).toColor(),
    shadow: ink.toColor(),
    toneMembers: const Oklch(0.86, 0.13, 220).toColor(),
    toneMoney: const Oklch(0.87, 0.16, 95).toColor(),
    toneKitchen: const Oklch(0.85, 0.14, 150).toColor(),
    toneSystem: const Oklch(0.84, 0.12, 330).toColor(),
    overlayScrim: ink.toColor().withValues(alpha: 0.65),
  );
}

/// Dark neobrutalism inverts the ink: borders and shadows go light against a
/// near-black ground. Tones drop to ~0.42 lightness so their labels can be
/// light text, and chroma comes down — vivid on white glares on near-black.
TiffinPalette _dark() {
  const ink = Oklch(0.94, 0.008, 90);
  const ground = Oklch(0.185, 0.012, 90);
  return TiffinPalette(
    brightness: Brightness.dark,
    surfaceBg: ground.toColor(),
    surface: ground.withL(0.245).toColor(),
    surfaceMuted: ground.withL(0.31).toColor(),
    ink: ink.toColor(),
    inkMuted: ink.withL(0.70).toColor(),
    border: ink.toColor(),
    accent: const Oklch(0.70, 0.16, 265).toColor(),
    accept: const Oklch(0.72, 0.14, 150).toColor(),
    reject: const Oklch(0.66, 0.17, 27).toColor(),
    warn: const Oklch(0.80, 0.13, 85).toColor(),
    shadow: ink.toColor(),
    toneMembers: const Oklch(0.42, 0.10, 220).toColor(),
    toneMoney: const Oklch(0.44, 0.11, 95).toColor(),
    toneKitchen: const Oklch(0.42, 0.10, 150).toColor(),
    toneSystem: const Oklch(0.42, 0.09, 330).toColor(),
    overlayScrim: const Oklch(0.10, 0.01, 90).toColor().withValues(alpha: 0.72),
  );
}
