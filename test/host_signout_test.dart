import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiffin/core/errors.dart';
import 'package:tiffin/data/host_backend.dart';
import 'package:tiffin/data/local/database.dart';
import 'package:tiffin/domain/ops.dart';
import 'package:tiffin/server/host_container.dart';

/// Signing out on the host device.
///
/// The bug: HostBackend.logout() cleared its own fields but never deleted the
/// session row it created. Combined with the client remembering tokens, an
/// operator tapped "Sign out", landed on the login screen, and was signed
/// straight back in by the resume path — so sign-out appeared to do nothing.
void main() {
  late Directory tmp;
  late AppDatabase db;
  late HostContainer container;
  late HostBackend backend;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('tiffin-signout');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();

    container = HostContainer.create(
      db: db,
      documentsDir: tmp.path,
      sessionTtl: const Duration(hours: 12),
    );
    await container.bootstrap();
    await container.auth
        .createInitialAdmin(username: 'admin', password: 'lunchtime99');
    backend = HostBackend(container);
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<int> sessionCount() => db.sessions.count().getSingle();

  test('signing out deletes the session, not just local state', () async {
    final session = await backend.login('admin', 'lunchtime99');
    expect(await sessionCount(), 1);

    await backend.logout();

    expect(await sessionCount(), 0,
        reason: 'a session that outlives sign-out is not a sign-out');
    // The token the device may still have saved must no longer open anything.
    expect(await backend.resumeSession(session.token), isNull);
  });

  test('a signed-out token cannot be resumed back into a session', () async {
    final session = await backend.login('admin', 'lunchtime99');
    await backend.logout();

    expect(await backend.resumeSession(session.token), isNull,
        reason: 'this is exactly what signed the operator straight back in');
  });

  ExpenseDraft draft() => ExpenseDraft(
        category: 'vegetables',
        description: 'Weekly',
        amount: 120,
        date: DateTime.now().toUtc(),
        createdBy: 'ignored — the backend attributes it to the session',
      );

  test('resuming adopts the session, so attributed work still functions',
      () async {
    final session = await backend.login('admin', 'lunchtime99');
    // A fresh backend is what an app relaunch looks like.
    final relaunched = HostBackend(container);

    final resumed = await relaunched.resumeSession(session.token);
    expect(resumed, isNotNull);
    expect(resumed!.username, 'admin');

    // Without adopting the session the caller looks signed in while anything
    // that records *who* did it trips the "not logged in" guard.
    final expense = await relaunched.addExpense(draft());
    expect(expense.createdBy, 'admin',
        reason: 'the resumed identity is what gets recorded');
  });

  test('an un-resumed backend refuses to attribute work to nobody', () async {
    expect(() => HostBackend(container).addExpense(draft()),
        throwsA(isA<AuthException>()));
  });

  test('after signing out, attributed work is refused again', () async {
    await backend.login('admin', 'lunchtime99');
    await backend.logout();
    expect(() => backend.addExpense(draft()), throwsA(isA<AuthException>()));
  });

  test('signing out twice is harmless', () async {
    await backend.login('admin', 'lunchtime99');
    await backend.logout();
    await backend.logout();
    expect(await sessionCount(), 0);
  });

  test('one device signing out leaves another session alone', () async {
    final other = HostBackend(container);
    await other.login('admin', 'lunchtime99');
    final mine = await backend.login('admin', 'lunchtime99');
    expect(await sessionCount(), 2);

    await backend.logout();

    expect(await sessionCount(), 1,
        reason: 'signing out one device must not sign out the others');
    expect(await other.resumeSession(mine.token), isNull);
  });
}
