import 'package:flutter/material.dart';

import 'motion.dart';
import 'palette.dart';
import 'shape.dart';
import 'typography.dart';

export 'motion.dart';
export 'palette.dart';
export 'shape.dart';
export 'typography.dart';

/// Every theme-varying design value, carried on [ThemeData] as a
/// [ThemeExtension] and read through `context.tokens`.
///
/// These were compile-time constants until themes became switchable at
/// runtime. Spacing and intensity stayed constant deliberately (see [NbSpace],
/// [NbIntensity]) — an 8pt rhythm is not a matter of taste, so keeping it
/// static avoids threading a token object through code that only wants a gap.
@immutable
class TiffinTokens extends ThemeExtension<TiffinTokens> {
  const TiffinTokens({
    required this.color,
    required this.text,
    required this.shape,
    required this.motion,
  });

  final TiffinPalette color;
  final TiffinTypography text;
  final TiffinShape shape;
  final MotionTokens motion;

  @override
  TiffinTokens copyWith({
    TiffinPalette? color,
    TiffinTypography? text,
    TiffinShape? shape,
    MotionTokens? motion,
  }) =>
      TiffinTokens(
        color: color ?? this.color,
        text: text ?? this.text,
        shape: shape ?? this.shape,
        motion: motion ?? this.motion,
      );

  /// Colour and type cross-fade on a theme switch; geometry and motion snap at
  /// the midpoint. Interpolating a border width or a blur radius produces
  /// visibly wrong in-between states (a half-brutalist card), whereas colour
  /// interpolation is exactly what makes the switch feel deliberate.
  @override
  TiffinTokens lerp(covariant TiffinTokens? other, double t) {
    if (other == null) return this;
    final past = t < 0.5;
    return TiffinTokens(
      color: _lerpPalette(color, other.color, t),
      text: past ? text : other.text,
      shape: past ? shape : other.shape,
      motion: past ? motion : other.motion,
    );
  }

  static TiffinPalette _lerpPalette(
      TiffinPalette a, TiffinPalette b, double t) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    return TiffinPalette(
      brightness: t < 0.5 ? a.brightness : b.brightness,
      surfaceBg: c(a.surfaceBg, b.surfaceBg),
      surface: c(a.surface, b.surface),
      surfaceMuted: c(a.surfaceMuted, b.surfaceMuted),
      ink: c(a.ink, b.ink),
      inkMuted: c(a.inkMuted, b.inkMuted),
      border: c(a.border, b.border),
      accent: c(a.accent, b.accent),
      accept: c(a.accept, b.accept),
      reject: c(a.reject, b.reject),
      warn: c(a.warn, b.warn),
      shadow: c(a.shadow, b.shadow),
      toneMembers: c(a.toneMembers, b.toneMembers),
      toneMoney: c(a.toneMoney, b.toneMoney),
      toneKitchen: c(a.toneKitchen, b.toneKitchen),
      toneSystem: c(a.toneSystem, b.toneSystem),
      overlayScrim: c(a.overlayScrim, b.overlayScrim),
    );
  }
}

/// `context.tokens.color.ink`, `context.tokens.text.body`, and so on.
extension TiffinTokensContext on BuildContext {
  TiffinTokens get tokens {
    final tokens = maybeTokens;
    assert(tokens != null,
        'No TiffinTokens on this ThemeData — build it with buildTiffinTheme().');
    return tokens!;
  }

  /// Null when there is no themed ancestor. Only the crash-screen builder
  /// should need this: it can be asked to render above [MaterialApp], and a
  /// last-resort error widget must never fail for want of a theme.
  TiffinTokens? get maybeTokens => Theme.of(this).extension<TiffinTokens>();
}

/// 8-point spacing scale (CLAUDE.md §11.4). Theme-invariant: a theme changes
/// how things look, never the rhythm they sit on.
class NbSpace {
  const NbSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// How loudly a surface presents itself. Screens pick an intensity; the theme
/// decides what that means in border width and shadow.
enum NbIntensity {
  /// Admin data surfaces — tables, calendar, forms, lists.
  restrained,

  /// Scan accept/reject state and primary CTAs.
  full;

  double borderWidth(TiffinShape shape) =>
      this == NbIntensity.full ? shape.borderBold : shape.borderBase;

  List<BoxShadow> shadow(TiffinShape shape) =>
      this == NbIntensity.full ? shape.shadowFull : shape.shadowRestrained;
}
