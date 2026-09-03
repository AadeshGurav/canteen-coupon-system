import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../discovery/discovery.dart';
import '../auth/login_screen.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../theme/tokens.dart';

/// Client mode: pick a host found on the LAN (PRD §13.5) — recognition over
/// recall (CLAUDE.md §11.1 #6), no IP typing. Picking one moves to sign-in.
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(discoveredHostsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FIND HOST'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Change mode',
            onPressed: () async {
              await ref.read(appModeStoreProvider).clear();
              ref.invalidate(appModeStoreProvider);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(NbSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Canteen devices on this Wi-Fi', style: NbType.heading),
            const SizedBox(height: NbSpace.md),
            Expanded(
              child: AsyncView<List<DiscoveredHost>>(
                value: hosts,
                onRetry: () => ref.invalidate(discoveredHostsProvider),
                builder: (list) {
                  if (list.isEmpty) {
                    return const _Searching();
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: NbSpace.sm),
                    itemBuilder: (_, i) {
                      final host = list[i];
                      return NbSurface(
                        onTap: () {
                          ref.read(selectedHostProvider.notifier).state = host;
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            const Icon(Icons.dns, color: NbColors.ink),
                            const SizedBox(width: NbSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(host.name, style: NbType.body),
                                  Text('${host.host}:${host.port}',
                                      style: NbType.label),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: NbSpace.md),
            NbButton.secondary(
              label: 'Search again',
              onPressed: () => ref.invalidate(discoveredHostsProvider),
            ),
          ],
        ),
      ),
    );
  }
}

class _Searching extends StatelessWidget {
  const _Searching();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: NbColors.ink),
          SizedBox(height: NbSpace.md),
          Text('Looking for a host…', style: NbType.body),
          SizedBox(height: NbSpace.xs),
          Text(
              'Make sure a device here is running in host mode\n'
              'and both are on the same Wi-Fi.',
              textAlign: TextAlign.center,
              style: NbType.label),
        ],
      ),
    );
  }
}
