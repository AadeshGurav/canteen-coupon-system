import 'package:canteen_coupon/data/local/database.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v1.dart' as v1;

/// Migrations are the one place a bug silently corrupts a host's only copy of
/// the data, so every schema bump gets a test that runs the real migration
/// against a real v(n-1) database.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  /// Seeds a v1 database with one settings row, then hands back a live v2
  /// [AppDatabase] on the same file with the migration applied and verified.
  Future<AppDatabase> migrated({String? timezone, String appName = 'T'}) async {
    final schema = await verifier.schemaAt(1);
    final old = v1.DatabaseAtV1(schema.newConnection());
    await old.customStatement(
      'INSERT INTO app_settings (id, app_name'
      '${timezone == null ? '' : ', local_timezone'}) '
      'VALUES (0, ?${timezone == null ? '' : ', ?'})',
      [appName, if (timezone != null) timezone],
    );
    await old.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
    return db;
  }

  test('v1 seeds UTC — the default this migration exists to correct', () async {
    final schema = await verifier.schemaAt(1);
    final old = v1.DatabaseAtV1(schema.newConnection());
    await old.customStatement('INSERT INTO app_settings (id) VALUES (0)');
    final row = await old
        .customSelect('SELECT local_timezone AS tz FROM app_settings')
        .getSingle();
    expect(row.read<String>('tz'), 'UTC');
    await old.close();
  });

  test('v1 -> v2 moves an untouched UTC default to Asia/Kolkata', () async {
    final db = await migrated();
    final settings = await db.select(db.appSettings).getSingle();
    expect(settings.localTimezone, 'Asia/Kolkata');
    expect(settings.appName, 'T', reason: 'other columns survive the rebuild');
    await db.close();
  });

  test('v1 -> v2 leaves a deliberately chosen zone alone', () async {
    final db = await migrated(timezone: 'Europe/Berlin');
    expect((await db.select(db.appSettings).getSingle()).localTimezone,
        'Europe/Berlin');
    await db.close();
  });

  test('a fresh database starts on Asia/Kolkata, not UTC', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    expect((await db.select(db.appSettings).getSingle()).localTimezone,
        'Asia/Kolkata');
    await db.close();
  });
}
