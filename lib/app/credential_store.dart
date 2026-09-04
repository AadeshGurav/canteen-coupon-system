import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/logging.dart';

/// One remembered account on one host.
class SavedLogin {
  const SavedLogin({
    required this.username,
    this.password,
    this.token,
    this.tokenExpiresAt,
  });

  factory SavedLogin.fromJson(Map<String, dynamic> j) => SavedLogin(
        username: j['username'] as String,
        password: j['password'] as String?,
        token: j['token'] as String?,
        tokenExpiresAt: j['tokenExpiresAt'] == null
            ? null
            : DateTime.tryParse(j['tokenExpiresAt'] as String),
      );

  final String username;

  /// Only ever set when the operator ticked "remember password". These are
  /// shared canteen phones, so it is opt-in per account rather than implied by
  /// signing in — the opt-in is the whole point.
  final String? password;

  /// The last session token. Lets a returning device skip the login form
  /// entirely, subject to the host still accepting it.
  final String? token;
  final DateTime? tokenExpiresAt;

  bool get tokenLooksValid =>
      token != null &&
      tokenExpiresAt != null &&
      tokenExpiresAt!.isAfter(DateTime.now().toUtc());

  Map<String, dynamic> toJson() => {
        'username': username,
        if (password != null) 'password': password,
        if (token != null) 'token': token,
        if (tokenExpiresAt != null)
          'tokenExpiresAt': tokenExpiresAt!.toIso8601String(),
      };
}

/// Everything this device remembers about one host.
class SavedHost {
  const SavedHost({
    required this.hostId,
    required this.name,
    required this.baseUrl,
    required this.lastUsed,
    required this.logins,
  });

  factory SavedHost.fromJson(Map<String, dynamic> j) => SavedHost(
        hostId: j['hostId'] as String,
        name: j['name'] as String? ?? 'Tiffin host',
        baseUrl: j['baseUrl'] as String? ?? '',
        lastUsed:
            DateTime.tryParse(j['lastUsed'] as String? ?? '') ?? DateTime.now(),
        logins: [
          for (final l in (j['logins'] as List<dynamic>? ?? const []))
            SavedLogin.fromJson(l as Map<String, dynamic>),
        ],
      );

  final String hostId;
  final String name;

  /// Last address this host answered on. A hint for reconnecting, never an
  /// identity — DHCP moves it, which is why [hostId] exists.
  final String baseUrl;
  final DateTime lastUsed;
  final List<SavedLogin> logins;

  SavedLogin? loginFor(String username) {
    for (final l in logins) {
      if (l.username == username) return l;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'hostId': hostId,
        'name': name,
        'baseUrl': baseUrl,
        'lastUsed': lastUsed.toIso8601String(),
        'logins': [for (final l in logins) l.toJson()],
      };
}

/// Per-host saved logins, in the platform keychain / keystore.
///
/// Keyed on the host's own generated id rather than its URL, so the same
/// canteen is recognised after DHCP hands it a different address — and so a
/// phone that visits two canteens keeps both sets of accounts.
class CredentialStore {
  CredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              // v11's Android default is already AES-GCM with a KeyStore-
              // wrapped key, so no options are needed here.
              // Readable after a reboot without the phone being unlocked, so a
              // host that power-cycles overnight still comes back signed in.
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;
  final _log = log('credentials');

  static const _prefix = 'host:';

  String _key(String hostId) => '$_prefix$hostId';

  Future<SavedHost?> read(String hostId) async {
    try {
      final raw = await _storage.read(key: _key(hostId));
      if (raw == null) return null;
      return SavedHost.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      // A corrupt or undecryptable entry must not block sign-in — the operator
      // can always type the password. Drop it and carry on.
      _log.warning('unreadable saved host, ignoring', e);
      return null;
    }
  }

  /// Every host this device has signed in to, most recent first.
  Future<List<SavedHost>> readAll() async {
    try {
      final all = await _storage.readAll();
      final hosts = <SavedHost>[];
      for (final entry in all.entries) {
        if (!entry.key.startsWith(_prefix)) continue;
        try {
          hosts.add(SavedHost.fromJson(
              jsonDecode(entry.value) as Map<String, dynamic>));
        } catch (_) {/* skip the bad one, keep the rest */}
      }
      hosts.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
      return hosts;
    } catch (e) {
      _log.warning('could not read saved logins', e);
      return const [];
    }
  }

  /// Records a successful sign-in. [password] is stored only when the operator
  /// asked for it; passing null leaves any previously saved one untouched so a
  /// normal sign-in doesn't silently forget it.
  Future<void> remember({
    required String hostId,
    required String hostName,
    required String baseUrl,
    required String username,
    String? password,
    bool forgetPassword = false,
    String? token,
    DateTime? tokenExpiresAt,
  }) async {
    final existing = await read(hostId);
    final previous = existing?.loginFor(username);

    final updated = SavedLogin(
      username: username,
      password: forgetPassword ? null : (password ?? previous?.password),
      token: token ?? previous?.token,
      tokenExpiresAt: tokenExpiresAt ?? previous?.tokenExpiresAt,
    );

    final logins = [
      updated,
      for (final l in existing?.logins ?? const <SavedLogin>[])
        if (l.username != username) l,
    ];

    await _write(SavedHost(
      hostId: hostId,
      name: hostName,
      baseUrl: baseUrl,
      lastUsed: DateTime.now().toUtc(),
      logins: logins,
    ));
  }

  /// Drops a token the host has rejected, keeping the username (and password,
  /// if saved) so the operator still gets a one-tap sign-in.
  Future<void> invalidateToken(String hostId, String username) async {
    final host = await read(hostId);
    if (host == null) return;
    await _write(SavedHost(
      hostId: host.hostId,
      name: host.name,
      baseUrl: host.baseUrl,
      lastUsed: host.lastUsed,
      logins: [
        for (final l in host.logins)
          if (l.username == username)
            SavedLogin(username: l.username, password: l.password)
          else
            l,
      ],
    ));
  }

  Future<void> forgetLogin(String hostId, String username) async {
    final host = await read(hostId);
    if (host == null) return;
    final remaining = [
      for (final l in host.logins)
        if (l.username != username) l,
    ];
    if (remaining.isEmpty) {
      await forgetHost(hostId);
      return;
    }
    await _write(SavedHost(
      hostId: host.hostId,
      name: host.name,
      baseUrl: host.baseUrl,
      lastUsed: host.lastUsed,
      logins: remaining,
    ));
  }

  Future<void> forgetHost(String hostId) => _storage.delete(key: _key(hostId));

  /// Clears every saved login on this device.
  Future<void> forgetEverything() async {
    for (final host in await readAll()) {
      await forgetHost(host.hostId);
    }
  }

  Future<void> _write(SavedHost host) =>
      _storage.write(key: _key(host.hostId), value: jsonEncode(host.toJson()));
}
