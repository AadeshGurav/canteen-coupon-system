import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_logo.dart';
import 'motion.dart';

/// The in-app landing / loading screen — the same ticket mark and ground as
/// the native splash, so the hand-off from OS splash to Flutter is seamless.
/// [message] adds a spinner + line while something is preparing.
class BrandSplash extends StatelessWidget {
  const BrandSplash({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.color.surfaceBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Entrance(child: AppLogo(size: 132)),
            const SizedBox(height: NbSpace.md),
            Entrance(
              index: 1,
              child: Text('TIFFIN',
                  style: t.text.display.copyWith(letterSpacing: 2)),
            ),
            if (message != null) ...[
              const SizedBox(height: NbSpace.lg),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: t.color.ink),
                  ),
                  const SizedBox(width: NbSpace.sm),
                  Text(message!, style: t.text.body),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
