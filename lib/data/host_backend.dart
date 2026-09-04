import '../core/app_mode.dart';
import '../core/errors.dart';
import '../core/role.dart';
import '../core/sentinels.dart';
import '../domain/inventory.dart';
import '../domain/ledger.dart';
import '../domain/member.dart';
import '../domain/menu.dart';
import '../domain/ops.dart';
import '../domain/settings.dart';
import '../ui/theme/appearance.dart';
import '../server/host_container.dart';
import 'backend.dart';

/// [Backend] backed by the in-process services (host mode). The operator on the
/// host device is a real logged-in user too — [login] creates a local session
/// so the same "who did this" data (createdBy / processedBy / actingUserId) the
/// API routes inject is available here.
class HostBackend implements Backend {
  HostBackend(this._c);

  final HostContainer _c;

  int? _userId;
  String _username = 'host';

  void _requireSession() {
    if (_userId == null) {
      throw const AuthException('Not logged in on this device.');
    }
  }

  @override
  Future<AuthSession> login(String username, String password) async {
    final user = await _c.auth.authenticate(username, password);
    if (user == null) {
      throw const AuthException('Incorrect username or password.');
    }
    final session = await _c.auth.createSession(user);
    _userId = session.userId;
    _username = session.username;
    return AuthSession(
      token: session.token,
      username: session.username,
      role: Role.fromWire(session.role),
    );
  }

  @override
  Future<void> logout() async {
    _userId = null;
    _username = 'host';
  }

  @override
  Future<String> branding() => _c.settings.readAppName();

  @override
  Future<AppearancePolicy> appearancePolicy() async =>
      AppearancePolicy.fromWire(await _c.settings.readPublicAppearance());

  @override
  Future<SettingsSnapshot> getSettings() => _c.settings.read();

  @override
  Future<List<String>> timezones() async => _c.settings.availableTimezones();

  @override
  Future<SettingsSnapshot> updateSettings(SettingsPatch patch) =>
      _c.settings.update(patch);

  @override
  Future<List<Member>> listMembers({String? type, String? status}) =>
      _c.members.list(type: type, status: status);

  @override
  Future<Member> getMember(int id) => _c.members.getById(id);

  @override
  Future<Member> createMember(MemberDraft draft) => _c.members.create(draft);

  @override
  Future<BackendBulkResult> bulkCreateMembers(List<MemberDraft> drafts) async {
    final result = await _c.members.createBulk(drafts);
    return BackendBulkResult(
      created: result.created,
      failed: result.failed
          .map((f) => (index: f.index, name: f.name, error: f.error))
          .toList(),
    );
  }

  @override
  Future<Member> updateMember(int id, MemberPatch patch) =>
      _c.members.update(id, patch);

  @override
  Future<void> deleteMember(int id) => _c.members.delete(id);

  @override
  Future<Member> creditMember(int id, UnitCounts units) =>
      _c.members.credit(id, units);

  @override
  Future<List<int>> memberQrPng(int id) => _c.members.renderQr(id);

  @override
  Future<ScanResult> scan(String qrCodeId, {MealType? mealTypeOverride}) =>
      _c.scans.processScan(qrCodeId, mealTypeOverride: mealTypeOverride);

  @override
  Future<ReversalResult> reverseScan(int scanId) {
    _requireSession();
    return _c.scans.reverseScan(scanId, _username);
  }

  @override
  Future<List<ScanRecord>> recentScans({int? memberId, int limit = 200}) =>
      _c.scans.recentScans(memberId: memberId, limit: limit);

  @override
  Future<List<Topup>> listTopups({int? memberId, int limit = 200}) =>
      _c.topups.list(memberId: memberId, limit: limit);

  @override
  Future<Topup> createTopup(TopupDraft draft) {
    _requireSession();
    return _c.topups.create(TopupDraft(
      memberId: draft.memberId,
      lunchUnits: draft.lunchUnits,
      breakfastUnits: draft.breakfastUnits,
      brunchUnits: draft.brunchUnits,
      paymentMethod: draft.paymentMethod,
      createdBy: _username,
    ));
  }

  @override
  Future<void> confirmTopupPayment(int id) => _c.topups.confirmPayment(id);

  @override
  Future<List<int>> topupBillPdf(int id) => _c.topups.billPdf(id);

  @override
  Future<List<int>> topupUpiQrPng(int id) => _c.topups.upiQr(id);

  @override
  Future<List<Refund>> listRefunds({int? memberId}) =>
      _c.refunds.list(memberId: memberId);

  @override
  Future<Refund> createRefund(RefundDraft draft) {
    _requireSession();
    return _c.refunds.create(RefundDraft(
      memberId: draft.memberId,
      lunchUnits: draft.lunchUnits,
      breakfastUnits: draft.breakfastUnits,
      brunchUnits: draft.brunchUnits,
      reason: draft.reason,
      processedBy: _username,
    ));
  }

