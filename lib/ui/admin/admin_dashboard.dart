import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_mode.dart';
import '../scanner/scanner_screen.dart';
import '../shared_widgets/app_shell.dart';
import '../shared_widgets/nb_surface.dart';
import '../theme/tokens.dart';
import 'expenses_screen.dart';
import 'hosting_screen.dart';
import 'ingredients_screen.dart';
import 'members_screen.dart';
import 'menu_categories_screen.dart';
import 'menu_screen.dart';
import 'purchase_schedule_screen.dart';
import 'recipes_screen.dart';
import 'refunds_screen.dart';
import 'scan_log_screen.dart';
import 'settings_screen.dart';
import 'topup_screen.dart';
import 'users_screen.dart';

/// Admin home — a flat grid of destinations (Hick's Law: staged, not one long
/// menu). Restrained neobrutalism intensity, this is a navigation surface not
/// an action moment (PRD §14.2).
class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final username = ref.watch(sessionProvider)?.username ?? '';
    final isHost = ref.watch(currentModeProvider) == AppMode.host;
    final serving = isHost && ref.watch(hostRunningProvider);
    // Grouped by domain, and coloured by it: fourteen identical boxes are a
    // wall to scan, four colour families are four places to look. The tone
    // never carries state, so nothing is lost if it isn't seen (§12.2).
    final destinations = <_Dest>[
      _Dest('Scan', Icons.qr_code_scanner, NbTone.members,
          () => const ScannerScreen()),
      _Dest(
          'Members', Icons.people, NbTone.members, () => const MembersScreen()),
      _Dest('Scan log', Icons.history, NbTone.members,
          () => const ScanLogScreen()),
      _Dest('Top-up & bill', Icons.payments, NbTone.money,
          () => const TopUpScreen()),
      _Dest('Expenses & revenue', Icons.receipt_long, NbTone.money,
          () => const ExpensesScreen()),
      _Dest('Refunds', Icons.undo, NbTone.money, () => const RefundsScreen()),
      _Dest('Menu calendar', Icons.calendar_month, NbTone.kitchen,
          () => const MenuScreen()),
      _Dest('Menu categories', Icons.category, NbTone.kitchen,
          () => const MenuCategoriesScreen()),
      _Dest('Ingredients', Icons.egg_alt, NbTone.kitchen,
          () => const IngredientsScreen()),
      _Dest('Recipes', Icons.menu_book, NbTone.kitchen,
          () => const RecipesScreen()),
      _Dest('Purchase schedule', Icons.shopping_cart, NbTone.kitchen,
          () => const PurchaseScheduleScreen()),
      _Dest('Settings', Icons.settings, NbTone.system,
          () => const SettingsScreen()),
      _Dest('Users', Icons.admin_panel_settings, NbTone.system,
          () => const UsersScreen()),
      if (isHost)
        _Dest('Hosting & LAN', Icons.wifi_tethering, NbTone.system,
            () => const HostingScreen()),
    ];

    void openHosting() => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const HostingScreen()),
        );

    return Scaffold(
      appBar: NbAppBar(title: 'Admin · $username'),
      body: Column(
        children: [
          if (isHost && !serving)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  NbSpace.md, NbSpace.md, NbSpace.md, 0),
              child: NbSurface(
                intensity: NbIntensity.full,
                background: t.color.warn,
                onTap: openHosting,
                child: Row(
                  children: [
                    Icon(Icons.wifi_off, color: t.color.onWarn),
                    const SizedBox(width: NbSpace.sm),
                    Expanded(
                      child: Text(
                        'Not serving on the LAN — other devices can\'t '
                        'connect. Tap to open Hosting.',
                        style: t.text.body.copyWith(color: t.color.onWarn),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(NbSpace.md),
              crossAxisCount: 2,
              mainAxisSpacing: NbSpace.md,
              crossAxisSpacing: NbSpace.md,
              childAspectRatio: 1.3,
              children: [
                for (final d in destinations)
                  NbSurface(
                    tone: d.tone,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => d.build()),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(d.icon,
                            size: 36, color: t.color.on(t.color.tone(d.tone))),
                        const SizedBox(height: NbSpace.sm),
                        Text(d.label,
                            textAlign: TextAlign.center, style: t.text.label),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dest {
  _Dest(this.label, this.icon, this.tone, this.build);
  final String label;
  final IconData icon;

  /// Which domain this destination belongs to — members, money, kitchen or
  /// system. Drives the tile colour only.
  final NbTone tone;
  final Widget Function() build;
}
