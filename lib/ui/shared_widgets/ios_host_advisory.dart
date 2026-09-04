import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'nb_surface.dart';

/// The honest fine print for hosting on an iPhone. iOS gives an app no way to
/// keep a server alive in the background and no way to create its own network,
/// so the operator has to know this up front — shown on first host setup and in
/// Admin → Hosting, never buried in a doc.
class IosHostAdvisory extends StatelessWidget {
  const IosHostAdvisory({super.key});

  static const _points = [
    'Keep Tiffin open and on screen while you host. iOS stops the server the '
        'moment you lock the phone or switch apps, and every connected device '
        'drops.',
    "iOS can't make its own Wi-Fi. Every device must be on the same Wi-Fi "
        'router — or turn on Personal Hotspot (Settings ▸ Personal Hotspot) and '
        'have the others join it.',
    'For a full meal service, host on an Android phone instead — it keeps '
        'serving with the screen off.',
  ];

  @override
  Widget build(BuildContext context) {
    return NbSurface(
      intensity: NbIntensity.full,
      background: NbColors.warn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HOSTING ON IPHONE — READ THIS',
              style: NbType.label.copyWith(color: NbColors.onWarn)),
          for (final p in _points)
            Padding(
              padding: const EdgeInsets.only(top: NbSpace.xs),
              child: Text('•  $p',
                  style: NbType.body.copyWith(color: NbColors.onWarn)),
            ),
        ],
      ),
    );
  }
}
