@Tags(['tool'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiffin/ui/shared_widgets/app_logo.dart';
import 'package:tiffin/ui/theme/theme_catalog.dart';

/// Rasterises one launcher icon per theme, from the *same* painter the in-app
/// logo uses — so the home-screen icon and the mark inside the app cannot
/// drift apart, and there is no hand-made copy to keep in sync.
///
/// This is a generator rather than an assertion, so it is tagged `tool` and
/// excluded from the normal suite (see dart_test.yaml). Run it with:
///
///     make icons
///
/// It writes `assets/icon/themes/<theme>.png` (full-bleed, for iOS and the
/// legacy Android icon) and `<theme>_foreground.png` (padded, for Android's
/// adaptive foreground layer, which crops to a safe zone).
void main() {
  const size = 1024.0;

  /// Android crops an adaptive foreground to roughly the middle 66%, so the
  /// mark is drawn smaller inside a transparent canvas for that layer.
  Future<void> render(
    File target, {
    required TiffinThemeId theme,
    required bool adaptive,
  }) async {
    final tokens = theme.tokens(Brightness.light);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (!adaptive) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, size, size),
        Paint()..color = tokens.color.surfaceBg,
      );
    }

    final markSize = adaptive ? size * 0.52 : size * 0.72;
    final offset = (size - markSize) / 2;
    canvas
      ..save()
      ..translate(offset, offset);
    tiffinMarkPainter(tokens, markSize).paint(canvas, Size(markSize, markSize));
    canvas.restore();

    final image =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  }

  testWidgets('generate launcher icons for every theme', (tester) async {
    final dir = Directory('assets/icon/themes');
    // runAsync: Picture.toImage() needs the real event loop. Under the test
    // binding's fake clock it simply never completes.
    await tester.runAsync(() async {
      for (final theme in TiffinThemeId.values) {
        await render(File('${dir.path}/${theme.wire}.png'),
            theme: theme, adaptive: false);
        await render(File('${dir.path}/${theme.wire}_foreground.png'),
            theme: theme, adaptive: true);
      }
    });

    // Fail loudly if a file did not land — a silently missing icon shows up as
    // a blank launcher entry, long after the fact.
    for (final theme in TiffinThemeId.values) {
      expect(File('${dir.path}/${theme.wire}.png').existsSync(), isTrue);
      expect(File('${dir.path}/${theme.wire}_foreground.png').existsSync(),
          isTrue);
    }
  });
}
