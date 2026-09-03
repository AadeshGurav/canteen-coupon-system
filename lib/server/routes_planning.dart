import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/errors.dart';
import '../core/sentinels.dart';
import '../domain/inventory.dart';
import '../domain/menu.dart';
import '../domain/ops.dart';
import 'host_container.dart';
import 'http_json.dart';
import 'middleware.dart';

/// Authenticated `/api` routes for menu planning, ingredients/recipes, the
/// purchase schedule, expenses and notifications. Ports v1 `routers/menu.py`,
/// `menu_categories.py`, `ingredients.py`, `recipes.py`, `purchase_schedule.py`,
/// `expenses.py`, `notifications.py`.
Router planningRoutes(HostContainer c) {
  final router = Router();

  // ---- menu categories (admin) -------------------------------
  router.get('/menu-categories', (Request request) async {
    requireRole(request, rolesAdmin);
    return jsonList((await c.menu.listCategories()).map((x) => x.toJson()));
  });

  router.post('/menu-categories', (Request request) async {
    requireRole(request, rolesAdmin);
    final body = await readJsonObject(request);
    final created = await c.menu.createCategory(
      body['name'] as String? ?? '',
      body['description'] as String?,
    );
    return jsonOk(created.toJson());
  });

  router.patch('/menu-categories/<id>', (Request request, String id) async {
    requireRole(request, rolesAdmin);
    final body = await readJsonObject(request);
    final updated = await c.menu.updateCategory(
      pathId(id, entity: 'menu category'),
      name: body['name'] as String?,
      description: body.containsKey('description')
          ? body['description'] as String?
          : kUnset,
    );
    return jsonOk(updated.toJson());
  });

  router.delete('/menu-categories/<id>', (Request request, String id) async {
    requireRole(request, rolesAdmin);
    await c.menu.deleteCategory(pathId(id, entity: 'menu category'));
    return jsonOk({'success': true});
  });

  // ---- menu entries (admin) -------------------------------
  router.get('/menu', (Request request) async {
    requireRole(request, rolesAdmin);
    final entries = await c.menu.listEntries(
      start: dateParam(request, 'start'),
      end: dateParam(request, 'end'),
    );
    return jsonList(entries.map((e) => e.toJson()));
  });

  router.post('/menu', (Request request) async {
    final caller = requireRole(request, rolesAdmin);
    final body = await readJsonObject(request);
    final draft =
        MenuEntryDraft.fromJson({...body, 'createdBy': caller.username});
    return jsonOk((await c.menu.addEntry(draft)).toJson());
  });

  router.delete('/menu/<id>', (Request request, String id) async {
    requireRole(request, rolesAdmin);
    await c.menu.deleteEntry(pathId(id, entity: 'menu entry'));
    return jsonOk({'success': true});
  });

  // ---- ingredients (admin write, counter read) ----------
  router.get('/ingredients', (Request request) async {
    requireRole(request, rolesBilling);
    return jsonList((await c.ingredients.list()).map((i) => i.toJson()));
  });

  router.post('/ingredients', (Request request) async {
    requireRole(request, rolesAdmin);
    final body = await readJsonObject(request);
    final created = await c.ingredients.create(
      body['name'] as String? ?? '',
      body['unit'] as String? ?? '',
    );
    return jsonOk(created.toJson());
  });

  router.patch('/ingredients/<id>', (Request request, String id) async {
    requireRole(request, rolesAdmin);
    final body = await readJsonObject(request);
    final updated = await c.ingredients.update(
      pathId(id, entity: 'ingredient'),
      name: body['name'] as String?,
      unit: body['unit'] as String?,
    );
    return jsonOk(updated.toJson());
  });

  router.delete('/ingredients/<id>', (Request request, String id) async {
    requireRole(request, rolesAdmin);
    await c.ingredients.delete(pathId(id, entity: 'ingredient'));
    return jsonOk({'success': true});
  });

  // ---- recipes (admin) ------------------------------------
  router.get('/recipes', (Request request) async {
    requireRole(request, rolesAdmin);
    return jsonList((await c.recipes.list()).map((r) => r.toJson()));
  });

  router.post('/recipes', (Request request) async {
    requireRole(request, rolesAdmin);
    final draft = RecipeDraft.fromJson(await readJsonObject(request));
    return jsonOk((await c.recipes.create(draft)).toJson());
  });

  router.patch('/recipes/<id>', (Request request, String id) async {
    requireRole(request, rolesAdmin);
    final body = await readJsonObject(request);
    final ingredients = (body['ingredients'] as List<dynamic>?)
        ?.map((e) => RecipeIngredient.fromJson(e as Map<String, dynamic>))
        .toList();
    final updated = await c.recipes.update(
      pathId(id, entity: 'recipe'),
      dishName: body['dishName'] as String?,
      ingredients: ingredients,
    );
    return jsonOk(updated.toJson());
  });

  router.delete('/recipes/<id>', (Request request, String id) async {
    requireRole(request, rolesAdmin);
    await c.recipes.delete(pathId(id, entity: 'recipe'));
    return jsonOk({'success': true});
  });

  // ---- purchase schedule (admin generates/deletes; counter co-manages) ----
  router.post('/purchase-schedule/generate', (Request request) async {
    requireRole(request, rolesAdmin);
    final start = dateParam(request, 'start');
    final end = dateParam(request, 'end');
    if (start == null || end == null) {
      throw const ValidationException('start and end are required.');
    }
    final created = await c.purchaseSchedule.generate(start, end);
    return jsonOk({'created': created});
  });

  router.get('/purchase-schedule', (Request request) async {
    requireRole(request, rolesBilling);
    final items = await c.purchaseSchedule.list(
      start: dateParam(request, 'start'),
      end: dateParam(request, 'end'),
    );
    return jsonList(items.map((i) => i.toJson()));
  });

  router.post('/purchase-schedule', (Request request) async {
    requireRole(request, rolesBilling);
    final body = await readJsonObject(request);
    final item = await c.purchaseSchedule.addManual(
      DateTime.parse(body['date'] as String),
      (body['ingredientId'] as num).toInt(),
      body['quantityNote'] as String? ?? '',
    );
    return jsonOk(item.toJson());
  });

  router.patch('/purchase-schedule/<id>', (Request request, String id) async {
    final caller = requireRole(request, rolesBilling);
    final body = await readJsonObject(request);
    final updated = await c.purchaseSchedule.updateItem(
      pathId(id, entity: 'purchase schedule item'),
      quantityNote: body['quantityNote'] as String?,
      purchased: body['purchased'] as bool?,
      actingUsername: caller.username,
    );
    return jsonOk(updated.toJson());
  });

  router.delete('/purchase-schedule/<id>', (Request request, String id) async {
    requireRole(request, rolesAdmin);
    await c.purchaseSchedule
        .deleteItem(pathId(id, entity: 'purchase schedule item'));
    return jsonOk({'success': true});
  });

  // ---- expenses (admin) ----------------------------------
  router.get('/expenses', (Request request) async {
    requireRole(request, rolesAdmin);
    final expenses = await c.expenses.list(
      start: dateParam(request, 'start'),
      end: dateParam(request, 'end'),
    );
    return jsonList(expenses.map((e) => e.toJson()));
  });

  router.post('/expenses', (Request request) async {
    final caller = requireRole(request, rolesAdmin);
    final body = await readJsonObject(request);
    final created = await c.expenses.add(
      ExpenseDraft.fromJson({...body, 'createdBy': caller.username}),
    );
    return jsonOk(created.toJson());
  });

  router.get('/expenses/summary', (Request request) async {
    requireRole(request, rolesAdmin);
    final summary = await c.expenses.summary(
      start: dateParam(request, 'start'),
      end: dateParam(request, 'end'),
    );
    return jsonOk(summary.toJson());
  });

  // ---- notifications (all roles) -------------------------
  router.get('/notifications', (Request request) async {
    final caller = callerOf(request);
    await c.notifications.generateDue(DateTime.now().toUtc());
    final list = await c.notifications.listFor(caller.role, caller.username);
    return jsonList(list.map((n) => n.toJson()));
  });

  router.post('/notifications/<id>/dismiss',
      (Request request, String id) async {
    final caller = callerOf(request);
    await c.notifications.dismiss(
      pathId(id, entity: 'notification'),
      caller.username,
    );
    return jsonOk({'success': true});
  });

  return router;
}
