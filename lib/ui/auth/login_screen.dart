import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors.dart';
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
      // ModeGate rebuilds on the session change and routes to the role home.
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = ref.watch(_brandingProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NbSpace.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: NbSurface(
                intensity: NbIntensity.full,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      branding.asData?.value ?? 'Canteen Coupon System',
                      style: NbType.heading,
                    ),
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
                          style: NbType.body.copyWith(color: NbColors.reject)),
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
