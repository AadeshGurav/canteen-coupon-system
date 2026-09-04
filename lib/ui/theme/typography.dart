import 'package:flutter/material.dart';

/// The type scale: ~4 sizes, 2 weights (CLAUDE.md §11.4).
///
/// Built per theme because the typeface is part of a theme's voice — a blocky
/// mono for Neobrutal, the platform's humanist sans for Clean and Frost, a
/// rounded face for Clay.
@immutable
class TiffinTypography {
  const TiffinTypography({
    required this.family,
    required this.display,
    required this.heading,
    required this.body,
    required this.label,
  });

  /// Builds the scale from a family and an ink colour, so a theme declares
  /// intent (family, tracking) once rather than repeating colour four times.
  factory TiffinTypography.scale({
    required String? family,
    required Color ink,
    double displaySize = 34,
    double headingSize = 22,
    double bodySize = 16,
    double labelSize = 13,
    double letterSpacing = 0,
    FontWeight boldWeight = FontWeight.w700,
  }) {
    TextStyle style(double size, FontWeight weight, double height) => TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          color: ink,
          height: height,
          letterSpacing: letterSpacing,
        );

    return TiffinTypography(
      family: family,
      display: style(displaySize, boldWeight, 1.1),
      heading: style(headingSize, boldWeight, 1.2),
      // Body stays at or above 16px: below that iOS Safari zooms form inputs,
      // and it is the floor for comfortable reading anyway (§11.6.3).
      body: style(bodySize, FontWeight.w400, 1.4),
      label: style(labelSize, boldWeight, 1.2),
    );
  }

  final String? family;
  final TextStyle display;
  final TextStyle heading;
  final TextStyle body;
  final TextStyle label;

  /// Recolours the whole scale — used for text drawn on an accent or status
  /// fill, where the ink colour is derived from the fill rather than the page.
  TiffinTypography onColor(Color color) => TiffinTypography(
        family: family,
        display: display.copyWith(color: color),
        heading: heading.copyWith(color: color),
        body: body.copyWith(color: color),
        label: label.copyWith(color: color),
      );
}
