import 'package:canteen_coupon/ui/shared_widgets/app_logo.dart';
import 'package:canteen_coupon/ui/shared_widgets/brand_splash.dart';
import 'package:canteen_coupon/ui/shared_widgets/nb_button.dart';
import 'package:canteen_coupon/ui/shared_widgets/nb_surface.dart';
import 'package:canteen_coupon/ui/shared_widgets/nb_text_field.dart';
import 'package:canteen_coupon/ui/theme/app_theme.dart';
import 'package:canteen_coupon/ui/theme/theme_catalog.dart';
import 'package:canteen_coupon/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders every shared primitive under all eight theme variants.
///
/// The token migration replaced ~313 compile-time constants with values
/// resolved from context. A missed one no longer fails to compile — it throws
/// at build time, on one screen, under one theme. This is the cheap way to
/// find that without a device.
void main() {
  Widget gallery(TextEditingController number) => Builder(
        builder: (context) {
          final t = context.tokens;
          return Scaffold(
            appBar: AppBar(title: const Text('Gallery')),
            body: ListView(
              padding: const EdgeInsets.all(NbSpace.md),
              children: [
                const AppLogo(),
                const AppWordmark(),
                for (final tone in NbTone.values)
                  NbSurface(
                    tone: tone,
                    intensity: NbIntensity.restrained,
                    child: Text(tone.name, style: t.text.body),
                  ),
                NbSurface(
                  intensity: NbIntensity.full,
                  background: t.color.warn,
                  child: Text('warning', style: t.text.label),
                ),
                NbButton(label: 'Primary', onPressed: () {}),
                const NbButton.secondary(label: 'Secondary', onPressed: null),
                NbButton(label: 'Busy', busy: true, onPressed: () {}),
                const NbTextField(label: 'Field'),
                NbNumberField(label: 'Number', controller: number),
              ],
            ),
          );
        },
      );

  for (final id in TiffinThemeId.values) {
    for (final brightness in Brightness.values) {
      final label = '${id.wire}/${brightness.name}';

      testWidgets('$label renders every shared primitive', (tester) async {
        final number = TextEditingController();
        addTearDown(number.dispose);
        await tester.pumpWidget(MaterialApp(
          theme: buildTiffinTheme(id, brightness),
          home: gallery(number),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      });

      testWidgets('$label renders the splash', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: buildTiffinTheme(id, brightness),
          home: const BrandSplash(message: 'Preparing…'),
        ));
        await tester.pump();
        expect(find.text('TIFFIN'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$label survives a narrow 320px viewport', (tester) async {
        // The reflow floor (§11.6.9): no overflow, nothing clipped.
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final number = TextEditingController();
        addTearDown(number.dispose);

        await tester.pumpWidget(MaterialApp(
          theme: buildTiffinTheme(id, brightness),
          home: gallery(number),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('tokens are attached to every theme this app builds',
      (tester) async {
    for (final id in TiffinThemeId.values) {
      late TiffinTokens? seen;
      await tester.pumpWidget(MaterialApp(
        theme: buildTiffinTheme(id, Brightness.light),
        home: Builder(builder: (context) {
          seen = context.maybeTokens;
          return const SizedBox();
        }),
      ));
      expect(seen, isNotNull, reason: '${id.wire} has no TiffinTokens');
    }
  });

  testWidgets('motion:false collapses the theme to still', (tester) async {
    late MotionTokens motion;
    await tester.pumpWidget(MaterialApp(
      theme:
          buildTiffinTheme(TiffinThemeId.clay, Brightness.light, motion: false),
      home: Builder(builder: (context) {
        motion = context.tokens.motion;
        return const SizedBox();
      }),
    ));
    expect(motion.isStill, isTrue);
    expect(motion.pressScale, 1.0);
  });

  testWidgets('reduceTransparency makes Frost opaque', (tester) async {
    late TiffinShape shape;
    await tester.pumpWidget(MaterialApp(
      theme: buildTiffinTheme(TiffinThemeId.frost, Brightness.light,
          reduceTransparency: true),
      home: Builder(builder: (context) {
        shape = context.tokens.shape;
        return const SizedBox();
      }),
    ));
    expect(shape.isTranslucent, isFalse);
  });
}
