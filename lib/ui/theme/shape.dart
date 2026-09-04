import 'package:flutter/material.dart';

/// Border, corner and depth values — the half of a theme's personality that
/// isn't colour. Neobrutalism's hard offset shadow and Clay's soft bloom are
/// the same three fields with very different numbers.
@immutable
class TiffinShape {
  const TiffinShape({
    required this.radius,
    required this.borderHair,
    required this.borderBase,
    required this.borderBold,
    required this.shadowRestrained,
    required this.shadowFull,
    required this.innerHighlight,
    this.chromeBlur = 0,
    this.chromeOpacity = 1,
  });

  final BorderRadius radius;

  /// Dividers and hairlines.
  final double borderHair;

  /// Restrained surfaces — admin data, forms, lists.
  final double borderBase;

  /// Full intensity — scan verdicts and primary CTAs.
  final double borderBold;

  final List<BoxShadow> shadowRestrained;
  final List<BoxShadow> shadowFull;

  /// Clay's inset bloom. Empty for every other theme.
  final List<BoxShadow> innerHighlight;

  /// Frost only: backdrop blur applied to chrome (app bars, sheets). Capped
  /// well below the point where it becomes a GPU cost on a mid-range phone
  /// (CLAUDE.md §11.5.4).
  final double chromeBlur;

  /// Frost only: fill opacity *behind* the blur. Blur alone does not guarantee
  /// contrast — it softens a backdrop without bounding it — so a semi-opaque
  /// plate always sits underneath.
  final double chromeOpacity;

  bool get isTranslucent => chromeBlur > 0 && chromeOpacity < 1;

  /// A solid, unblurred version of this shape, for
  /// `prefers-reduced-transparency` / `prefers-contrast` and for the
  /// `@supports`-less fallback path (§11.5.0 rule 6).
  TiffinShape get opaque => TiffinShape(
        radius: radius,
        borderHair: borderHair,
        borderBase: borderBase,
        borderBold: borderBold,
        shadowRestrained: shadowRestrained,
        shadowFull: shadowFull,
        innerHighlight: innerHighlight,
      );
}
