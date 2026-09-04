import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'schema_versions.dart';
import 'tables.dart';

part 'database.g.dart';

/// The host-mode database. Client mode never constructs this (PRD §13.7).
///
/// `part 'database.g.dart'` is produced by `dart run build_runner build`; it
/// does not exist until codegen runs. See the Makefile `gen` target.
@DriftDatabase(
  tables: [
    Members,
    Scans,
    Topups,
    Refunds,
    MenuCategories,
    MenuEntries,
    Ingredients,
    Recipes,
    PurchaseScheduleItems,
    Expenses,
    Users,
    Sessions,
    Notifications,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For tests: an in-memory database.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedSettingsRow();
        },
        // Each step sees the schema as it was at *that* version, never the
        // latest. Writing them against the current tables looks fine until a
        // later version adds a column, at which point an old step starts
        // referencing something that does not exist yet on a real device.
        // Regenerate the step definitions with `make schema` after a bump.
        onUpgrade: stepByStep(
          from1To2: (m, schema) async {
            // A column DEFAULT lives in the CREATE TABLE, so changing it means
            // recreating the table; TableMigration carries existing rows over.
            await m.alterTable(TableMigration(schema.appSettings));
            // Raw SQL on purpose: it names only columns that exist at v2.
            //
            // v1 shipped a `UTC` default, which is wrong for every real
            // deployment — meal windows are local wall-clock times. Only
            // installs still on that untouched default are corrected; an admin
            // who chose UTC deliberately is indistinguishable, but on a
            // pre-pilot app that trade beats every install silently keeping a
            // bad zone.
            await customStatement(
              "UPDATE app_settings SET local_timezone = 'Asia/Kolkata' "
              "WHERE local_timezone = 'UTC'",
            );
          },
          from3To4: (m, schema) async {
            // Empty by default; SettingsService fills it on first read, so an
            // upgraded host keeps serving without a restart.
            await m.addColumn(schema.appSettings, schema.appSettings.hostId);
          },
          from2To3: (m, schema) async {
            // Host-enforced appearance. Additive and defaulted off, so an
            // existing host keeps behaving exactly as it did.
            await m.addColumn(
                schema.appSettings, schema.appSettings.enforceAppearance);
            await m.addColumn(
                schema.appSettings, schema.appSettings.appearanceTheme);
            await m.addColumn(
                schema.appSettings, schema.appSettings.appearanceMode);
            await m.addColumn(
                schema.appSettings, schema.appSettings.appearanceMotion);
          },
        ),
      );

  Future<void> _seedSettingsRow() => into(appSettings).insert(
        const AppSettingsCompanion(id: Value(0)),
        mode: InsertMode.insertOrIgnore,
      );

  /// Deletes every row and re-seeds the settings singleton — a fresh install
  /// without a reinstall. Host-admin "reset all data" only; destructive, so
  /// it's gated behind a typed confirmation in the UI (CLAUDE.md §18.2).
  Future<void> wipeAllData() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
      await _seedSettingsRow();
    });
  }
}

/// Where the host's database lives. Exposed because backup and restore have
/// to address the file itself, not just the connection.
Future<File> appDatabaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(dir.path, 'canteen.sqlite'));
}

LazyDatabase _openConnection() {
  return LazyDatabase(
      () async => NativeDatabase.createInBackground(await appDatabaseFile()));
}
