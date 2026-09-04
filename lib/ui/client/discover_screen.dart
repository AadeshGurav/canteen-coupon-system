import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config.dart';
import '../../discovery/discovery.dart';
import '../auth/login_screen.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../theme/tokens.dart';

/// Client mode: pick a host found on the LAN (PRD §13.5) — recognition over
/// recall (CLAUDE.md §11.1 #6). Auto-discovery is the happy path; a manual
/// "connect by IP" fallback covers routers that block mDNS between devices
/// (guest networks, AP isolation) and iOS hosts that never got Local Network
/// permission (CLAUDE.md §4.6 graceful degradation, §11.1 #3 user control).
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  void _connect(BuildContext context, WidgetRef ref, DiscoveredHost host) {
    ref.read(selectedHostProvider.notifier).state = host;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _enterManually(BuildContext context, WidgetRef ref) async {
    final host = await showDialog<DiscoveredHost>(
      context: context,
      builder: (_) => const _ManualHostDialog(),
    );
    if (host != null && context.mounted) _connect(context, ref, host);
  }

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
              await ref.read(currentModeProvider.notifier).clear();
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
                        onTap: () => _connect(context, ref, host),
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
            const SizedBox(height: NbSpace.sm),
            NbButton.secondary(
              label: 'Connect by IP address',
              icon: Icons.keyboard,
              onPressed: () => _enterManually(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fallback when mDNS can't cross the network: type the host's IP (shown on its
/// console under DESKTOP ADMIN) and port.
class _ManualHostDialog extends StatefulWidget {
  const _ManualHostDialog();

  @override
  State<_ManualHostDialog> createState() => _ManualHostDialogState();
}

class _ManualHostDialogState extends State<_ManualHostDialog> {
  final _ip = TextEditingController();
  final _port =
      TextEditingController(text: '${AppConfig.defaultServerPort}');
  String? _error;

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    super.dispose();
  }

  void _submit() {
    final ip = _ip.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (ip.isEmpty || port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Enter a valid IP and port.');
      return;
    }
    Navigator.of(context).pop(
      DiscoveredHost(name: 'Host at $ip', host: ip, port: port),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect by IP'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ip,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Host IP',
              hintText: '192.168.1.42',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: NbSpace.sm),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Port'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: NbSpace.sm),
            Text(_error!,
                style: NbType.label.copyWith(color: NbColors.reject)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Connect')),
      ],
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
