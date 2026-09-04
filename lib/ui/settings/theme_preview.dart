import 'package:flutter/material.dart';

import '../theme/theme_catalog.dart';
import '../theme/tokens.dart';

/// A row for one theme, showing a miniature rendered in *that* theme's own
/// tokens rather than the current one.
///
/// Picking a theme from a list of names is guesswork; the point of a preview
/// is that the border weight, corner radius, shadow and palette are all
/// visible before committing (recognition over recall, §11.1 heuristic 6).
class ThemePreviewCard extends StatelessWidget {
  const ThemePreviewCard({
    super.key,
    required this.id,
    required this.brightness,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final TiffinThemeId id;
  final Brightness brightness;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final host = context.tokens;
    final preview = id.tokens(brightness);

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(NbSpace.sm),
          decoration: BoxDecoration(
            color: host.color.surface,
            borderRadius: host.shape.radius,
            border: Border.all(
              color: selected ? host.color.accent : host.color.border,
              width: selected ? host.shape.borderBold : host.shape.borderBase,
            ),
            boxShadow: selected ? host.shape.shadowFull : const [],
          ),
          child: Row(
            children: [
              _Miniature(tokens: preview),
              const SizedBox(width: NbSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(id.label, style: host.text.heading),
                    const SizedBox(height: NbSpace.xs),
                    Text(id.blurb,
                        style: host.text.body.copyWith(
                            color: host.color.inkMuted, fontSize: 14)),
                  ],
                ),
              ),
              const SizedBox(width: NbSpace.sm),
              // Selection is a check, not just a border colour (§12.2).
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? host.color.accent : host.color.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A scaled-down mock of a screen in [tokens]: page ground, a card, a primary
/// button, and the four category tones.
class _Miniature extends StatelessWidget {
  const _Miniature({required this.tokens});

  final TiffinTokens tokens;

  @override
  Widget build(BuildContext context) {
    final c = tokens.color;
    final s = tokens.shape;

    return Container(
      width: 84,
      height: 84,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: c.surfaceBg,
        borderRadius: s.radius,
        border: Border.all(color: c.border, width: s.borderHair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A card, carrying this theme's border weight and shadow.
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: s.radius,
                border: Border.all(color: c.border, width: s.borderBase),
                boxShadow: s.shadowRestrained,
              ),
              child: Center(
                child: Container(
                  height: 4,
                  width: 30,
                  color: c.inkMuted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final tone in NbTone.values)
                if (tone != NbTone.neutral)
                  Expanded(
                    child: Container(
                      height: 12,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: c.tone(tone),
                        borderRadius: s.radius,
                        border:
                            Border.all(color: c.border, width: s.borderHair),
                      ),
                    ),
                  ),
              Container(
                height: 12,
                width: 16,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: s.radius,
                  border: Border.all(color: c.border, width: s.borderHair),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
