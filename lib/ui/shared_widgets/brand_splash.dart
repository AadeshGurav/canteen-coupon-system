import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The in-app landing / loading screen — the same ticket mark and ground as
/// the native splash, so the hand-off from OS splash to Flutter is seamless.
/// [message] adds a spinner + line while something is preparing.
class BrandSplash extends StatelessWidget {
  const BrandSplash({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NbColors.surfaceBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icon/icon_foreground.png',
              width: 132,
              height: 132,
              filterQuality: FilterQuality.medium,
            ),
            const SizedBox(height: NbSpace.md),
            Text('TIFFIN', style: NbType.display.copyWith(letterSpacing: 2)),
            if (message != null) ...[
              const SizedBox(height: NbSpace.lg),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: NbColors.ink),
                  ),
                  const SizedBox(width: NbSpace.sm),
                  Text(message!, style: NbType.body),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
