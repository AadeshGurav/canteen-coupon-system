import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/providers.dart';
import '../../discovery/hotspot.dart';
import '../shared_widgets/copyable_url.dart';
import '../shared_widgets/ios_host_advisory.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_feedback.dart';
import '../theme/tokens.dart';

/// Admin ▸ Hosting — the LAN server controls that used to live on a pre-login
/// console. Start/stop serving, see the URLs other devices use, and generate
/// the optional desktop-browser TLS certificate. Host mode only.
class HostingScreen extends ConsumerWidget {
  const HostingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
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
                        color: running ? t.color.accept : t.color.ink),
                    const SizedBox(width: NbSpace.sm),
                    Text(running ? 'SERVING ON LAN' : 'NOT SERVING',
                        style: t.text.heading),
                  ],
                ),
                if (running && server != null) ...[
                  const SizedBox(height: NbSpace.sm),
                  Text(
                    'Client phones connect on port ${server.httpPort}'
                    '${server.httpsPort != null ? ' · desktop HTTPS on ${server.httpsPort}' : ''}',
                    style: t.text.body,
                  ),
                ],
                if (!serving.discoveryOk) ...[
                  const SizedBox(height: NbSpace.sm),
                  Text(
                    'Auto-discovery is off (no Wi-Fi router reachable). Clients '
                    'can still connect with "Connect by IP address" using the '
                    'address below.',
                    style: t.text.body.copyWith(color: t.color.reject),
                  ),
                ],
                if (serving.lastError != null) ...[
                  const SizedBox(height: NbSpace.sm),
                  Text(serving.lastError!,
                      style: t.text.body.copyWith(color: t.color.reject)),
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
                          background: t.color.reject,
                          foreground: t.color.onReject,
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
                        Text('DESKTOP ADMIN', style: t.text.label),
                        const SizedBox(height: NbSpace.xs),
                        if (urls.http.isEmpty)
                          Text('No LAN address — check Wi-Fi.',
                              style: t.text.body)
                        else ...[
                          Text(
                              'Open in a browser on the same Wi-Fi '
                              '(tap to copy):',
                              style: t.text.body),
                          for (final u in urls.http) CopyableUrl(url: u),
                          if (urls.https.isNotEmpty) ...[
                            const SizedBox(height: NbSpace.xs),
                            Text(
                                'Encrypted (one "not trusted" warning per '
                                'computer):',
                                style: t.text.label),
                            for (final u in urls.https) CopyableUrl(url: u),
                          ],
                        ],
                      ],
                    ),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
          if (running) const SizedBox(height: NbSpace.md),

          // Offline hotspot (Android) ----------------------------------
          if (ref.watch(hotspotProvider).supported) ...[
            const _HotspotCard(),
            const SizedBox(height: NbSpace.md),
          ],

          // Keep awake -------------------------------------------------
          NbSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('KEEP THIS DEVICE AWAKE', style: t.text.label),
                const SizedBox(height: NbSpace.xs),
                Text(
                  Platform.isIOS
                      ? 'While serving, the screen is held awake. Leave the app '
                          'in the foreground — backgrounding it on iOS stops the '
                          'server.'
                      : 'While serving, the screen is held awake and a '
                          'foreground service keeps the server running. Keep the '
                          'phone on power and on Wi-Fi; don\'t force-stop the app.',
                  style: t.text.body,
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
                Text('DESKTOP-ADMIN TLS (OPTIONAL)', style: t.text.label),
                const SizedBox(height: NbSpace.xs),
                Text(
                  'Encrypts admin login over the LAN. A self-signed certificate '
                  'still shows a browser "not trusted" warning the first time '
                  'each computer connects. It never affects phone-to-phone use. '
                  'Restart serving after generating.',
                  style: t.text.body,
                ),
                if (serving.certExpiry != null) ...[
                  const SizedBox(height: NbSpace.xs),
                  Text('Current certificate valid until ${serving.certExpiry}',
                      style: t.text.body),
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

/// "Serve without Wi-Fi" — the host device broadcasts its own network via
/// Android's local-only hotspot. Other phones join it (SSID + passphrase, or
/// the QR) and reach the host at 192.168.49.1.
class _HotspotCard extends ConsumerWidget {
  const _HotspotCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final hs = ref.watch(hotspotProvider);
    final ctrl = ref.read(hotspotProvider.notifier);
    final info = hs.info;

    return NbSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SERVE WITHOUT WI-FI (HOTSPOT)', style: t.text.label),
          const SizedBox(height: NbSpace.xs),
          if (info == null) ...[
            Text(
              'No Wi-Fi at the canteen? This phone makes its own private '
              'network. It turns Wi-Fi off on this device while active, and '
              'has no internet — just the canteen app.',
              style: t.text.body,
            ),
            if (hs.error != null) ...[
              const SizedBox(height: NbSpace.xs),
              Text(hs.error!,
                  style: t.text.body.copyWith(color: t.color.reject)),
            ],
            const SizedBox(height: NbSpace.md),
            NbButton.secondary(
              label: 'Start hotspot',
              icon: Icons.wifi_tethering,
              busy: hs.busy,
              onPressed: hs.busy
                  ? null
                  : () async {
                      await ctrl.start();
                      ref.invalidate(lanUrlsProvider);
                    },
            ),
          ] else ...[
            _kv(context, 'Network', info.ssid),
            _kv(context, 'Password', info.passphrase),
            _kv(context, 'Host address', '${info.host}:8710'),
            const SizedBox(height: NbSpace.sm),
            Text(
                'Other phones: scan to join, then open the app and '
                'pick this host (or Connect by IP → ${'192.168.49.1'}).',
                style: t.text.body),
            const SizedBox(height: NbSpace.sm),
            Center(
              child: Container(
                padding: const EdgeInsets.all(NbSpace.sm),
                color: t.color.surface,
                child: QrImageView(
                  data: info.joinQr,
                  size: 180,
                  backgroundColor: t.color.surface,
                ),
              ),
            ),
            const SizedBox(height: NbSpace.md),
            NbButton(
              label: 'Stop hotspot',
              icon: Icons.stop,
              background: t.color.reject,
              foreground: t.color.onReject,
              busy: hs.busy,
              onPressed: hs.busy ? null : ctrl.stop,
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final t = context.tokens;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: NbSpace.xs),
        child: Row(
          children: [
            SizedBox(width: 120, child: Text(k, style: t.text.label)),
            Expanded(
              child: InkWell(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: v));
                  if (context.mounted) showNbSnack(context, 'Copied "$v".');
                },
                child: Text(v,
                    style: t.text.body.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ));
  }
}
