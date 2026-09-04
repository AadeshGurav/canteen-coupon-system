import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:pointycastle/export.dart';

import '../core/errors.dart';
import '../core/logging.dart';
import '../core/role.dart';
import '../data/local/database.dart';

/// Password hashing and opaque server-side sessions — a port of v1
/// `app/services/auth_service.py`. PBKDF2-HMAC-SHA256, 260k iterations, stored
/// as `salt$digest` (both hex), matching v1 so a migrated `users` row verifies
/// unchanged. Sessions are random tokens in a table row, revoked by deleting
/// the row; expired rows are swept opportunistically (no cron), the same
/// reasoning as v1's Mongo TTL index (PRD §8).
class AuthService {
  AuthService(this._db, {required this.sessionTtl});

  final AppDatabase _db;
  final Duration sessionTtl;
  final _log = log('auth');

  static const _iterations = 260000;
  static const _keyLen = 32;
  final _random = Random.secure();

  /// Throttle for [sweepExpired] — the web admin fires many requests per
  /// screen and a DELETE-scan on every one is wasted work.
  DateTime? _lastSweep;
  static const _sweepEvery = Duration(minutes: 5);

  // ---- password hashing -------------------------------------------------

  String hashPassword(String password) {
    final salt = _randomBytes(16);
    final digest = _pbkdf2(password, salt);
    return '${_hex(salt)}\$${_hex(digest)}';
  }

  bool verifyPassword(String password, String storedHash) {
    final parts = storedHash.split('\$');
    if (parts.length != 2) return false;
    final salt = _unhex(parts[0]);
    final expected = parts[1];
    final actual = _hex(_pbkdf2(password, salt));
    return _constantTimeEquals(actual, expected);
  }

  Uint8List _pbkdf2(String password, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _iterations, _keyLen));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  // ---- authentication + sessions -------------------------------------

  /// Returns the user row on success, null on ANY failure — a caller never
  /// distinguishes "no such user" from "wrong password" (that distinction is
  /// what lets an attacker enumerate usernames). Same as v1.
  Future<User?> authenticate(String username, String password) async {
    final user = await (_db.select(_db.users)
          ..where((u) => u.username.equals(username)))
        .getSingleOrNull();
    if (user == null) return null;
    if (user.status != 'active') return null;
    if (!verifyPassword(password, user.passwordHash)) return null;
    return user;
  }

  Future<Session> createSession(User user) async {
    final now = DateTime.now().toUtc();
    final token = _urlSafeToken(32);
    final row = SessionsCompanion.insert(
      token: token,
      userId: user.id,
      username: user.username,
      role: user.role,
      createdAt: now,
      expiresAt: now.add(sessionTtl),
    );
    await _db.into(_db.sessions).insert(row);
    _log.info('login_succeeded username=${user.username} role=${user.role}');
    return (await _sessionByToken(token))!;
  }

  /// Resolves a bearer token to its session, or throws [AuthException].
  /// Belt-and-suspenders expiry check: a token past `expiresAt` is rejected
  /// even before the sweep removes its row.
  Future<Session> requireSession(String? token) async {
    if (token == null || token.isEmpty) {
      throw const AuthException('Not logged in.');
    }
    final session = await _sessionByToken(token);
    if (session == null || session.expiresAt.isBefore(DateTime.now().toUtc())) {
      throw const AuthException(
          'Session expired or invalid — please log in again.');
    }
    return session;
  }

  Future<void> deleteSession(String token) async {
    await (_db.delete(_db.sessions)..where((s) => s.token.equals(token))).go();
  }

  /// Opportunistic cleanup — safe to call from the auth middleware on every
  /// request; it self-throttles to once per [_sweepEvery] so it isn't a DB
  /// write per API call. No scheduled job.
  Future<void> sweepExpired() async {
    final now = DateTime.now().toUtc();
    if (_lastSweep != null && now.difference(_lastSweep!) < _sweepEvery) return;
    _lastSweep = now;
    await (_db.delete(_db.sessions)
          ..where((s) => s.expiresAt.isSmallerThanValue(now)))
        .go();
  }

  Future<Session?> _sessionByToken(String token) =>
      (_db.select(_db.sessions)..where((s) => s.token.equals(token)))
          .getSingleOrNull();

  // ---- first-run setup -------------------------------------------------

  /// True while this host has no accounts at all — the state the setup screen
  /// exists to resolve. Also true after a data reset, which is what makes
  /// setup self-healing rather than a one-shot that can be missed.
  Future<bool> needsSetup() async => (await _db.users.count().getSingle()) == 0;

  /// Creates the first admin account with credentials the operator chose.
  ///
  /// This replaced a scheme that generated a password and displayed it once on
  /// the login screen. The account was real, but the password lived only in
  /// memory: background the app, restart it, or simply not read the banner,
  /// and the host was left with an admin nobody could ever sign in as and no
  /// way back except wiping the database. An operator who picks their own
  /// password cannot be locked out by a missed notification.
  ///
  /// Guarded on an empty users table so it can never be used to mint a second
  /// admin on a live host.
  Future<void> createInitialAdmin({
    required String username,
    required String password,
  }) async {
    if (!await needsSetup()) {
      throw const ValidationException(
          'This device is already set up. Sign in instead.');
    }
    final name = username.trim();
    if (name.isEmpty) {
      throw const ValidationException('Choose a username.');
    }
    requireStrongPassword(password);

    final now = DateTime.now().toUtc();
    await _db.into(_db.users).insert(UsersCompanion.insert(
          username: name,
          passwordHash: hashPassword(password),
          role: Role.admin.wire,
          createdAt: now,
          updatedAt: now,
        ));
    _log.info('initial_admin_created username=$name');
  }

  /// Rejects passwords that would make the host trivially reachable by anyone
  /// on the same Wi-Fi. Deliberately a length floor rather than a character
  /// -class rule: length is what actually helps, and rules people fight
  /// produce `Password1!` (CLAUDE.md §11.2, Postel's Law on input).
  static const minPasswordLength = 8;

  void requireStrongPassword(String password) {
    if (password.length < minPasswordLength) {
      throw const ValidationException(
          'Use at least $minPasswordLength characters.');
    }
  }

  /// A strong password the operator can accept rather than invent. Returned,
  /// never logged — a plaintext credential in the rotating log file would
  /// violate CLAUDE.md §7.
  String suggestPassword() => _urlSafeToken(9);

  /// Last-resort recovery, host device only (see the route's role gate).
  ///
  /// Grants no privilege that physical possession of the host phone did not
  /// already carry: that phone can already wipe the entire database from
  /// Settings, which is strictly more destructive than a password reset.
  Future<void> resetPasswordFor(String username, String newPassword) async {
    requireStrongPassword(newPassword);
    final updated = await (_db.update(_db.users)
          ..where((u) => u.username.equals(username)))
        .write(UsersCompanion(
      passwordHash: Value(hashPassword(newPassword)),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
    if (updated == 0) {
      throw ValidationException('No account called "$username".');
    }
    // Any session opened with the old password stops being valid.
    await (_db.delete(_db.sessions)..where((s) => s.username.equals(username)))
        .go();
    _log.warning('admin_password_reset username=$username');
  }

  // ---- primitives --------------------------------------------------------

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  String _urlSafeToken(int bytes) =>
      base64Url.encode(_randomBytes(bytes)).replaceAll('=', '');

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _unhex(String s) {
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
