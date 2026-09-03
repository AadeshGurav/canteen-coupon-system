import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_mode.dart';
import '../ui/shared_widgets/nb_button.dart';
import '../ui/shared_widgets/nb_surface.dart';
import '../ui/theme/tokens.dart';
import 'bootstrap.dart';

/// First screen. If no [AppMode] is stored yet (first launch), asks the
/// operator to choose Host or Client (PRD §13.2). Otherwise routes straight in.
///
/// Hick's Law (CLAUDE.md §11.2): exactly two choices, each with a one-line
/// explanation of what it does — nothing else on the screen.
class ModeGate extends ConsumerWidget {
  const ModeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appModeStoreProvider);
    final mode = store.read();
    if (mode != null) return _ModeHome(mode: mode);
    return const _ModePicker();
  }
}

class _ModePicker extends ConsumerWidget {
  const _ModePicker();

  Future<void> _choose(WidgetRef ref, AppMode mode) async {
    await ref.read(appModeStoreProvider).write(mode);
    // A rebuild of ModeGate picks up the new value; force it.
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    ref.invalidate(appModeStoreProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(NbSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Set up this device', style: NbType.display),
                  const SizedBox(height: NbSpace.sm),
                  Text(
                    'One app, two roles. You can change this later.',
                    style: NbType.body,
                  ),
                  const SizedBox(height: NbSpace.xl),
                  NbSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('HOST', style: NbType.heading),
                        const SizedBox(height: NbSpace.xs),
                        Text(
                          'This device runs the database and server for the '
                          'canteen. Other devices connect to it. Pick this for '
                          'the phone that stays at the canteen.',
                          style: NbType.body,
                        ),
                        const SizedBox(height: NbSpace.md),
                        NbButton(
                          label: 'Run as host',
                          onPressed: () => _choose(ref, AppMode.host),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: NbSpace.md),
                  NbSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('CLIENT', style: NbType.heading),
                        const SizedBox(height: NbSpace.xs),
                        Text(
                          'This device connects to a host on the same Wi-Fi. '
                          'Pick this for a counter or scan-point phone.',
                          style: NbType.body,
                        ),
                        const SizedBox(height: NbSpace.md),
                        NbButton.secondary(
                          label: 'Run as client',
                          onPressed: () => _choose(ref, AppMode.client),
                        ),
                      ],
                    ),
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

/// Placeholder home for a chosen mode. Replaced by the host console / client
/// discovery screens as those land (see docs/PRD.md §13.2, §13.5).
class _ModeHome extends ConsumerWidget {
  const _ModeHome({required this.mode});

  final AppMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('Mode: ${mode.name}')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(NbSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                mode == AppMode.host
                    ? 'Host console — server start/stop, discovery, TLS cert, '
                        'connected clients — lands next.'
                    : 'Client discovery — find a host on the LAN — lands next.',
                style: NbType.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: NbSpace.lg),
              NbButton.secondary(
                label: 'Change mode',
                onPressed: () async {
                  await ref.read(appModeStoreProvider).clear();
                  ref.invalidate(appModeStoreProvider);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
