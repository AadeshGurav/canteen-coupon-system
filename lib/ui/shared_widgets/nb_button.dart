import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'motion.dart';

/// Primary/secondary action button. A full-intensity primary is reserved for
/// the one action that matters most on a screen (PRD §14.2, Von Restorff);
/// everything else uses [NbButton.secondary].
///
/// Colours default to null and resolve from the active theme at build time —
/// a const default can't follow a runtime theme switch. Callers that pass an
/// explicit colour (the scan verdict inverts the button onto its own fill)
/// still win.
///
/// Touch target is >= 48px tall (Fitts's Law, CLAUDE.md §11.2 / §12.1).
class NbButton extends StatelessWidget {
  const NbButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.intensity = NbIntensity.full,
    this.background,
    this.foreground,
    this.busy = false,
  }) : _secondary = false;

  const NbButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.background,
    this.foreground,
  })  : intensity = NbIntensity.restrained,
        _secondary = true;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NbIntensity intensity;
  final Color? background;
  final Color? foreground;
  final bool busy;
  final bool _secondary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final disabled = onPressed == null || busy;
    final bg = background ?? (_secondary ? t.color.surface : t.color.accent);
    final fg = foreground ?? (_secondary ? t.color.ink : t.color.on(bg));

    return Semantics(
      button: true,
      enabled: !disabled,
      label: label,
      child: PressEffect(
        onTap: disabled ? null : onPressed,
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
                horizontal: NbSpace.lg, vertical: NbSpace.md),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: t.shape.radius,
              border: Border.all(
                  color: t.color.border, width: intensity.borderWidth(t.shape)),
              boxShadow: disabled ? const [] : intensity.shadow(t.shape),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child:
                        CircularProgressIndicator(strokeWidth: 2.5, color: fg),
                  )
                else if (icon != null)
                  Icon(icon, size: 20, color: fg),
                if (busy || icon != null) const SizedBox(width: NbSpace.sm),
                Text(label,
                    style: t.text.label.copyWith(color: fg, fontSize: 15)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
