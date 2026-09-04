import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'motion.dart';

/// A bordered, shadowed block — the base primitive for cards, panels and the
/// scan result state (PRD §14). [intensity] picks border/shadow weight so no
/// screen re-decides it; the theme decides what those weights mean.
///
/// [tone] colour-codes a surface by *domain* (members, money, kitchen,
/// system). It never encodes state, so nothing is lost by not seeing colour —
/// every toned tile still carries its own icon and label (CLAUDE.md §12.2).
class NbSurface extends StatelessWidget {
  const NbSurface({
    super.key,
    required this.child,
    this.intensity = NbIntensity.restrained,
    this.background,
    this.tone = NbTone.neutral,
    this.padding = const EdgeInsets.all(NbSpace.md),
    this.onTap,
  });

  final Widget child;
  final NbIntensity intensity;

  /// Explicit fill. Wins over [tone] when both are given. Null means "let the
  /// theme decide" — a const default cannot follow a runtime theme switch.
  final Color? background;
  final NbTone tone;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fill = background ?? t.color.tone(tone);

    final block = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: t.shape.radius,
        border: Border.all(
            color: t.color.border, width: intensity.borderWidth(t.shape)),
        boxShadow: [
          ...intensity.shadow(t.shape),
          // Clay's inset bloom; empty for every other theme.
          ...t.shape.innerHighlight,
        ],
      ),
      child: DefaultTextStyle.merge(
        // A toned fill needs its own readable ink, or a dark-mode tile keeps
        // the page's light text on a mid-lightness fill.
        style: TextStyle(color: t.color.on(fill)),
        child: child,
      ),
    );
    if (onTap == null) return block;
    return PressEffect(onTap: onTap, child: block);
  }
}
