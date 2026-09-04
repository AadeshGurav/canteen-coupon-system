import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../shared_widgets/copyable_url.dart';
import '../shared_widgets/ios_host_advisory.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_surface.dart';
import '../theme/tokens.dart';

/// Admin ▸ Hosting — the LAN server controls that used to live on a pre-login
/// console. Start/stop serving, see the URLs other devices use, and generate
/// the optional desktop-browser TLS certificate. Host mode only.
class HostingScreen extends ConsumerWidget {
  const HostingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serving = ref.watch(hostServingProvider);
    final ctrl = ref.read(hostServingProvider.notifier);
    final running = serving.running;
    final server = running ? ref.watch(hostServerProvider) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Hosting & LAN')),
      body: ListView(
        padding: const EdgeInsets.all(NbSpace.lg),
        children: [
          if (Platform.isIOS) ...[
            const IosHostAdvisory(),
            const SizedBox(height: NbSpace.md),
          ],

          // Status + start/stop -------------------------------------------
          NbSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(running ? Icons.check_circle : Icons.circle_outlined,
                        color: running ? NbColors.accept : NbColors.ink),
                    const SizedBox(width: NbSpace.sm),
                    Text(running ? 'SERVING ON LAN' : 'NOT SERVING',
                        style: NbType.heading),
                  ],
                ),
                if (running && server != null) ...[
                  const SizedBox(height: NbSpace.sm),
                  Text(
                    'Client phones connect on port ${server.httpPort}'
                    '${server.httpsPort != null ? ' · desktop HTTPS on ${server.httpsPort}' : ''}',
                    style: NbType.body,
                  ),
                ],
                if (!serving.discoveryOk) ...[
                  const SizedBox(height: NbSpace.sm),
                  Text(
                    'Auto-discovery is off (no Wi-Fi router reachable). Clients '
                    'can still connect with "Connect by IP address" using the '
                    'address below.',
                    style: NbType.body.copyWith(color: NbColors.reject),
                  ),
                ],
                if (serving.lastError != null) ...[
                  const SizedBox(height: NbSpace.sm),
                  Text(serving.lastError!,
                      style: NbType.body.copyWith(color: NbColors.reject)),
                ],
                const SizedBox(height: NbSpace.md),
                if (!running)
                  NbButton(
                    label: 'Start serving',
                    icon: Icons.play_arrow,
                    busy: serving.busy,
                    onPressed: serving.busy ? null : ctrl.start,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: NbButton(
                          label: 'Stop',
                          icon: Icons.stop,
                          background: NbColors.reject,
                          foreground: NbColors.onReject,
                          busy: serving.busy,
                          onPressed: serving.busy ? null : ctrl.stop,
                        ),
                      ),
                      const SizedBox(width: NbSpace.sm),
                      Expanded(
                        child: NbButton.secondary(
                          label: 'Restart',
                          icon: Icons.refresh,
                          busy: serving.busy,
                          onPressed: serving.busy ? null : ctrl.restart,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: NbSpace.md),

          // LAN URLs -----------------------------------------------------
          if (running)
            ref.watch(lanUrlsProvider).maybeWhen(
                  data: (urls) => NbSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DESKTOP ADMIN', style: NbType.label),
                        const SizedBox(height: NbSpace.xs),
                        if (urls.http.isEmpty)
                          const Text('No LAN address — check Wi-Fi.',
                              style: NbType.body)
                        else ...[
                          const Text(
                              'Open in a browser on the same Wi-Fi '
                              '(tap to copy):',
                              style: NbType.body),
                          for (final u in urls.http) CopyableUrl(url: u),
                          if (urls.https.isNotEmpty) ...[
                            const SizedBox(height: NbSpace.xs),
                            const Text(
                                'Encrypted (one "not trusted" warning per '
                                'computer):',
                                style: NbType.label),
                            for (final u in urls.https) CopyableUrl(url: u),
                          ],
                        ],
                      ],
                    ),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
          if (running) const SizedBox(height: NbSpace.md),

          // Keep awake -------------------------------------------------
          NbSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('KEEP THIS DEVICE AWAKE', style: NbType.label),
                const SizedBox(height: NbSpace.xs),
                Text(
                  Platform.isIOS
                      ? 'While serving, the screen is held awake. Leave the app '
                          'in the foreground — backgrounding it on iOS stops the '
                          'server.'
                      : 'While serving, the screen is held awake and a '
                          'foreground service keeps the server running. Keep the '
                          'phone on power and on Wi-Fi; don\'t force-stop the app.',
                  style: NbType.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: NbSpace.md),

          // TLS cert -------------------------------------------------
          NbSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DESKTOP-ADMIN TLS (OPTIONAL)', style: NbType.label),
                const SizedBox(height: NbSpace.xs),
                const Text(
                  'Encrypts admin login over the LAN. A self-signed certificate '
                  'still shows a browser "not trusted" warning the first time '
                  'each computer connects. It never affects phone-to-phone use. '
                  'Restart serving after generating.',
                  style: NbType.body,
                ),
                if (serving.certExpiry != null) ...[
                  const SizedBox(height: NbSpace.xs),
                  Text('Current certificate valid until ${serving.certExpiry}',
                      style: NbType.body),
                ],
                const SizedBox(height: NbSpace.md),
                NbButton.secondary(
                  label: 'Generate certificate',
                  busy: serving.busy,
                  onPressed: serving.busy ? null : ctrl.generateCert,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
