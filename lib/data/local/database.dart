import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedSettingsRow();
        },
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

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'canteen.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
