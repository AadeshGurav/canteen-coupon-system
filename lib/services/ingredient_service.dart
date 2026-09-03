import 'package:drift/drift.dart';

import '../core/errors.dart';
import '../data/local/database.dart' hide Ingredient;
import '../data/local/mappers.dart';
import '../domain/inventory.dart';

/// Ingredients master list — a port of v1 `app/routers/ingredients.py`
/// (PRD §6.5.1). Admin writes; counter reads (for manual purchase items).
class IngredientService {
  IngredientService(this._db);

  final AppDatabase _db;

  Future<List<Ingredient>> list() async {
    final rows = await (_db.select(_db.ingredients)
          ..orderBy([(i) => OrderingTerm.asc(i.name)]))
        .get();
    return rows.map(ingredientFromRow).toList();
  }

  Future<Ingredient> create(String name, String unit) async {
    if (name.trim().isEmpty || unit.trim().isEmpty) {
      throw const ValidationException('Name and unit are both required.');
    }
    final now = DateTime.now().toUtc();
    try {
      final id = await _db.into(_db.ingredients).insert(
            IngredientsCompanion.insert(
                name: name, unit: unit, createdAt: now, updatedAt: now),
          );
      final row = await (_db.select(_db.ingredients)
            ..where((i) => i.id.equals(id)))
          .getSingle();
      return ingredientFromRow(row);
    } on Exception catch (e) {
      if (_isUnique(e)) {
        throw ConflictException("Ingredient '$name' already exists.");
      }
      rethrow;
    }
  }

  Future<Ingredient> update(int id, {String? name, String? unit}) async {
    if (name == null && unit == null) {
      throw const ValidationException('Nothing to update.');
    }
    try {
      final n = await (_db.update(_db.ingredients)
            ..where((i) => i.id.equals(id)))
          .write(IngredientsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        unit: unit == null ? const Value.absent() : Value(unit),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
      if (n == 0) throw const NotFoundException('Ingredient not found.');
    } on Exception catch (e) {
      if (_isUnique(e)) {
        throw ConflictException("Ingredient '$name' already exists.");
      }
      rethrow;
    }
    final row = await (_db.select(_db.ingredients)
          ..where((i) => i.id.equals(id)))
        .getSingle();
    return ingredientFromRow(row);
  }

  Future<void> delete(int id) async {
    final n =
        await (_db.delete(_db.ingredients)..where((i) => i.id.equals(id))).go();
    if (n == 0) throw const NotFoundException('Ingredient not found.');
  }

  bool _isUnique(Exception e) => e.toString().toLowerCase().contains('unique');
}
