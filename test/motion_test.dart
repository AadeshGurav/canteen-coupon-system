import 'package:canteen_coupon/ui/shared_widgets/motion.dart';
import 'package:canteen_coupon/ui/theme/app_theme.dart';
import 'package:canteen_coupon/ui/theme/theme_catalog.dart';
import 'package:canteen_coupon/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Motion has three independent off-switches and any one of them must win.
/// The system accessibility preference is the one worth guarding hardest: it
/// belongs to the viewer, not the app, and silently overriding it is exactly
/// the failure §11.5.0 rule 6 exists to prevent.
void main() {
  Future<MotionTokens> resolve(
    WidgetTester tester, {
    required bool themeMotion,
    bool disableAnimations = false,
    TiffinThemeId theme = TiffinThemeId.clay,
  }) async {
    late MotionTokens seen;
    await tester.pumpWidget(MaterialApp(
      theme: buildTiffinTheme(theme, Brightness.light, motion: themeMotion),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Builder(builder: (context) {
          seen = motionOf(context);
          return const SizedBox();
        }),
      ),
    ));
    // MaterialApp cross-fades between themes, and TiffinTokens.lerp snaps
    // geometry and motion at the midpoint — so one frame after a theme swap
    // still reports the outgoing theme. Let the transition finish.
    await tester.pumpAndSettle();
    return seen;
  }

  testWidgets('motion is on by default', (tester) async {
    final motion = await resolve(tester, themeMotion: true);
    expect(motion.isStill, isFalse);
  });

  testWidgets('the appearance setting turns it off', (tester) async {
    final motion = await resolve(tester, themeMotion: false);
    expect(motion.isStill, isTrue);
  });

  testWidgets("the phone's reduce-motion setting overrides the app's",
      (tester) async {
    final motion =
        await resolve(tester, themeMotion: true, disableAnimations: true);
    expect(motion.isStill, isTrue,
        reason: 'the OS preference belongs to the viewer and always wins');
  });

  testWidgets('each theme moves in its own way', (tester) async {
    final durations = <TiffinThemeId, Duration>{};
    final curves = <TiffinThemeId, Curve>{};
    for (final id in TiffinThemeId.values) {
      final motion = await resolve(tester, themeMotion: true, theme: id);
      durations[id] = motion.page;
      curves[id] = motion.entrance;
    }
    // Motion is part of a theme's personality, not a shared constant.
    expect(durations.values.toSet().length, greaterThan(1));
    expect(curves.values.toSet().length, greaterThan(1));
  });

  testWidgets('with motion off, a press does not scale the surface',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme:
          buildTiffinTheme(TiffinThemeId.clay, Brightness.light, motion: false),
      home: Scaffold(
        body: PressEffect(onTap: () {}, child: const Text('tap me')),
      ),
    ));
    expect(find.byType(AnimatedScale), findsNothing);
  });

  testWidgets('with motion on, a press scales the surface', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTiffinTheme(TiffinThemeId.clay, Brightness.light),
      home: Scaffold(
        body: PressEffect(onTap: () {}, child: const Text('tap me')),
      ),
    ));
    expect(find.byType(AnimatedScale), findsOneWidget);
  });

  testWidgets('a non-tappable surface gets no gesture wrapper', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTiffinTheme(TiffinThemeId.clay, Brightness.light),
      home: const Scaffold(body: PressEffect(child: Text('static'))),
    ));
    expect(find.byType(AnimatedScale), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('Entrance renders its child either way, and leaves no timer',
      (tester) async {
    for (final motion in [true, false]) {
      await tester.pumpWidget(MaterialApp(
        theme: buildTiffinTheme(TiffinThemeId.neobrutal, Brightness.light,
            motion: motion),
        home: Scaffold(
          body: Column(
            children: [
              for (var i = 0; i < 14; i++)
                Entrance(index: i, child: Text('tile $i')),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('tile 13'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a route pushed with motion off has no transition',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTiffinTheme(TiffinThemeId.frost, Brightness.light,
          motion: false),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              tiffinRoute<void>(context, () => const Text('second')),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    // A single frame is enough when there is no transition to play.
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
  });
}
