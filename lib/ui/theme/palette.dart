import 'package:flutter/material.dart';

import 'oklch.dart';

/// The semantic colour roles every theme must fill (CLAUDE.md §11.4).
///
/// Screens never name a colour — they name a *role*, so swapping the theme
/// swaps one object rather than editing widgets. Text colours that sit on a
/// variable fill are derived by contrast rather than hand-picked, so a fill can
/// be retuned without silently dropping its label below WCAG AA.
@immutable
class TiffinPalette {
  const TiffinPalette({
    required this.brightness,
    required this.surfaceBg,
    required this.surface,
    required this.surfaceMuted,
    required this.ink,
    required this.inkMuted,
    required this.border,
    required this.accent,
    required this.accept,
    required this.reject,
    required this.warn,
    required this.shadow,
    required this.toneMembers,
    required this.toneMoney,
    required this.toneKitchen,
    required this.toneSystem,
    required this.overlayScrim,
  });

  final Brightness brightness;

  /// 60% — the page ground.
  final Color surfaceBg;

  /// 30% — cards, sheets, fields.
  final Color surface;
  final Color surfaceMuted;

  /// Primary text and, in bordered themes, the border colour.
  final Color ink;

  /// Secondary text — captions, hints, disabled labels.
  final Color inkMuted;
  final Color border;

  /// 10% — the single most important action on a screen (Von Restorff).
  final Color accent;

  /// Status fills. Never colour alone: the widget layer pairs each with an
  /// icon and a border weight (§12.2).
  final Color accept;
  final Color reject;
  final Color warn;

  final Color shadow;

  /// Category fills for the dashboard grid — these carry *domain*, never
  /// state, so colour-blind users lose nothing by ignoring them.
  final Color toneMembers;
  final Color toneMoney;
  final Color toneKitchen;
  final Color toneSystem;

  /// Dimming behind modals and full-screen scan verdicts.
  final Color overlayScrim;

  bool get isDark => brightness == Brightness.dark;

  /// Readable text/icon colour for anything drawn on [fill].
  ///
  /// Checked against both ink and surface so it works on a pastel clay tile
  /// and a saturated neobrutal one without either being special-cased.
  Color on(Color fill) => mostReadableOn(fill, [ink, surface, surfaceBg]);

  Color get onAccent => on(accent);
  Color get onAccept => on(accept);
  Color get onReject => on(reject);
  Color get onWarn => on(warn);

  Color tone(NbTone tone) => switch (tone) {
        NbTone.neutral => surface,
        NbTone.members => toneMembers,
        NbTone.money => toneMoney,
        NbTone.kitchen => toneKitchen,
        NbTone.system => toneSystem,
      };
}

/// Category of an admin destination, used to colour-code the dashboard so it
/// reads as grouped at a glance instead of as fourteen identical boxes.
enum NbTone { neutral, members, money, kitchen, system }
