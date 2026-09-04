import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_mode.dart';
import '../../core/errors.dart';
import '../shared_widgets/ios_host_advisory.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_feedback.dart';
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

  /// Sets a new password for an account on this host, on the host device only.
  Future<void> _recoverPassword() async {
    final container = await ref.read(hostContainerProvider.future);
    if (!mounted) return;
    final username = _username.text.trim();
    final result = await showDialog<({String username, String password})>(
      context: context,
      builder: (_) => _RecoverPasswordDialog(
        initialUsername: username.isEmpty ? 'admin' : username,
        suggestion: container.auth.suggestPassword(),
      ),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await container.auth.resetPasswordFor(result.username, result.password);
      _username.text = result.username;
      _password.text = result.password;
      setState(() => _error = null);
      if (mounted) {
        showNbSnack(context, 'Password reset. Sign in to continue.');
      }
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final branding = ref.watch(_brandingProvider);
    final isHost = ref.watch(currentModeProvider) == AppMode.host;
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
                          style: t.text.heading,
                        ),
                        if (isHost) Text('Host device', style: t.text.label),
                        const SizedBox(height: NbSpace.xs),
                        Text('Sign in', style: t.text.body),
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
                                  t.text.body.copyWith(color: t.color.reject)),
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
                  // Recovery is offered only on the host device, and never
                  // over the network: it runs against the local database, so
                  // it grants nothing that holding this phone didn't already
                  // grant — the same phone can wipe the database outright.
                  if (isHost)
                    TextButton.icon(
                      icon: const Icon(Icons.lock_reset, size: 18),
                      label: const Text('Forgot the password?'),
                      onPressed: _busy ? null : _recoverPassword,
                    ),
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

/// Typed confirmation for the host-device password reset. Requires the word
/// RESET, matching the pattern the destructive data wipe already uses, so a
/// stray tap on a shared phone can't change a credential.
class _RecoverPasswordDialog extends StatefulWidget {
  const _RecoverPasswordDialog({
    required this.initialUsername,
    required this.suggestion,
  });

  final String initialUsername;
  final String suggestion;

  @override
  State<_RecoverPasswordDialog> createState() => _RecoverPasswordDialogState();
}

class _RecoverPasswordDialogState extends State<_RecoverPasswordDialog> {
  late final _username = TextEditingController(text: widget.initialUsername);
  late final _password = TextEditingController(text: widget.suggestion);
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final armed = _confirm.text.trim().toUpperCase() == 'RESET';
    return AlertDialog(
      title: Text('Reset a password', style: t.text.heading),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Only possible on this host device. The new password is shown '
              'below — write it down, it cannot be read back afterwards. Any '
              'open session for this account is signed out.',
              style: t.text.body,
            ),
            const SizedBox(height: NbSpace.md),
            NbTextField(label: 'Account', controller: _username),
            const SizedBox(height: NbSpace.sm),
            NbTextField(label: 'New password', controller: _password),
            const SizedBox(height: NbSpace.sm),
            NbTextField(
              label: 'Type RESET to confirm',
              controller: _confirm,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        NbButton(
          label: 'Reset password',
          background: t.color.reject,
          onPressed: armed
              ? () => Navigator.pop(
                    context,
                    (
                      username: _username.text.trim(),
                      password: _password.text,
                    ),
                  )
              : null,
        ),
      ],
    );
  }
}
