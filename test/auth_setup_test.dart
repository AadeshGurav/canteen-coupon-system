import 'package:tiffin/core/errors.dart';
import 'package:tiffin/core/role.dart';
import 'package:tiffin/data/local/database.dart';
import 'package:tiffin/domain/ops.dart';
import 'package:tiffin/services/auth_service.dart';
import 'package:tiffin/services/user_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// First-run setup and account identity.
///
/// The bug these cover: the initial admin used to be created automatically
/// with a generated password shown once, in memory only. The account was real
/// and the credential was not recoverable, so a missed banner or an app restart
/// left the host permanently unreachable.
void main() {
  late AppDatabase db;
  late AuthService auth;
  late UserService users;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = AuthService(db, sessionTtl: const Duration(hours: 12));
    users = UserService(db, auth);
  });

  tearDown(() => db.close());

  group('first-run setup', () {
    test('a fresh host owes setup and creates no account on its own', () async {
      expect(await auth.needsSetup(), isTrue);
      expect(await db.users.count().getSingle(), 0,
          reason: 'nothing is created behind the operator\'s back');
    });

    test('setup creates the admin with the chosen credentials', () async {
      await auth.createInitialAdmin(username: 'boss', password: 'lunchtime99');

      expect(await auth.needsSetup(), isFalse);
      final user = await auth.authenticate('boss', 'lunchtime99');
      expect(user, isNotNull);
      expect(user!.role, Role.admin.wire);
    });

    test('the chosen password still works after a restart', () async {
      await auth.createInitialAdmin(username: 'admin', password: 'lunchtime99');

      // A second service over the same database is what an app relaunch looks
      // like — nothing about the credential lives in memory.
      final afterRestart =
          AuthService(db, sessionTtl: const Duration(hours: 1));
      expect(
          await afterRestart.authenticate('admin', 'lunchtime99'), isNotNull);
    });

    test('setup cannot mint a second admin on a live host', () async {
      await auth.createInitialAdmin(username: 'admin', password: 'lunchtime99');
      expect(
        () => auth.createInitialAdmin(username: 'sneak', password: 'password1'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('a too-short password is refused', () async {
      expect(
        () => auth.createInitialAdmin(username: 'admin', password: 'short'),
        throwsA(isA<ValidationException>()),
      );
      expect(await auth.needsSetup(), isTrue, reason: 'nothing was written');
    });

    test('setup is owed again after the data is wiped', () async {
      await auth.createInitialAdmin(username: 'admin', password: 'lunchtime99');
      await db.wipeAllData();
      expect(await auth.needsSetup(), isTrue);
    });
  });

  group('renaming an account', () {
    Future<int> seedAdmin() async {
      await auth.createInitialAdmin(username: 'admin', password: 'lunchtime99');
      final row = await db.select(db.users).getSingle();
      return row.id;
    }

    test('the admin username can be changed and signed in with', () async {
      final id = await seedAdmin();
      await users.update(id, const UserPatch(username: 'canteen-boss'),
          actingUserId: id);

      expect(await auth.authenticate('canteen-boss', 'lunchtime99'), isNotNull);
      expect(await auth.authenticate('admin', 'lunchtime99'), isNull);
    });

    test('live sessions pick up the new name', () async {
      final id = await seedAdmin();
      final user = (await auth.authenticate('admin', 'lunchtime99'))!;
      final session = await auth.createSession(user);

      await users.update(id, const UserPatch(username: 'renamed'),
          actingUserId: id);

      // Sessions carry a denormalised username; it is what the app bar shows.
      final refreshed = await auth.requireSession(session.token);
      expect(refreshed.username, 'renamed');
    });

    test('a taken username is refused, not silently applied', () async {
      final id = await seedAdmin();
      await users.create(const UserDraft(
          username: 'counter1', password: 'lunchtime99', role: Role.counter));

      expect(
        () => users.update(id, const UserPatch(username: 'counter1'),
            actingUserId: id),
        throwsA(isA<ConflictException>()),
      );
      expect(await auth.authenticate('admin', 'lunchtime99'), isNotNull,
          reason: 'the original name is intact');
    });

    test('an invalid username is refused', () async {
      final id = await seedAdmin();
      expect(
        () => users.update(id, const UserPatch(username: 'no spaces here'),
            actingUserId: id),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('host-device password recovery', () {
    test('resets the password and signs out open sessions', () async {
      await auth.createInitialAdmin(username: 'admin', password: 'lunchtime99');
      final user = (await auth.authenticate('admin', 'lunchtime99'))!;
      final session = await auth.createSession(user);

      await auth.resetPasswordFor('admin', 'brand-new-pass');

      expect(await auth.authenticate('admin', 'brand-new-pass'), isNotNull);
      expect(await auth.authenticate('admin', 'lunchtime99'), isNull);
      // A password reset that left old tokens valid would be no reset at all.
      expect(() => auth.requireSession(session.token),
          throwsA(isA<AuthException>()));
    });

    test('refuses an unknown account and a weak password', () async {
      await auth.createInitialAdmin(username: 'admin', password: 'lunchtime99');
      expect(() => auth.resetPasswordFor('nobody', 'brand-new-pass'),
          throwsA(isA<ValidationException>()));
      expect(() => auth.resetPasswordFor('admin', 'short'),
          throwsA(isA<ValidationException>()));
    });
  });
}
