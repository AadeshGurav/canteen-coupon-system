import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A bordered, hard-shadowed block — the base primitive for cards, panels and
/// the scan result state (PRD §14). Intensity picks border/shadow weight so no
/// screen re-decides it (PRD §14.4).
class NbSurface extends StatelessWidget {
  const NbSurface({
    super.key,
    required this.child,
    this.intensity = NbIntensity.restrained,
    this.background = NbColors.surface,
    this.padding = const EdgeInsets.all(NbSpace.md),
    this.onTap,
  });

  final Widget child;
  final NbIntensity intensity;
  final Color background;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final block = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: NbColors.ink, width: intensity.borderWidth),
        boxShadow: intensity.shadow,
      ),
      child: child,
    );
    if (onTap == null) return block;
    return GestureDetector(onTap: onTap, child: block);
  }
}
