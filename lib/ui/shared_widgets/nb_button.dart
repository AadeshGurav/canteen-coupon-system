import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Primary/secondary action button. A full-intensity primary is reserved for
/// the one action that matters most on a screen (PRD §14.2, Von Restorff);
/// everything else uses [NbButton.secondary].
///
/// Touch target is >= 48px tall (Fitts's Law, CLAUDE.md §11.2 / §12.1).
class NbButton extends StatelessWidget {
  const NbButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.intensity = NbIntensity.full,
    this.background = NbColors.accent,
    this.foreground = NbColors.onAccent,
    this.busy = false,
  });

  const NbButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  })  : intensity = NbIntensity.restrained,
        background = NbColors.surface,
        foreground = NbColors.ink;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NbIntensity intensity;
  final Color background;
  final Color foreground;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || busy;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: label,
      child: GestureDetector(
        onTap: disabled ? null : onPressed,
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
                horizontal: NbSpace.lg, vertical: NbSpace.md),
            decoration: BoxDecoration(
              color: background,
              border:
                  Border.all(color: NbColors.ink, width: intensity.borderWidth),
              boxShadow: disabled ? const [] : intensity.shadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: foreground),
                  )
                else if (icon != null)
                  Icon(icon, size: 20, color: foreground),
                if (busy || icon != null) const SizedBox(width: NbSpace.sm),
                Text(label,
                    style:
                        NbType.label.copyWith(color: foreground, fontSize: 15)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
