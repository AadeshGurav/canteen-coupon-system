import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../admin/purchase_schedule_screen.dart';
import '../admin/topup_screen.dart';
import '../scanner/scanner_screen.dart';
import '../shared_widgets/app_shell.dart';
import '../shared_widgets/nb_surface.dart';
import '../theme/tokens.dart';

/// Counter-role home (PRD §4): scan, top-ups & billing, and the shared
/// purchase schedule — nothing else.
class CounterHome extends ConsumerWidget {
  const CounterHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = ref.watch(sessionProvider)?.username ?? '';
    final items = <(String, IconData, Widget Function())>[
      ('Scan', Icons.qr_code_scanner, () => const ScannerScreen()),
      ('Top-up & bill', Icons.payments, () => const TopUpScreen()),
      (
        'Purchase schedule',
        Icons.shopping_cart,
        () => const PurchaseScheduleScreen()
      ),
    ];

    return Scaffold(
      appBar: NbAppBar(title: 'Counter · $username'),
      body: ListView(
        padding: const EdgeInsets.all(NbSpace.md),
        children: [
          for (final (label, icon, build) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: NbSpace.md),
              child: NbSurface(
                intensity: NbIntensity.full,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => build()),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 32, color: NbColors.ink),
                    const SizedBox(width: NbSpace.md),
                    Text(label, style: NbType.heading),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
