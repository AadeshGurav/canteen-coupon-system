import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_mode.dart';
import '../core/role.dart';
import '../ui/admin/admin_dashboard.dart';
import '../ui/auth/login_screen.dart';
import '../ui/client/discover_screen.dart';
import '../ui/counter/counter_home.dart';
import '../ui/scanner/scanner_screen.dart';
import '../ui/shared_widgets/brand_splash.dart';
import '../ui/shared_widgets/nb_button.dart';
import '../ui/shared_widgets/nb_feedback.dart';
import '../ui/shared_widgets/nb_surface.dart';
import '../ui/theme/tokens.dart';
import 'providers.dart';

/// The single routing decision (kept flat, CLAUDE.md §3):
///
///  1. no mode chosen        → mode picker
///  2. host, container ready? → wait / show error (+ auto-start serving)
///  3. not signed in         → sign-in (host) or host discovery (client)
///  4. signed in             → the role's home
class ModeGate extends ConsumerWidget {
  const ModeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(currentModeProvider);
    if (mode == null) return const _ModePicker();

    final session = ref.watch(sessionProvider);

    if (mode == AppMode.host) {
      ref.watch(hostWakelockProvider); // keep the screen awake while serving
      final container = ref.watch(hostContainerProvider);
      return container.when(
        loading: () => const BrandSplash(message: 'Preparing database…'),
        error: (e, _) => Scaffold(
          body: Center(child: ErrorPanel(error: e)),
        ),
        data: (_) {
          // A host serves — bring the LAN server up the moment the database is
          // ready, before anyone signs in, so clients can connect straight
          // away. Start/stop/certificate controls live in Admin ▸ Hosting.
          Future.microtask(
              () => ref.read(hostServingProvider.notifier).ensureStarted());
          return session == null
              ? const LoginScreen()
              : _roleHome(session.role);
        },
      );
    }

    // client
    if (session == null) return const DiscoverScreen();
    return _roleHome(session.role);
  }

  Widget _roleHome(Role role) => switch (role) {
        Role.scanner => const ScannerScreen(isRoleHome: true),
        Role.counter => const CounterHome(),
        Role.admin => const AdminDashboard(),
      };
}

class _ModePicker extends ConsumerWidget {
  const _ModePicker();

  Future<void> _choose(WidgetRef ref, AppMode mode) async {
    await ref.read(currentModeProvider.notifier).set(mode);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(NbSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Image.asset('assets/icon/icon_foreground.png',
                          width: 48, height: 48),
                      const SizedBox(width: NbSpace.sm),
                      Text('TIFFIN',
                          style: NbType.display.copyWith(letterSpacing: 2)),
                    ],
                  ),
                  const SizedBox(height: NbSpace.lg),
                  const Text('Set up this device', style: NbType.heading),
                  const SizedBox(height: NbSpace.sm),
                  const Text(
                      'One app, two roles. You can change this later '
                      'from Settings — your data stays put.',
                      style: NbType.body),
                  const SizedBox(height: NbSpace.xl),
                  _ModeCard(
                    name: 'HOST',
                    blurb: 'This device runs the database and server for the '
                        'canteen. Other devices connect to it. Pick this for '
                        'the phone that stays at the canteen.',
                    action: 'Run as host',
                    onTap: () => _choose(ref, AppMode.host),
                    primary: true,
                  ),
                  const SizedBox(height: NbSpace.md),
                  _ModeCard(
                    name: 'CLIENT',
                    blurb: 'This device connects to a host on the same Wi-Fi. '
                        'Pick this for a counter or scan-point phone.',
                    action: 'Run as client',
                    onTap: () => _choose(ref, AppMode.client),
                    primary: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.name,
    required this.blurb,
    required this.action,
    required this.onTap,
    required this.primary,
  });

  final String name;
  final String blurb;
  final String action;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return NbSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: NbType.heading),
          const SizedBox(height: NbSpace.xs),
          Text(blurb, style: NbType.body),
          const SizedBox(height: NbSpace.md),
          primary
              ? NbButton(label: action, onPressed: onTap)
              : NbButton.secondary(label: action, onPressed: onTap),
        ],
      ),
    );
  }
}
