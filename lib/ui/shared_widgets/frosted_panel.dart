import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Wraps an overlay in the active theme's chrome material.
///
/// Only Frost is translucent; every other theme returns [child] untouched, so
/// this is safe to use on any sheet or dialog. Translucency is confined to
/// overlays because they are the one place with a known thing behind them —
/// content surfaces stay solid, where contrast can actually be reasoned about
/// (CLAUDE.md §11.5.4).
///
/// The blur is dropped entirely when the viewer has asked for reduced
/// transparency or higher contrast, which is what the OS accessibility
/// settings already do natively (§11.5.0 rule 6).
class FrostedPanel extends StatelessWidget {
  const FrostedPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final media = MediaQuery.of(context);
    final wantsPlain = media.highContrast || media.accessibleNavigation;

    if (!t.shape.isTranslucent || wantsPlain) return child;

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: t.shape.radius.topLeft),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: t.shape.chromeBlur,
          sigmaY: t.shape.chromeBlur,
        ),
        // A semi-opaque plate *behind* the blur: blur softens a backdrop
        // without bounding it, so text on glass alone has no guaranteed
        // contrast.
        child: Container(
          color: t.color.surface.withValues(alpha: t.shape.chromeOpacity),
          child: child,
        ),
      ),
    );
  }
}

/// Background colour a modal should use so [FrostedPanel] can supply its own.
/// Transparent under Frost (the panel paints the plate), solid otherwise.
Color sheetBackground(BuildContext context) {
  final t = context.tokens;
  return t.shape.isTranslucent ? Colors.transparent : t.color.surface;
}
