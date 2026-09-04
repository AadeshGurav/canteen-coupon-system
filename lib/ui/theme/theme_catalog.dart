import 'package:flutter/material.dart';

import 'themes/clay.dart';
import 'themes/clean.dart';
import 'themes/frost.dart';
import 'themes/neobrutal.dart';
import 'tokens.dart';

/// The themes a device can be set to. Each ships a light and a dark variant —
/// dark is a mode, not a fifth theme (CLAUDE.md §11.5.10).
///
/// [wire] is the stored/transmitted name: it must stay stable, because it is
/// persisted per device and can also be pushed from the host.
enum TiffinThemeId {
  neobrutal(
    wire: 'neobrutal',
    label: 'Neobrutal',
    blurb: 'Hard borders, offset shadows, loud colour. The Tiffin original.',
  ),
  clean(
    wire: 'clean',
    label: 'Clean',
    blurb: 'Flat and quiet. Easiest on the eyes for a long admin shift.',
  ),
  frost(
    wire: 'frost',
    label: 'Frost',
    blurb: 'Frosted glass bars and sheets over solid content.',
  ),
  clay(
    wire: 'clay',
    label: 'Clay',
    blurb: 'Soft, round and warm. Friendliest of the four.',
  );

  const TiffinThemeId({
    required this.wire,
    required this.label,
    required this.blurb,
  });

  final String wire;
  final String label;
  final String blurb;

  /// Falls back to the default rather than throwing: a theme name can arrive
  /// from another device's settings, and an unknown one should degrade to a
  /// usable app rather than a crash on launch.
  static TiffinThemeId fromWire(String? wire) => values.firstWhere(
        (t) => t.wire == wire,
        orElse: () => defaultTheme,
      );

  /// A fresh install opens on the app's own identity.
  static const defaultTheme = TiffinThemeId.neobrutal;

  TiffinTokens tokens(Brightness brightness) => switch (this) {
        TiffinThemeId.neobrutal => buildNeobrutal(brightness),
        TiffinThemeId.clean => buildClean(brightness),
        TiffinThemeId.frost => buildFrost(brightness),
        TiffinThemeId.clay => buildClay(brightness),
      };
}
