import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/errors.dart';
import '../data/local/database.dart' hide PurchaseScheduleItem;
import '../data/local/mappers.dart';
import '../domain/inventory.dart';

/// Derives a shopping list from the menu calendar — a port of v1
/// `app/services/purchase_schedule_service.py` + `app/routers/purchase_schedule.py`
/// (PRD §6.5.1).
///
/// [generate] is idempotent: re-running it over an overlapping range never
/// duplicates an item or resets one already checked off. It does this the same
/// way v1 did — check whether a row for (date, ingredient) exists before
/// inserting — rather than a DB unique constraint, so ad-hoc manual items for
/// the same (date, ingredient) still coexist.
class PurchaseScheduleService {
  PurchaseScheduleService(this._db);

  final AppDatabase _db;

  /// Returns the count of newly created items.
  Future<int> generate(DateTime start, DateTime end) async {
    if (start.isAfter(end)) {
      throw const ValidationException('start must be on or before end.');
    }
    final startDate = _dateOnly(start);
    final endDate = _dateOnly(end);

    final entries = await (_db.select(_db.menuEntries)
          ..where((e) =>
              e.date.isBiggerOrEqualValue(startDate) &
              e.date.isSmallerOrEqualValue(endDate)))
        .get();
    if (entries.isEmpty) return 0;

    // dishNameLower -> recipe row
    final allRecipes = await _db.select(_db.recipes).get();
    final recipeByDish = {for (final r in allRecipes) r.dishNameLower: r};

    // ingredientId -> ingredient row (only those a matched recipe references)
    final allIngredients = await _db.select(_db.ingredients).get();
    final ingredientById = {for (final i in allIngredients) i.id: i};

    final now = DateTime.now().toUtc();
    var created = 0;

    for (final entry in entries) {
      final entryDate = _dateOnly(entry.date);
      final items =
          (jsonDecode(entry.itemsJson) as List<dynamic>).cast<String>();
      for (final itemName in items) {
        final recipe = recipeByDish[itemName.trim().toLowerCase()];
        if (recipe == null) continue;

        final recipeIngredients = (jsonDecode(recipe.ingredientsJson)
                as List<dynamic>)
            .map((e) => RecipeIngredient.fromJson(e as Map<String, dynamic>))
            .toList();

        for (final ri in recipeIngredients) {
          final ingredient = ingredientById[ri.ingredientId];
          if (ingredient == null) {
            continue; // deleted after the recipe was saved
          }

          final exists = await (_db.select(_db.purchaseScheduleItems)
                    ..where((p) =>
                        p.date.equals(entryDate) &
                        p.ingredientId.equals(ri.ingredientId))
                    ..limit(1))
                  .getSingleOrNull() !=
              null;
          if (exists) continue;

          await _db.into(_db.purchaseScheduleItems).insert(
                PurchaseScheduleItemsCompanion.insert(
                  date: entryDate,
                  ingredientId: ri.ingredientId,
                  ingredientName: ingredient.name,
                  ingredientUnit: ingredient.unit,
                  quantityNote: ri.quantityNote,
                  source: 'auto',
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          created++;
        }
      }
    }
    return created;
  }

  Future<List<PurchaseScheduleItem>> list({
    DateTime? start,
    DateTime? end,
  }) async {
    final query = _db.select(_db.purchaseScheduleItems)
      ..orderBy([(p) => OrderingTerm.asc(p.date)]);
    if (start != null) {
      query.where((p) => p.date.isBiggerOrEqualValue(_dateOnly(start)));
    }
    if (end != null) {
      query.where((p) => p.date.isSmallerOrEqualValue(_dateOnly(end)));
    }
    return (await query.get()).map(purchaseItemFromRow).toList();
  }

  Future<PurchaseScheduleItem> addManual(
    DateTime date,
    int ingredientId,
    String quantityNote,
  ) async {
    if (quantityNote.trim().isEmpty) {
      throw const ValidationException('A quantity note is required.');
    }
    final ingredient = await (_db.select(_db.ingredients)
          ..where((i) => i.id.equals(ingredientId)))
        .getSingleOrNull();
    if (ingredient == null) {
      throw const NotFoundException('Ingredient not found.');
    }
    final now = DateTime.now().toUtc();
    final id = await _db.into(_db.purchaseScheduleItems).insert(
          PurchaseScheduleItemsCompanion.insert(
            date: _dateOnly(date),
            ingredientId: ingredientId,
            ingredientName: ingredient.name,
            ingredientUnit: ingredient.unit,
            quantityNote: quantityNote,
            source: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final row = await (_db.select(_db.purchaseScheduleItems)
          ..where((p) => p.id.equals(id)))
        .getSingle();
    return purchaseItemFromRow(row);
  }

  /// [actingUsername] is recorded when an item is marked purchased.
  Future<PurchaseScheduleItem> updateItem(
    int id, {
    String? quantityNote,
    bool? purchased,
    required String actingUsername,
  }) async {
    if (quantityNote == null && purchased == null) {
      throw const ValidationException('Nothing to update.');
    }
    final now = DateTime.now().toUtc();
    final companion = PurchaseScheduleItemsCompanion(
      quantityNote:
          quantityNote == null ? const Value.absent() : Value(quantityNote),
      purchased: purchased == null ? const Value.absent() : Value(purchased),
      purchasedBy: purchased == null
          ? const Value.absent()
          : Value(purchased ? actingUsername : null),
      purchasedAt: purchased == null
          ? const Value.absent()
          : Value(purchased ? now : null),
      updatedAt: Value(now),
    );
    final n = await (_db.update(_db.purchaseScheduleItems)
          ..where((p) => p.id.equals(id)))
        .write(companion);
    if (n == 0) {
      throw const NotFoundException('Purchase schedule item not found.');
    }
    final row = await (_db.select(_db.purchaseScheduleItems)
          ..where((p) => p.id.equals(id)))
        .getSingle();
    return purchaseItemFromRow(row);
  }

  Future<void> deleteItem(int id) async {
    final n = await (_db.delete(_db.purchaseScheduleItems)
          ..where((p) => p.id.equals(id)))
        .go();
    if (n == 0) {
      throw const NotFoundException('Purchase schedule item not found.');
    }
  }

  DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);
}
