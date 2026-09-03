import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/errors.dart';
import '../core/sentinels.dart';
import '../data/local/database.dart' hide MenuCategory, MenuEntry;
import '../data/local/mappers.dart';
import '../domain/menu.dart';

/// Menu categories + menu entries — a port of v1 `app/routers/menu_categories.py`
/// and `app/routers/menu.py` (PRD §6.5). Categories are a first-class editable
/// list, not an enum.
class MenuService {
  MenuService(this._db);

  final AppDatabase _db;

  // ---- categories --------------------------------------------------

  Future<List<MenuCategory>> listCategories() async {
    final rows = await (_db.select(_db.menuCategories)
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .get();
    return rows.map(menuCategoryFromRow).toList();
  }

  Future<MenuCategory> createCategory(String name, String? description) async {
    if (name.trim().isEmpty) {
      throw const ValidationException('Category name cannot be blank.');
    }
    final now = DateTime.now().toUtc();
    try {
      final id = await _db.into(_db.menuCategories).insert(
            MenuCategoriesCompanion.insert(
              name: name,
              description: Value(description),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final row = await (_db.select(_db.menuCategories)
            ..where((c) => c.id.equals(id)))
          .getSingle();
      return menuCategoryFromRow(row);
    } on Exception catch (e) {
      if (_isUnique(e)) {
        throw ConflictException("Menu category '$name' already exists.");
      }
      rethrow;
    }
  }

  Future<MenuCategory> updateCategory(
    int id, {
    String? name,
    Object? description = kUnset,
  }) async {
    final companion = MenuCategoriesCompanion(
      name: name == null ? const Value.absent() : Value(name),
      description: identical(description, kUnset)
          ? const Value.absent()
          : Value(description as String?),
      updatedAt: Value(DateTime.now().toUtc()),
    );
    try {
      final n = await (_db.update(_db.menuCategories)
            ..where((c) => c.id.equals(id)))
          .write(companion);
      if (n == 0) throw const NotFoundException('Menu category not found.');
    } on Exception catch (e) {
      if (_isUnique(e)) {
        throw ConflictException("Menu category '$name' already exists.");
      }
      rethrow;
    }
    final row = await (_db.select(_db.menuCategories)
          ..where((c) => c.id.equals(id)))
        .getSingle();
    return menuCategoryFromRow(row);
  }

  Future<void> deleteCategory(int id) async {
    final n = await (_db.delete(_db.menuCategories)
          ..where((c) => c.id.equals(id)))
        .go();
    if (n == 0) throw const NotFoundException('Menu category not found.');
  }

  // ---- entries ---------------------------------------------------

  Future<List<MenuEntry>> listEntries({DateTime? start, DateTime? end}) async {
    final query = _db.select(_db.menuEntries)
      ..orderBy([(e) => OrderingTerm.asc(e.date)]);
    if (start != null) {
      query.where((e) => e.date.isBiggerOrEqualValue(_dateOnly(start)));
    }
    if (end != null) {
      query.where((e) => e.date.isSmallerOrEqualValue(_dateOnly(end)));
    }
    return (await query.get()).map(menuEntryFromRow).toList();
  }

  Future<MenuEntry> addEntry(MenuEntryDraft draft) async {
    if (draft.categories.isEmpty) {
      throw const ValidationException('At least one category is required.');
    }
    if (draft.items.isEmpty) {
      throw const ValidationException('At least one item is required.');
    }
    await _validateCategoryNames(draft.categories);

    final id =
        await _db.into(_db.menuEntries).insert(MenuEntriesCompanion.insert(
              date: _dateOnly(draft.date),
              mealType: draft.mealType.wire,
              categoriesJson: jsonEncode(draft.categories),
              itemsJson: jsonEncode(draft.items),
              createdBy: draft.createdBy,
            ));
    final row = await (_db.select(_db.menuEntries)
          ..where((e) => e.id.equals(id)))
        .getSingle();
    return menuEntryFromRow(row);
  }

  Future<void> deleteEntry(int id) async {
    final n =
        await (_db.delete(_db.menuEntries)..where((e) => e.id.equals(id))).go();
    if (n == 0) throw const NotFoundException('Menu entry not found.');
  }

  Future<void> _validateCategoryNames(List<String> names) async {
    final existing = (await (_db.select(_db.menuCategories)
              ..where((c) => c.name.isIn(names)))
            .get())
        .map((c) => c.name)
        .toSet();
    final unknown = names.where((n) => !existing.contains(n)).toList();
    if (unknown.isNotEmpty) {
      throw ValidationException(
        'Unknown menu category/categories: ${unknown.join(', ')}. '
        'Create them first.',
      );
    }
  }

  DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  bool _isUnique(Exception e) => e.toString().toLowerCase().contains('unique');

}
