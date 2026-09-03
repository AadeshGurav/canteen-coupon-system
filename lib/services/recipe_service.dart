import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/errors.dart';
import '../data/local/database.dart' hide Recipe;
import '../data/local/mappers.dart';
import '../domain/inventory.dart';

/// Recipes — a port of v1 `app/routers/recipes.py` (PRD §6.5.1). A dish name
/// (matched case-insensitively against menu items) linked to ingredients with
/// free-text quantity notes.
class RecipeService {
  RecipeService(this._db);

  final AppDatabase _db;

  Future<List<Recipe>> list() async {
    final rows = await (_db.select(_db.recipes)
          ..orderBy([(r) => OrderingTerm.asc(r.dishName)]))
        .get();
    return rows.map(recipeFromRow).toList();
  }

  Future<Recipe> create(RecipeDraft draft) async {
    if (draft.dishName.trim().isEmpty) {
      throw const ValidationException('Dish name cannot be blank.');
    }
    if (draft.ingredients.isEmpty) {
      throw const ValidationException(
          'A recipe needs at least one ingredient.');
    }
    await _validateIngredientIds(draft.ingredients.map((i) => i.ingredientId));

    final now = DateTime.now().toUtc();
    try {
      final id = await _db.into(_db.recipes).insert(RecipesCompanion.insert(
            dishName: draft.dishName,
            dishNameLower: draft.dishName.trim().toLowerCase(),
            ingredientsJson:
                jsonEncode(draft.ingredients.map((i) => i.toJson()).toList()),
            createdAt: now,
            updatedAt: now,
          ));
      final row = await (_db.select(_db.recipes)..where((r) => r.id.equals(id)))
          .getSingle();
      return recipeFromRow(row);
    } on Exception catch (e) {
      if (_isUnique(e)) {
        throw ConflictException(
            "A recipe for '${draft.dishName}' already exists.");
      }
      rethrow;
    }
  }

  Future<Recipe> update(
    int id, {
    String? dishName,
    List<RecipeIngredient>? ingredients,
  }) async {
    if (dishName == null && ingredients == null) {
      throw const ValidationException('Nothing to update.');
    }
    if (ingredients != null) {
      await _validateIngredientIds(ingredients.map((i) => i.ingredientId));
    }
    final companion = RecipesCompanion(
      dishName: dishName == null ? const Value.absent() : Value(dishName),
      dishNameLower: dishName == null
          ? const Value.absent()
          : Value(dishName.trim().toLowerCase()),
      ingredientsJson: ingredients == null
          ? const Value.absent()
          : Value(jsonEncode(ingredients.map((i) => i.toJson()).toList())),
      updatedAt: Value(DateTime.now().toUtc()),
    );
    try {
      final n = await (_db.update(_db.recipes)..where((r) => r.id.equals(id)))
          .write(companion);
      if (n == 0) throw const NotFoundException('Recipe not found.');
    } on Exception catch (e) {
      if (_isUnique(e)) {
        throw ConflictException("A recipe for '$dishName' already exists.");
      }
      rethrow;
    }
    final row = await (_db.select(_db.recipes)..where((r) => r.id.equals(id)))
        .getSingle();
    return recipeFromRow(row);
  }

  Future<void> delete(int id) async {
    final n =
        await (_db.delete(_db.recipes)..where((r) => r.id.equals(id))).go();
    if (n == 0) throw const NotFoundException('Recipe not found.');
  }

  Future<void> _validateIngredientIds(Iterable<int> ids) async {
    final unique = ids.toSet();
    final found = (await (_db.select(_db.ingredients)
              ..where((i) => i.id.isIn(unique)))
            .get())
        .length;
    if (found != unique.length) {
      throw const ValidationException(
          "One or more ingredient ids don't match a known ingredient.");
    }
  }

  bool _isUnique(Exception e) => e.toString().toLowerCase().contains('unique');
}
