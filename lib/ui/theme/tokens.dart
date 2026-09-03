import 'package:flutter/material.dart';

/// Neobrutalism design tokens (PRD §14.4) — defined once, consumed everywhere,
/// never hand-styled per screen. Colours are checked for WCAG AA contrast
/// against their intended text colour (PRD §14.3); the pairings noted below
/// are the ones the UI is allowed to use.
///
/// 60/30/10 (PRD §14.3 / CLAUDE.md §11.4): [surfaceBg] is the 60% ground,
/// [surface] the 30%, and the accent family the 10% — reserved for the single
/// most important action on a screen (Von Restorff).
class NbColors {
  const NbColors._();

  // 60% — ground
  static const surfaceBg = Color(0xFFF5F1E8); // warm off-white
  static const ink =
      Color(0xFF1A1A1A); // primary text / borders (AA on all surfaces below)

  // 30% — surfaces
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFE9E4D6);

  // 10% — accents. Each is paired with the text colour that clears AA on it.
  static const accent = Color(0xFF2B6CF6); // primary CTA · text: white
  static const onAccent = Color(0xFFFFFFFF);

  // Status — never colour alone (PRD §14.3): each pairs with an icon + a
  // distinct border weight in the widget layer.
  static const accept = Color(0xFF1E8E4E); // scan accepted · text: white
  static const onAccept = Color(0xFFFFFFFF);
  static const reject = Color(0xFFD62D2D); // scan rejected · text: white
  static const onReject = Color(0xFFFFFFFF);
  static const warn = Color(0xFFE8A317); // grace / pending · text: ink
  static const onWarn = ink;

  static const shadow = Color(0xFF1A1A1A); // hard offset shadow
}

/// Border widths — blocky, but on the 8pt system (PRD §14.3).
class NbBorders {
  const NbBorders._();

  static const double hair = 1.5;
  static const double base = 3.0; // restrained variant (admin data surfaces)
  static const double bold = 5.0; // full intensity (scan result, primary CTA)

  static const BorderRadius radius =
      BorderRadius.zero; // neobrutalism: no rounding
}

/// Hard, offset drop shadows. Weight scales with intensity (PRD §14.2).
class NbShadows {
  const NbShadows._();

  static const List<BoxShadow> restrained = [
    BoxShadow(color: NbColors.shadow, offset: Offset(3, 3), blurRadius: 0),
  ];

  static const List<BoxShadow> full = [
    BoxShadow(color: NbColors.shadow, offset: Offset(6, 6), blurRadius: 0),
  ];
}

/// 8-point spacing scale (PRD §14.3 / CLAUDE.md §11.4).
class NbSpace {
  const NbSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Small type scale — ~4 sizes, 2 weights (PRD §14.3 / CLAUDE.md §11.4).
class NbType {
  const NbType._();

  static const String family =
      'RobotoMono'; // blocky, monospaced — falls back to system mono

  static const TextStyle display = TextStyle(
      fontFamily: family,
      fontSize: 34,
      fontWeight: FontWeight.w700,
      color: NbColors.ink,
      height: 1.1);
  static const TextStyle heading = TextStyle(
      fontFamily: family,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: NbColors.ink,
      height: 1.2);
  static const TextStyle body = TextStyle(
      fontFamily: family,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: NbColors.ink,
      height: 1.4);
  static const TextStyle label = TextStyle(
      fontFamily: family,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: NbColors.ink,
      height: 1.2);
}

/// The two intensity levels from PRD §14.2, passed to shared widgets so a
/// screen never re-decides border/shadow weight.
enum NbIntensity {
  /// Admin data surfaces — tables, calendar, forms, lists.
  restrained,

  /// Scan accept/reject state and primary CTAs.
  full;

  double get borderWidth =>
      this == NbIntensity.full ? NbBorders.bold : NbBorders.base;

  List<BoxShadow> get shadow =>
      this == NbIntensity.full ? NbShadows.full : NbShadows.restrained;
}
