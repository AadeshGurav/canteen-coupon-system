import 'package:drift/drift.dart';

import '../core/errors.dart';
import '../core/logging.dart';
import '../data/local/database.dart';
import '../data/local/mappers.dart';
import '../domain/ops.dart';
import 'auth_service.dart';

/// Login-account management — a port of v1 `app/routers/users.py` (PRD §4).
/// Admin-only at the router layer. Never returns a password hash.
class UserService {
  UserService(this._db, this._auth);

  final AppDatabase _db;
  final AuthService _auth;
  final _log = log('user');

  static final _usernamePattern = RegExp(r'^[a-zA-Z0-9_.-]+$');

  Future<List<AppUser>> list() async {
    final rows = await (_db.select(_db.users)
          ..orderBy([(u) => OrderingTerm.asc(u.username)]))
        .get();
    return rows.map(userFromRow).toList();
  }

  Future<AppUser> create(UserDraft draft) async {
    _validateUsername(draft.username);
    if (draft.password.length < 8) {
      throw const ValidationException(
          'Password must be at least 8 characters.');
    }
    final now = DateTime.now().toUtc();
    try {
      final id = await _db.into(_db.users).insert(UsersCompanion.insert(
            username: draft.username,
            passwordHash: _auth.hashPassword(draft.password),
            role: draft.role.wire,
            createdAt: now,
            updatedAt: now,
          ));
      _log.info('created username=${draft.username} role=${draft.role.wire}');
      final row = await (_db.select(_db.users)..where((u) => u.id.equals(id)))
          .getSingle();
      return userFromRow(row);
    } on Exception catch (e) {
      if (e.toString().toLowerCase().contains('unique')) {
        throw ConflictException(
            "Username '${draft.username}' is already taken.");
      }
      rethrow;
    }
  }

  /// [actingUserId] guards the "can't deactivate/delete yourself" rules.
  Future<AppUser> update(int id, UserPatch patch,
      {required int actingUserId}) async {
    if (patch.username != null) _validateUsername(patch.username!);
    final companion = UsersCompanion(
      username: patch.username == null
          ? const Value.absent()
          : Value(patch.username!),
      passwordHash: patch.password == null
          ? const Value.absent()
          : Value(_auth.hashPassword(patch.password!)),
      role: patch.role == null ? const Value.absent() : Value(patch.role!.wire),
      status:
          patch.status == null ? const Value.absent() : Value(patch.status!),
      updatedAt: Value(DateTime.now().toUtc()),
    );
    if (patch.status == 'inactive' && id == actingUserId) {
      throw const ValidationException("You can't deactivate your own account.");
    }
    if (patch.password != null && patch.password!.length < 8) {
      throw const ValidationException(
          'Password must be at least 8 characters.');
    }

    final int n;
    try {
      n = await (_db.update(_db.users)..where((u) => u.id.equals(id)))
          .write(companion);
    } on Exception catch (e) {
      if (e.toString().toLowerCase().contains('unique')) {
        throw ConflictException(
            "Username '${patch.username}' is already taken.");
      }
      rethrow;
    }
    if (n == 0) throw const NotFoundException('User not found.');

    // Sessions carry a denormalised copy of the username (it is what the app
    // bar shows and what request logs record), so a rename has to reach them
    // too or the operator keeps seeing their old name until the token expires.
    if (patch.username != null) {
      await (_db.update(_db.sessions)..where((s) => s.userId.equals(id)))
          .write(SessionsCompanion(username: Value(patch.username!)));
    }

    _log.info('updated user_id=$id');
    final row = await (_db.select(_db.users)..where((u) => u.id.equals(id)))
        .getSingle();
    return userFromRow(row);
  }

  Future<void> delete(int id, {required int actingUserId}) async {
    if (id == actingUserId) {
      throw const ValidationException("You can't delete your own account.");
    }
    final n = await (_db.delete(_db.users)..where((u) => u.id.equals(id))).go();
    if (n == 0) throw const NotFoundException('User not found.');
    _log.warning('deleted user_id=$id');
  }

  void _validateUsername(String username) {
    if (username.length < 3 || username.length > 50) {
      throw const ValidationException('Username must be 3–50 characters.');
    }
    if (!_usernamePattern.hasMatch(username)) {
      throw const ValidationException(
          'Username may only contain letters, digits, and _ . -');
    }
  }
}
