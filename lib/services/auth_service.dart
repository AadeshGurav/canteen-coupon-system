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

  // ---- bootstrap ------------------------------------------------------

  /// Creates one admin account iff the users table is empty (PRD §4). If no
  /// password is supplied a random one is generated and RETURNED (never
  /// logged — writing a plaintext credential to the rotating log file would
  /// violate CLAUDE.md §7); the host console shows it once on first boot.
  Future<String?> bootstrapInitialAdmin({
    required String username,
    String? password,
  }) async {
    final count = await _db.users.count().getSingle();
    if (count > 0) return null;

    final effective =
        (password == null || password.isEmpty) ? _urlSafeToken(9) : password;
    final now = DateTime.now().toUtc();
    await _db.into(_db.users).insert(UsersCompanion.insert(
          username: username,
          passwordHash: hashPassword(effective),
          role: Role.admin.wire,
          createdAt: now,
          updatedAt: now,
        ));
    _log.info('bootstrap_admin_created username=$username');
    return (password == null || password.isEmpty) ? effective : null;
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
