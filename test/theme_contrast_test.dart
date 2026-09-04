import 'package:tiffin/ui/theme/oklch.dart';
import 'package:tiffin/ui/theme/theme_catalog.dart';
import 'package:tiffin/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG AA is the floor for every theme, not a target (CLAUDE.md §11.5.0
/// rule 3). Four themes x light/dark is eight palettes, which is far too many
/// to eyeball — so every foreground/background pair the UI can actually
/// produce is asserted here. This is what keeps Clay's pastels and Frost's
/// tinted surfaces honest when someone retunes a hue later.
void main() {
  const bodyMin = 4.5; // normal text
  const uiMin = 3.0; // large text, icons, meaningful boundaries

  void expectContrast(
    Color fg,
    Color bg,
    double min, {
    required String what,
  }) {
    final ratio = contrastRatio(fg, bg);
    expect(
      ratio,
      greaterThanOrEqualTo(min),
      reason: '$what is ${ratio.toStringAsFixed(2)}:1, needs $min:1',
    );
  }

  for (final id in TiffinThemeId.values) {
    for (final brightness in Brightness.values) {
      final label = '${id.wire}/${brightness.name}';

      group(label, () {
        final tokens = id.tokens(brightness);
        final c = tokens.color;

        test('body text on every content surface', () {
          expectContrast(c.ink, c.surfaceBg, bodyMin, what: '$label ink/bg');
          expectContrast(c.ink, c.surface, bodyMin, what: '$label ink/surface');
          expectContrast(c.ink, c.surfaceMuted, bodyMin,
              what: '$label ink/muted');
        });

        test('secondary text stays readable', () {
          expectContrast(c.inkMuted, c.surfaceBg, bodyMin,
              what: '$label inkMuted/bg');
          expectContrast(c.inkMuted, c.surface, bodyMin,
              what: '$label inkMuted/surface');
        });

        test('derived text on accent and status fills', () {
          for (final (name, fill) in [
            ('accent', c.accent),
            ('accept', c.accept),
            ('reject', c.reject),
            ('warn', c.warn),
          ]) {
            expectContrast(c.on(fill), fill, bodyMin, what: '$label on/$name');
          }
        });

        test('derived text on every category tone', () {
          for (final tone in NbTone.values) {
            final fill = c.tone(tone);
            expectContrast(c.on(fill), fill, bodyMin,
                what: '$label on/${tone.name}');
          }
        });

        // WCAG 1.4.11 asks that a component be distinguishable from what's
        // next to it — not that any one token carry that on its own. A card is
        // identifiable if EITHER its border or its fill separates it from the
        // page, which is why Neobrutal can use a pastel tile behind a 3px ink
        // border while Clean must earn it with the border alone.
        test('every tappable surface is identifiable against the page', () {
          double separation(Color fill) => [
                contrastRatio(c.border, c.surfaceBg),
                contrastRatio(fill, c.surfaceBg),
              ].reduce((a, b) => a > b ? a : b);

          expect(separation(c.surface), greaterThanOrEqualTo(uiMin),
              reason: '$label: a card is indistinguishable from the page');
          for (final tone in NbTone.values) {
            expect(separation(c.tone(tone)), greaterThanOrEqualTo(uiMin),
                reason: '$label: the ${tone.name} tile has no visible edge');
          }
        });

        test('the focus ring is distinguishable from the page', () {
          expectContrast(c.accent, c.surfaceBg, uiMin,
              what: '$label accent/bg');
          expectContrast(c.accent, c.surface, uiMin,
              what: '$label accent/surface');
        });

        test('dark mode avoids pure black and pure white', () {
          if (brightness != Brightness.dark) return;
          // Pure white on pure black causes halation and is fatiguing
          // (§11.5.10); both ends stay off the extremes.
          expect(relativeLuminance(c.surfaceBg), greaterThan(0.0),
              reason: '$label background is pure black');
          expect(relativeLuminance(c.ink), lessThan(1.0),
              reason: '$label ink is pure white');
        });
      });
    }
  }

  group('translucent chrome', () {
    test('only Frost is translucent, and it keeps a plate behind the blur', () {
      for (final id in TiffinThemeId.values) {
        final shape = id.tokens(Brightness.light).shape;
        if (id == TiffinThemeId.frost) {
          expect(shape.isTranslucent, isTrue);
          // Blur alone does not bound contrast, so a semi-opaque fill must sit
          // underneath — and the blur stays cheap enough for a mid-range GPU.
          expect(shape.chromeOpacity, greaterThanOrEqualTo(0.6));
          expect(shape.chromeBlur, lessThanOrEqualTo(16));
        } else {
          expect(shape.isTranslucent, isFalse, reason: '${id.wire} is opaque');
        }
      }
    });

    test('reduced transparency collapses Frost to a solid surface', () {
      final opaque = TiffinThemeId.frost.tokens(Brightness.light).shape.opaque;
      expect(opaque.isTranslucent, isFalse);
    });
  });

  group('motion', () {
    test('every theme stays inside the interaction budget', () {
      for (final id in TiffinThemeId.values) {
        final motion = id.tokens(Brightness.light).motion;
        expect(motion.isStill, isFalse);
        // Past ~300ms an interaction reads as slow rather than smooth.
        expect(motion.page.inMilliseconds, lessThanOrEqualTo(300));
        expect(motion.normal.inMilliseconds, lessThanOrEqualTo(300));
      }
    });

    test('still motion is genuinely zero everywhere', () {
      const still = MotionTokens.still;
      expect(still.isStill, isTrue);
      expect(still.fast, Duration.zero);
      expect(still.page, Duration.zero);
      expect(still.staggerStep, Duration.zero);
      expect(still.pressScale, 1.0);
    });
  });
}
