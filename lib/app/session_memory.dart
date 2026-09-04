import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';
import 'appearance_providers.dart';
import 'credential_store.dart';
import 'providers.dart';

final credentialStoreProvider =
    Provider<CredentialStore>((ref) => CredentialStore());

/// Every host this device has signed in to, most recent first. Drives the
/// "you've been here before" list on the discovery and login screens.
final savedHostsProvider = FutureProvider<List<SavedHost>>(
    (ref) => ref.watch(credentialStoreProvider).readAll());

/// What this device remembers about the host it is currently talking to.
final savedLoginsForHostProvider = FutureProvider<SavedHost?>((ref) async {
  final greeting = await ref.watch(hostGreetingProvider.future);
  if (!greeting.isIdentified) return null;
  return ref.watch(credentialStoreProvider).read(greeting.hostId);
});

/// Ties sign-in to what the device remembers.
///
/// Kept out of [SessionController] so the session stays a pure in-memory
/// concern and this file owns every read/write of stored credentials — there
/// is one place to look when asking what this device has kept.
class SessionMemory {
  SessionMemory(this._ref);

  final Ref _ref;
  final _log = log('session-memory');

  /// Records a successful sign-in against the host's stable id.
  ///
  /// Usernames are always remembered — they are not a secret and typing one
  /// on a phone is the friction worth removing. The password is written only
  /// when [rememberPassword] is set, and clearing the tick actively forgets a
  /// previously saved one rather than leaving it behind.
  Future<void> remember({
    required String username,
    required String password,
    required bool rememberPassword,
  }) async {
    try {
      final greeting = await _ref.read(hostGreetingProvider.future);
      if (!greeting.isIdentified) return;
      final session = _ref.read(sessionProvider);

      await _ref.read(credentialStoreProvider).remember(
            hostId: greeting.hostId,
            hostName: greeting.appName,
            baseUrl: _ref.read(selectedHostProvider)?.baseUrl ?? '',
            username: username,
            password: rememberPassword ? password : null,
            forgetPassword: !rememberPassword,
            token: session?.token,
            // Mirrors the host's 12h session TTL. Treated as a hint only: the
            // host is still asked to confirm the token before it is trusted.
            tokenExpiresAt:
                DateTime.now().toUtc().add(const Duration(hours: 12)),
          );
      _ref.invalidate(savedHostsProvider);
      _ref.invalidate(savedLoginsForHostProvider);
    } catch (e) {
      // Never let a storage problem fail a sign-in that already succeeded.
      _log.warning('could not save login', e);
    }
  }

  /// Signs out, and makes it stick.
  ///
  /// Clearing the session alone was not enough: the login screen offers any
  /// saved token straight back, so an explicit sign-out has to drop the token
  /// too or the operator is signed back in before the form is drawn. The
  /// username (and the password, if it was opted into) are kept — signing out
  /// should cost a tap, not the whole convenience.
  Future<void> signOut() async {
    // Read before the session is cleared; afterwards there is no username.
    final username = _ref.read(sessionProvider)?.username;
    String? hostId;
    try {
      hostId = (await _ref.read(hostGreetingProvider.future)).hostId;
    } catch (_) {
      // Host unreachable — sign out locally anyway rather than trapping
      // someone on a screen because the network is down.
    }

    await _ref.read(sessionProvider.notifier).logout();

    if (hostId != null && hostId.isNotEmpty && username != null) {
      try {
        await _ref
            .read(credentialStoreProvider)
            .invalidateToken(hostId, username);
        _ref.invalidate(savedLoginsForHostProvider);
      } catch (e) {
        _log.warning('signed out but could not drop the saved token', e);
      }
    }
  }

  /// Tries to resume a saved session on the current host without a password.
  ///
  /// The stored expiry is only a hint — the host is asked to confirm the token
  /// before it is trusted, because a password reset or a data wipe invalidates
  /// it well before it expires.
  Future<bool> tryResume() async {
    try {
      final greeting = await _ref.read(hostGreetingProvider.future);
      if (!greeting.isIdentified) return false;

      final host =
          await _ref.read(credentialStoreProvider).read(greeting.hostId);
      if (host == null) return false;

      for (final login in host.logins.where((l) => l.tokenLooksValid)) {
        final resumed = await _ref
            .read(sessionProvider.notifier)
            .resumeWithToken(login.token!);
        if (resumed) {
          _log.info('session resumed username=${login.username}');
          return true;
        }
        await _ref
            .read(credentialStoreProvider)
            .invalidateToken(greeting.hostId, login.username);
      }
      return false;
    } catch (e) {
      _log.warning('could not resume a session', e);
      return false;
    }
  }

  Future<void> forgetLogin(String hostId, String username) async {
    await _ref.read(credentialStoreProvider).forgetLogin(hostId, username);
    _ref.invalidate(savedHostsProvider);
    _ref.invalidate(savedLoginsForHostProvider);
  }

  Future<void> forgetEverything() async {
    await _ref.read(credentialStoreProvider).forgetEverything();
    _ref.invalidate(savedHostsProvider);
    _ref.invalidate(savedLoginsForHostProvider);
  }
}

final sessionMemoryProvider =
    Provider<SessionMemory>((ref) => SessionMemory(ref));
