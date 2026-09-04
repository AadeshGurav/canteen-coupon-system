import 'dart:io';

import 'package:archive/archive.dart';
import 'package:canteen_coupon/core/errors.dart';
import 'package:canteen_coupon/core/role.dart';
import 'package:canteen_coupon/data/local/database.dart';
import 'package:canteen_coupon/services/backup_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Restore replaces the only copy of a canteen's data, so the round trip is
/// asserted end to end: seed, export, wipe, restore, and check every row came
/// back — plus each way the file itself can be wrong.
void main() {
  late Directory tmp;
  late File dbFile;
  late AppDatabase db;
  late BackupService backup;

  /// A real file rather than an in-memory database, because `VACUUM INTO` is
  /// what the export actually relies on.
  Future<AppDatabase> openAt(File file) async {
    final opened = AppDatabase.forTesting(NativeDatabase(file));
    await opened.customSelect('SELECT 1').get();
    return opened;
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('tiffin-backup-test');
    dbFile = File('${tmp.path}/canteen.sqlite');
    db = await openAt(dbFile);
    backup = BackupService(db, appVersion: '2.0.0-test', workingDirectory: tmp);
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> seed() async {
    final now = DateTime.now().toUtc();
    await db.into(db.members).insert(MembersCompanion.insert(
          type: 'student',
          name: 'Aadesh Gurav',
          qrCodeId: 'qr-1',
          createdAt: now,
          updatedAt: now,
          lunchBalance: const Value(12),
        ));
    await db.into(db.users).insert(UsersCompanion.insert(
          username: 'admin',
          passwordHash: 'salt\$digest',
          role: Role.admin.wire,
          createdAt: now,
          updatedAt: now,
        ));
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          category: 'vegetables',
          description: 'Weekly',
          amount: 1250.5,
          date: now,
          createdBy: 'admin',
        ));
  }

  /// Restores [bytes] over a fresh database and hands it back for inspection.
  Future<AppDatabase> restoreInto(List<int> bytes, {String? passphrase}) async {
    final target = File('${tmp.path}/restored.sqlite');
    await backup.stageRestore(bytes, target, passphrase: passphrase);
    return openAt(target);
  }

  test('every row survives a plain round trip', () async {
    await seed();
    final bytes = await backup.export();

    // The wipe stands in for "a new phone, or this one after a reset".
    await db.wipeAllData();
    expect(await db.members.count().getSingle(), 0);

    final restored = await restoreInto(bytes);
    final member = await restored.select(restored.members).getSingle();
    expect(member.name, 'Aadesh Gurav');
    expect(member.lunchBalance, 12, reason: 'balances must come back exactly');
    expect(
        (await restored.select(restored.users).getSingle()).username, 'admin');
    expect(
        (await restored.select(restored.expenses).getSingle()).amount, 1250.5);
    await restored.close();
  });

  test('the manifest reports what is inside', () async {
    await seed();
    final manifest = backup.inspect(await backup.export());

    expect(manifest.schemaVersion, db.schemaVersion);
    expect(manifest.appVersion, '2.0.0-test');
    expect(manifest.encrypted, isFalse);
    expect(manifest.rowCounts['members'], 1);
    expect(manifest.rowCounts['expenses'], 1);
    // The settings singleton is seeded on creation, so it is always in there.
    expect(manifest.rowCounts['app_settings'], 1);
  });

  test('an encrypted backup round-trips with its password', () async {
    await seed();
    final bytes = await backup.export(passphrase: 'canteen-secret');

    expect(backup.inspect(bytes).encrypted, isTrue);
    final restored = await restoreInto(bytes, passphrase: 'canteen-secret');
    expect((await restored.select(restored.members).getSingle()).name,
        'Aadesh Gurav');
    await restored.close();
  });

  test('an encrypted backup keeps member names off the wire', () async {
    await seed();
    final plain = await backup.export();
    final sealed = await backup.export(passphrase: 'canteen-secret');

    // The zip is compressed, so the payload has to be extracted before
    // looking for plaintext — searching the container bytes would pass for
    // the wrong reason.
    List<int> payload(List<int> bytes) => ZipDecoder()
        .decodeBytes(bytes)
        .files
        .firstWhere((f) => f.name == BackupService.databaseEntry)
        .content as List<int>;

    bool holdsName(List<int> bytes) =>
        String.fromCharCodes(payload(bytes).map((b) => b & 0xFF))
            .contains('Aadesh Gurav');

    expect(holdsName(plain), isTrue,
        reason: 'sanity: an unencrypted backup does hold the name');
    expect(holdsName(sealed), isFalse,
        reason: 'an encrypted backup must not leak names to anyone with it');
  });

  test('the wrong password fails clearly, without writing anything', () async {
    await seed();
    final bytes = await backup.export(passphrase: 'canteen-secret');
    final target = File('${tmp.path}/restored.sqlite');

    await expectLater(
      backup.stageRestore(bytes, target, passphrase: 'wrong'),
      throwsA(isA<ValidationException>()),
    );
    expect(target.existsSync(), isFalse,
        reason: 'nothing is written until the file has been proven readable');
  });

  test('a missing password on a sealed backup is refused', () async {
    await seed();
    final bytes = await backup.export(passphrase: 'canteen-secret');
    await expectLater(
      backup.stageRestore(bytes, File('${tmp.path}/x.sqlite')),
      throwsA(isA<ValidationException>()),
    );
  });

  test('a file that is not a backup is refused', () async {
    await expectLater(
      backup.stageRestore(
          List<int>.filled(500, 42), File('${tmp.path}/x.sqlite')),
      throwsA(isA<ValidationException>()),
    );
  });

  test('a backup from a newer app is refused rather than half-read', () async {
    await seed();
    final bytes = await backup.export();

    // Pretend this app is older than the file it was handed.
    final older = _PretendOlderDatabase(db, db.schemaVersion - 1);
    final service =
        BackupService(older, appVersion: '1.0.0', workingDirectory: tmp);

    await expectLater(
      service.stageRestore(bytes, File('${tmp.path}/x.sqlite')),
      throwsA(isA<ValidationException>()),
    );
  });

  test('exporting leaves no snapshot behind', () async {
    await seed();
    await backup.export();

    final strays = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('backup-'));
    expect(strays, isEmpty,
        reason: 'a stray snapshot is a second full copy of everything');
  });

  test('the filename is dated so exports do not overwrite each other', () {
    final name = backup.fileName(now: DateTime(2026, 9, 4, 21, 30));
    expect(name, 'tiffin-backup-2026-09-04-2130.tiffin');
  });
}

/// Reports an older schema version while delegating everything else, so the
/// "backup from a newer app" guard can be exercised without a second schema.
class _PretendOlderDatabase extends AppDatabase {
  _PretendOlderDatabase(AppDatabase inner, this._version)
      : super.forTesting(inner.executor);

  final int _version;

  @override
  int get schemaVersion => _version;

  @override
  Future<void> close() async {
    // The inner database owns the executor; closing here would pull it out
    // from under the test's own handle.
  }
}
