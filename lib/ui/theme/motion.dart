import 'package:flutter/material.dart';

/// How a theme moves. Motion is part of a theme's personality, not a global
/// constant — Neobrutal snaps, Clay overshoots, Frost glides.
///
/// Every duration stays under the ~300ms an interaction can absorb before it
/// starts feeling slow rather than smooth (CLAUDE.md §11.2, Doherty).
@immutable
class MotionTokens {
  const MotionTokens({
    required this.fast,
    required this.normal,
    required this.page,
    required this.curve,
    required this.entrance,
    required this.pressScale,
    required this.staggerStep,
  });

  /// Press feedback, colour and opacity swaps.
  final Duration fast;

  /// Surface transitions, expanding panels, loading -> data swaps.
  final Duration normal;

  /// Route transitions.
  final Duration page;

  /// The theme's signature easing.
  final Curve curve;

  /// Easing for things arriving on screen; may overshoot where the theme wants
  /// a bit of bounce.
  final Curve entrance;

  /// How far a tappable surface shrinks when pressed. 1.0 disables it.
  final double pressScale;

  /// Delay between consecutive items in a staggered list or grid. Kept small:
  /// the last tile of a 14-tile grid must not wait on a visible queue.
  final Duration staggerStep;

  /// Everything at zero — what the whole app collapses to when motion is off,
  /// whether by the device setting, a host policy, or the OS reduce-motion
  /// preference (§11.5.0 rule 6).
  static const still = MotionTokens(
    fast: Duration.zero,
    normal: Duration.zero,
    page: Duration.zero,
    curve: Curves.linear,
    entrance: Curves.linear,
    pressScale: 1.0,
    staggerStep: Duration.zero,
  );

  bool get isStill => normal == Duration.zero;
}
