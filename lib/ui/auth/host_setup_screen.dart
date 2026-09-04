import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors.dart';
import '../shared_widgets/app_logo.dart';
import '../shared_widgets/nb_button.dart';
import '../shared_widgets/nb_surface.dart';
import '../shared_widgets/nb_text_field.dart';
import '../theme/tokens.dart';

/// First run on a host device: the operator creates the admin account.
///
/// This replaced a scheme that generated a password and showed it once on the
/// login screen. The account existed, but the password was held only in
/// memory — miss the banner or restart the app and the host had an admin
/// nobody could sign in as, recoverable only by wiping the database. Choosing
/// your own credentials cannot be lost by looking away.
///
/// Shown whenever the users table is empty, so it also comes back correctly
/// after a data reset instead of being a one-shot.
class HostSetupScreen extends ConsumerStatefulWidget {
  const HostSetupScreen({super.key});

  @override
  ConsumerState<HostSetupScreen> createState() => _HostSetupScreenState();
}

class _HostSetupScreenState extends ConsumerState<HostSetupScreen> {
  final _username = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _revealed = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    final container = await ref.read(hostContainerProvider.future);
    final suggestion = container.auth.suggestPassword();
    setState(() {
      _password.text = suggestion;
      _confirm.text = suggestion;
      // Revealed on purpose: a generated password you cannot read is one you
      // cannot write down, which is how the previous scheme stranded hosts.
      _revealed = true;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_password.text != _confirm.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final container = await ref.read(hostContainerProvider.future);
      await container.auth.createInitialAdmin(
        username: _username.text.trim(),
        password: _password.text,
      );
      ref.invalidate(setupRequiredProvider);
      // Straight in, rather than making someone retype what they just chose.
      await ref
          .read(sessionProvider.notifier)
          .login(_username.text.trim(), _password.text);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not finish setup: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NbSpace.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppWordmark()),
                  const SizedBox(height: NbSpace.lg),
                  NbSurface(
                    intensity: NbIntensity.full,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Set up this host', style: t.text.heading),
                        const SizedBox(height: NbSpace.xs),
                        Text(
                          'Create the admin account for this canteen. You will '
                          'use it to sign in here and on the desktop admin '
                          'page. You can change both later in Users.',
                          style: t.text.body,
                        ),
                        const SizedBox(height: NbSpace.lg),
                        NbTextField(
                          label: 'Admin username',
                          controller: _username,
                          autofocus: true,
                        ),
                        const SizedBox(height: NbSpace.md),
                        NbTextField(
                          label: 'Password',
                          controller: _password,
                          obscure: !_revealed,
                        ),
                        const SizedBox(height: NbSpace.md),
                        NbTextField(
                          label: 'Confirm password',
                          controller: _confirm,
                          obscure: !_revealed,
                        ),
                        const SizedBox(height: NbSpace.sm),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton.icon(
                                icon:
                                    const Icon(Icons.casino_outlined, size: 18),
                                label: const Text('Suggest a strong one'),
                                onPressed: _busy ? null : _suggest,
                              ),
                            ),
                            IconButton(
                              icon: Icon(_revealed
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              tooltip:
                                  _revealed ? 'Hide password' : 'Show password',
                              onPressed: () =>
                                  setState(() => _revealed = !_revealed),
                            ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: NbSpace.sm),
                          Text(_error!,
                              style:
                                  t.text.body.copyWith(color: t.color.reject)),
                        ],
                        const SizedBox(height: NbSpace.md),
                        NbButton(
                          label: 'Create admin & continue',
                          icon: Icons.check,
                          busy: _busy,
                          onPressed: _busy ? null : _submit,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: NbSpace.md),
                  NbSurface(
                    background: t.color.warn,
                    child: Row(
                      children: [
                        Icon(Icons.key_outlined, color: t.color.onWarn),
                        const SizedBox(width: NbSpace.sm),
                        Expanded(
                          child: Text(
                            'Write this password down. It is stored only as a '
                            'one-way hash — nobody, including this app, can '
                            'read it back.',
                            style: t.text.body.copyWith(color: t.color.onWarn),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: NbSpace.md),
                  TextButton.icon(
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Run as a client instead'),
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
