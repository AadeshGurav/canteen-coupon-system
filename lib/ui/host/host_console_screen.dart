import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config.dart';
import '../../server/tls.dart';
import '../auth/login_screen.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
import '../shared_widgets/nb_surface.dart';
import '../theme/tokens.dart';

/// Host-mode control panel (PRD §13.2): start/stop the embedded server, publish
/// it on the LAN, optionally generate the self-signed cert (§13.6). Once the
/// server is running the operator signs in here like any other device.
class HostConsoleScreen extends ConsumerStatefulWidget {
  const HostConsoleScreen({super.key});

  @override
  ConsumerState<HostConsoleScreen> createState() => _HostConsoleScreenState();
}

class _HostConsoleScreenState extends ConsumerState<HostConsoleScreen> {
  bool _busy = false;
  String? _certExpiry;

  Future<void> _startServer(String documentsDir) async {
    setState(() => _busy = true);
    await runGuarded(context, () async {
      final container = await ref.read(hostContainerProvider.future);
      final tls = SelfSignedTls(documentsDir);
      final server = ref.read(hostServerProvider);
      await server.start(
        port: AppConfig.defaultServerPort,
        securityContext: tls.securityContext(),
      );
      await ref.read(hostAdvertiserProvider).advertise(
          name: await container.settings.readAppName(),
          port: AppConfig.defaultServerPort);
      ref.read(hostRunningProvider.notifier).state = true;
    }, successMessage: 'Server started.');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _stopServer() async {
    setState(() => _busy = true);
    await runGuarded(context, () async {
      await ref.read(hostAdvertiserProvider).stop();
      await ref.read(hostServerProvider).stop();
      ref.read(hostRunningProvider.notifier).state = false;
    }, successMessage: 'Server stopped.');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _generateCert(String documentsDir) async {
    setState(() => _busy = true);
    await runGuarded(context, () async {
      final expiry = await SelfSignedTls(documentsDir).generate();
      setState(
          () => _certExpiry = expiry.toLocal().toString().split(' ').first);
    },
        successMessage:
            'Certificate generated. Restart the server to use HTTPS.');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final running = ref.watch(hostRunningProvider);
    final server = running ? ref.watch(hostServerProvider) : null;
    final generatedPw = ref.watch(generatedAdminPasswordProvider);
    final docsDir = ref.watch(hostContainerProvider).maybeWhen(
          data: (c) => c.artifacts.baseDir,
          orElse: () => null,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('HOST'),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(NbSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (generatedPw != null)
              NbSurface(
                intensity: NbIntensity.full,
                background: NbColors.warn,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FIRST-RUN ADMIN PASSWORD',
                        style: NbType.label.copyWith(color: NbColors.onWarn)),
                    const SizedBox(height: NbSpace.xs),
                    SelectableText(generatedPw,
                        style: NbType.heading.copyWith(color: NbColors.onWarn)),
                    const SizedBox(height: NbSpace.xs),
                    Text(
                      'Username "admin". Shown once, never written to a log. '
                      'Change it from Users after signing in.',
                      style: NbType.body.copyWith(color: NbColors.onWarn),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: NbSpace.md),
            NbSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(running ? Icons.check_circle : Icons.circle_outlined,
                          color: running ? NbColors.accept : NbColors.ink),
                      const SizedBox(width: NbSpace.sm),
                      Text(running ? 'SERVER RUNNING' : 'SERVER STOPPED',
                          style: NbType.heading),
                    ],
                  ),
                  if (running && server != null) ...[
                    const SizedBox(height: NbSpace.sm),
                    Text('${server.address}:${server.port}',
                        style: NbType.body),
                    const Text(
                        'Advertised as "${AppConfig.discoveryServiceType}"',
                        style: NbType.body),
                  ],
                  const SizedBox(height: NbSpace.md),
                  if (docsDir == null)
                    const Text('Preparing database…', style: NbType.body)
                  else if (!running)
                    NbButton(
                      label: 'Start server',
                      icon: Icons.play_arrow,
                      busy: _busy,
                      onPressed: _busy ? null : () => _startServer(docsDir),
                    )
                  else
                    NbButton(
                      label: 'Stop server',
                      icon: Icons.stop,
                      background: NbColors.reject,
                      foreground: NbColors.onReject,
                      busy: _busy,
                      onPressed: _busy ? null : _stopServer,
                    ),
                ],
              ),
            ),
            const SizedBox(height: NbSpace.md),
            NbSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DESKTOP-ADMIN TLS (OPTIONAL)',
                      style: NbType.label),
                  const SizedBox(height: NbSpace.xs),
                  const Text(
                    'Encrypts admin login over the LAN. A self-signed '
                    'certificate still shows a browser "not trusted" warning '
                    'the first time each device connects — only a real CA '
                    'removes that. It does not affect phone-to-phone use.',
                    style: NbType.body,
                  ),
                  if (_certExpiry != null) ...[
                    const SizedBox(height: NbSpace.xs),
                    Text('Current certificate valid until $_certExpiry',
                        style: NbType.body),
                  ],
                  const SizedBox(height: NbSpace.md),
                  NbButton.secondary(
                    label: 'Generate certificate',
                    onPressed: (_busy || docsDir == null)
                        ? null
                        : () => _generateCert(docsDir),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NbSpace.lg),
            NbButton(
              label: 'Sign in on this device',
              icon: Icons.login,
              onPressed: docsDir == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LoginScreen(),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
