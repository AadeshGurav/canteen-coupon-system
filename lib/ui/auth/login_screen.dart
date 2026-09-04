import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_mode.dart';
import '../../core/errors.dart';
import '../shared_widgets/ios_host_advisory.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_text_field.dart';
import '../theme/tokens.dart';

/// Sign-in for scanner / counter / admin roles (PRD §4, §6.4). The session is
/// remembered on this device until sign-out or expiry, so a shared kiosk logs
/// in once.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .login(_username.text.trim(), _password.text);
      // This screen can be PUSHED (from the client discovery screen), so
      // ModeGate swapping its home underneath isn't enough — pop back to the
      // root, or the operator keeps staring at the login form.
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not sign in: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = ref.watch(_brandingProvider);
    final isHost = ref.watch(currentModeProvider) == AppMode.host;
    final firstRunPassword = ref.watch(generatedAdminPasswordProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NbSpace.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The sign-in card comes first — advisories are context, not
                  // the task, and pushing the fields down the screen buries the
                  // one thing the operator opened this screen to do.
                  NbSurface(
                    intensity: NbIntensity.full,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          branding.asData?.value ?? 'Tiffin',
                          style: NbType.heading,
                        ),
                        if (isHost)
                          const Text('Host device', style: NbType.label),
                        const SizedBox(height: NbSpace.xs),
                        const Text('Sign in', style: NbType.body),
                        const SizedBox(height: NbSpace.lg),
                        NbTextField(
                          label: 'Username',
                          controller: _username,
                          autofocus: true,
                        ),
                        const SizedBox(height: NbSpace.md),
                        NbTextField(
                          label: 'Password',
                          controller: _password,
                          obscure: true,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: NbSpace.md),
                          Text(_error!,
                              style:
                                  NbType.body.copyWith(color: NbColors.reject)),
                        ],
                        const SizedBox(height: NbSpace.lg),
                        NbButton(
                          label: 'Sign in',
                          busy: _busy,
                          onPressed: _busy ? null : _submit,
                        ),
                      ],
                    ),
                  ),
                  if (firstRunPassword != null) ...[
                    const SizedBox(height: NbSpace.md),
                    NbSurface(
                      intensity: NbIntensity.full,
                      background: NbColors.warn,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('FIRST-RUN ADMIN PASSWORD',
                              style: NbType.label
                                  .copyWith(color: NbColors.onWarn)),
                          const SizedBox(height: NbSpace.xs),
                          SelectableText(firstRunPassword,
                              style: NbType.heading
                                  .copyWith(color: NbColors.onWarn)),
                          const SizedBox(height: NbSpace.xs),
                          Text(
                            'Username "admin". Shown once, never written to a '
                            'log. Change it from Users after signing in.',
                            style: NbType.body.copyWith(color: NbColors.onWarn),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: NbSpace.md),
                  ],
                  if (isHost && Platform.isIOS) ...[
                    const SizedBox(height: NbSpace.md),
                    const IosHostAdvisory(),
                  ],
                  const SizedBox(height: NbSpace.md),
                  TextButton.icon(
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Switch device role'),
                    onPressed: () =>
                        ref.read(currentModeProvider.notifier).clear(),
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

/// Public branding — safe to fetch before a session exists.
final _brandingProvider = FutureProvider.autoDispose<String>((ref) {
  return ref.watch(backendProvider).branding();
});