  @override
  Future<List<MenuCategory>> listMenuCategories() => _c.menu.listCategories();

  @override
  Future<MenuCategory> createMenuCategory(String name, String? description) =>
      _c.menu.createCategory(name, description);

  @override
  Future<MenuCategory> updateMenuCategory(int id,
          {String? name, Object? description = kUnset}) =>
      _c.menu.updateCategory(id, name: name, description: description);

  @override
  Future<void> deleteMenuCategory(int id) => _c.menu.deleteCategory(id);

  @override
  Future<List<MenuEntry>> listMenu({DateTime? start, DateTime? end}) =>
      _c.menu.listEntries(start: start, end: end);

  @override
  Future<MenuEntry> addMenuEntry(MenuEntryDraft draft) {
    _requireSession();
    return _c.menu.addEntry(MenuEntryDraft(
      date: draft.date,
      mealType: draft.mealType,
      categories: draft.categories,
      items: draft.items,
      createdBy: _username,
    ));
  }

  @override
  Future<void> deleteMenuEntry(int id) => _c.menu.deleteEntry(id);

  @override
  Future<List<Ingredient>> listIngredients() => _c.ingredients.list();

  @override
  Future<Ingredient> createIngredient(String name, String unit) =>
      _c.ingredients.create(name, unit);

  @override
  Future<Ingredient> updateIngredient(int id, {String? name, String? unit}) =>
      _c.ingredients.update(id, name: name, unit: unit);

  @override
  Future<void> deleteIngredient(int id) => _c.ingredients.delete(id);

  @override
  Future<List<Recipe>> listRecipes() => _c.recipes.list();

  @override
  Future<Recipe> createRecipe(RecipeDraft draft) => _c.recipes.create(draft);

  @override
  Future<Recipe> updateRecipe(int id,
          {String? dishName, List<RecipeIngredient>? ingredients}) =>
      _c.recipes.update(id, dishName: dishName, ingredients: ingredients);

  @override
  Future<void> deleteRecipe(int id) => _c.recipes.delete(id);

  @override
  Future<int> generatePurchaseSchedule(DateTime start, DateTime end) =>
      _c.purchaseSchedule.generate(start, end);

  @override
  Future<List<PurchaseScheduleItem>> listPurchaseSchedule(
          {DateTime? start, DateTime? end}) =>
      _c.purchaseSchedule.list(start: start, end: end);

  @override
  Future<PurchaseScheduleItem> addManualPurchaseItem(
          DateTime date, int ingredientId, String quantityNote) =>
      _c.purchaseSchedule.addManual(date, ingredientId, quantityNote);

  @override
  Future<PurchaseScheduleItem> updatePurchaseItem(int id,
      {String? quantityNote, bool? purchased}) {
    _requireSession();
    return _c.purchaseSchedule.updateItem(
      id,
      quantityNote: quantityNote,
      purchased: purchased,
      actingUsername: _username,
    );
  }

  @override
  Future<void> deletePurchaseItem(int id) => _c.purchaseSchedule.deleteItem(id);

  @override
  Future<List<Expense>> listExpenses({DateTime? start, DateTime? end}) =>
      _c.expenses.list(start: start, end: end);

  @override
  Future<Expense> addExpense(ExpenseDraft draft) {
    _requireSession();
    return _c.expenses.add(ExpenseDraft(
      category: draft.category,
      description: draft.description,
      amount: draft.amount,
      date: draft.date,
      createdBy: _username,
    ));
  }

  @override
  Future<ProfitSummary> profitSummary({DateTime? start, DateTime? end}) =>
      _c.expenses.summary(start: start, end: end);

  @override
  Future<List<AppUser>> listUsers() => _c.users.list();

  @override
  Future<AppUser> createUser(UserDraft draft) => _c.users.create(draft);

  @override
  Future<AppUser> updateUser(int id, UserPatch patch) {
    _requireSession();
    return _c.users.update(id, patch, actingUserId: _userId!);
  }

  @override
  Future<void> deleteUser(int id) {
    _requireSession();
    return _c.users.delete(id, actingUserId: _userId!);
  }

  @override
  Future<List<AppNotification>> listNotifications() async {
    _requireSession();
    await _c.notifications.generateDue(DateTime.now().toUtc());
    // Host operator's role: look it up from the session's user row is
    // overkill here — the host console is admin-facing, so admin visibility.
    return _c.notifications.listFor(Role.admin, _username);
  }

  @override
  Future<void> dismissNotification(int id) {
    _requireSession();
    return _c.notifications.dismiss(id, _username);
  }
}
