import 'package:canteen_coupon/data/local/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated_migrations/schema.dart';

/// Migrations are the one place a bug silently corrupts a host's only copy of
/// the data, so every schema bump runs against a real database at the previous
/// version — including from the oldest version still in the wild, which is
/// where step ordering bugs actually show up.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  const current = 3;

  Future<String> timezoneOf(AppDatabase db) async =>
      (await db.select(db.appSettings).getSingle()).localTimezone;

  /// Opens a database at [from], seeds the settings row, then migrates it all
  /// the way to the current version and validates the resulting schema.
  Future<AppDatabase> migrated(int from, {String? timezone}) async {
    final schema = await verifier.schemaAt(from);
    final seed = schema.newConnection();
    await seed.executor.ensureOpen(_SeedUser(from));
    await seed.executor.runCustom(
      'INSERT INTO app_settings (id, app_name'
      '${timezone == null ? '' : ', local_timezone'}) '
      'VALUES (0, ?${timezone == null ? '' : ', ?'})',
      ['Tiffin', if (timezone != null) timezone],
    );
    await seed.executor.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, current);
    return db;
  }

  for (final from in [1, 2]) {
    test('v$from -> v$current keeps the schema valid and the row intact',
        () async {
      final db = await migrated(from);
      final settings = await db.select(db.appSettings).getSingle();
      expect(settings.appName, 'Tiffin',
          reason: 'existing data survives the migration');
      // Appearance enforcement is additive and must default to off, so an
      // existing host behaves exactly as it did before the upgrade.
      expect(settings.enforceAppearance, isFalse);
      expect(settings.appearanceTheme, 'neobrutal');
      expect(settings.appearanceMode, 'system');
      expect(settings.appearanceMotion, isTrue);
      await db.close();
    });
  }

  test('v1 -> v3 moves an untouched UTC default to Asia/Kolkata', () async {
    final db = await migrated(1);
    expect(await timezoneOf(db), 'Asia/Kolkata');
    await db.close();
  });

  test('v1 -> v3 leaves a deliberately chosen zone alone', () async {
    final db = await migrated(1, timezone: 'Europe/Berlin');
    expect(await timezoneOf(db), 'Europe/Berlin');
    await db.close();
  });

  test('v2 -> v3 does not touch the timezone at all', () async {
    // The UTC correction belongs to the 1->2 step only; re-running it on a
    // v2 database would override a zone the admin chose after upgrading.
    final db = await migrated(2, timezone: 'UTC');
    expect(await timezoneOf(db), 'UTC');
    await db.close();
  });

  test('a fresh database starts on Asia/Kolkata, not UTC', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    expect(await timezoneOf(db), 'Asia/Kolkata');
    await db.close();
  });
}

/// [QueryExecutor.ensureOpen] wants a user, and it stamps that user's version
/// onto the database. It must therefore report the version actually being
/// seeded — reporting 1 here silently re-ran the 1->2 step on a v2 database.
class _SeedUser extends QueryExecutorUser {
  _SeedUser(this.schemaVersion);

  @override
  final int schemaVersion;

  @override
  Future<void> beforeOpen(_, __) async {}
}
