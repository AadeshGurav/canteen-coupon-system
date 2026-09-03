import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
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

  @override
  void initState() {
    super.initState();
    // Self-heal: if the keep-alive service is still running (e.g. an OEM ROM
    // killed and restarted the app process mid-shift), bring the server back
    // up automatically so the console's state matches reality.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || ref.read(hostRunningProvider)) return;
      if (await FlutterForegroundTask.isRunningService) {
        final container = await ref.read(hostContainerProvider.future);
        if (mounted) await _startServer(container.artifacts.baseDir);
      }
    });
  }

  Future<void> _startServer(String documentsDir) async {
    setState(() => _busy = true);
    await runGuarded(context, () async {
      final container = await ref.read(hostContainerProvider.future);
      final appName = await container.settings.readAppName();
      final tls = SelfSignedTls(documentsDir);
      final server = ref.read(hostServerProvider)
        ..staticRoot = await ref.read(webAdminDirProvider.future);
      await server.start(
        port: AppConfig.defaultServerPort,
        securityContext: tls.securityContext(),
      );
      await ref
          .read(hostAdvertiserProvider)
          .advertise(name: appName, port: AppConfig.defaultServerPort);
      // Keep the process (and this server) alive when backgrounded (PRD §13.3).
      await ref
          .read(hostKeepAliveProvider)
          .start(appName: appName, port: AppConfig.defaultServerPort);
      ref.read(hostRunningProvider.notifier).state = true;
      ref.invalidate(lanUrlsProvider);
    }, successMessage: 'Server started.');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _stopServer() async {
    setState(() => _busy = true);
    await runGuarded(context, () async {
      await ref.read(hostKeepAliveProvider).stop();
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
                    Text('Listening on port ${server.port}',
                        style: NbType.body),
                    const Text(
                        'Advertised as "${AppConfig.discoveryServiceType}"',
                        style: NbType.body),
                    const SizedBox(height: NbSpace.sm),
                    const Text(
                        'DESKTOP ADMIN — open one of these in a browser '
                        'on a computer on the same Wi-Fi:',
                        style: NbType.label),
                    ref.watch(lanUrlsProvider).maybeWhen(
                          data: (urls) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: urls.isEmpty
                                ? [
                                    const Text(
                                        'No LAN address found — check Wi-Fi.',
                                        style: NbType.body)
                                  ]
                                : [
                                    for (final u in urls) _CopyableUrl(url: u),
                                  ],
                          ),
                          orElse: () => const SizedBox.shrink(),
                        ),
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

/// A LAN URL that copies to the clipboard on tap, with a cheerful confirmation
/// (the operator will do this a lot — reward the tap, Peak-End Rule).
class _CopyableUrl extends StatelessWidget {
  const _CopyableUrl({required this.url});

  final String url;

  static const _quips = [
    'Yoinked! It is on your clipboard now. 📋',
    'Copied. Paste it like it is hot. 🔥',
    'URL beamed to your clipboard. 🛸',
    'Snatched. Ctrl+V is your friend now. ✌️',
    'Got it. Go forth and paste. 📎',
    'Clipboard: fed. You: welcome. 🍽️',
  ];

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: url));
        if (context.mounted) {
          showNbSnack(context, _quips[Random().nextInt(_quips.length)]);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NbSpace.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                url,
                style: NbType.body.copyWith(
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(width: NbSpace.xs),
            const Icon(Icons.copy, size: 16, color: NbColors.ink),
          ],
        ),
      ),
    );
  }
}
