import '../core/app_mode.dart';
import '../domain/inventory.dart';
import '../domain/ledger.dart';
import '../domain/member.dart';
import '../domain/menu.dart';
import '../domain/ops.dart';
import '../domain/settings.dart';
import '../ui/theme/appearance.dart';
import '../services/settings_service.dart' show SettingsPatch;

export '../services/settings_service.dart' show SettingsPatch;

/// The one data-access seam (PRD §13.7). Every screen and every piece of
/// business-logic-adjacent UI code depends on this, never on a service or an
/// HTTP client directly. Two implementations:
///
///  * `HostBackend`  — calls the in-process services (host mode).
///  * `ClientBackend` — calls the JSON API on a discovered host (client mode).
///
/// The PRD sketches "one interface per domain"; this is a single cohesive
/// interface with per-domain sections instead — same intent (host/client is an
/// implementation detail behind one boundary), far less ceremony for ~50
/// operations.
abstract interface class Backend {
  // ---- auth ---------------------------------------------------------
  Future<AuthSession> login(String username, String password);
  Future<void> logout();

  // ---- settings ---------------------------------------------------
  Future<String> branding();

  /// App name plus the host's appearance policy, readable before sign-in.
  Future<AppearancePolicy> appearancePolicy();
  Future<SettingsSnapshot> getSettings();
  Future<List<String>> timezones();
  Future<SettingsSnapshot> updateSettings(SettingsPatch patch);

  // ---- members --------------------------------------------------
  Future<List<Member>> listMembers({String? type, String? status});
  Future<Member> getMember(int id);
  Future<Member> createMember(MemberDraft draft);
  Future<BackendBulkResult> bulkCreateMembers(List<MemberDraft> drafts);
  Future<Member> updateMember(int id, MemberPatch patch);
  Future<void> deleteMember(int id);
  Future<Member> creditMember(int id, UnitCounts units);
  Future<List<int>> memberQrPng(int id);

  // ---- scanning ----------------------------------------------
  Future<ScanResult> scan(String qrCodeId, {MealType? mealTypeOverride});
  Future<ReversalResult> reverseScan(int scanId);
  Future<List<ScanRecord>> recentScans({int? memberId, int limit});

  // ---- top-ups ---------------------------------------------
  Future<List<Topup>> listTopups({int? memberId, int limit});
  Future<Topup> createTopup(TopupDraft draft);
  Future<void> confirmTopupPayment(int id);
  Future<List<int>> topupBillPdf(int id);
  Future<List<int>> topupUpiQrPng(int id);

  // ---- refunds -------------------------------------------
  Future<List<Refund>> listRefunds({int? memberId});
  Future<Refund> createRefund(RefundDraft draft);

  // ---- menu -------------------------------------------
  Future<List<MenuCategory>> listMenuCategories();
  Future<MenuCategory> createMenuCategory(String name, String? description);
  Future<MenuCategory> updateMenuCategory(int id,
      {String? name, Object? description});
  Future<void> deleteMenuCategory(int id);
  Future<List<MenuEntry>> listMenu({DateTime? start, DateTime? end});
  Future<MenuEntry> addMenuEntry(MenuEntryDraft draft);
  Future<void> deleteMenuEntry(int id);

  // ---- ingredients & recipes ----------------------------
  Future<List<Ingredient>> listIngredients();
  Future<Ingredient> createIngredient(String name, String unit);
  Future<Ingredient> updateIngredient(int id, {String? name, String? unit});
  Future<void> deleteIngredient(int id);
  Future<List<Recipe>> listRecipes();
  Future<Recipe> createRecipe(RecipeDraft draft);
  Future<Recipe> updateRecipe(int id,
      {String? dishName, List<RecipeIngredient>? ingredients});
  Future<void> deleteRecipe(int id);

  // ---- purchase schedule ----------------------------
  Future<int> generatePurchaseSchedule(DateTime start, DateTime end);
  Future<List<PurchaseScheduleItem>> listPurchaseSchedule(
      {DateTime? start, DateTime? end});
  Future<PurchaseScheduleItem> addManualPurchaseItem(
      DateTime date, int ingredientId, String quantityNote);
  Future<PurchaseScheduleItem> updatePurchaseItem(int id,
      {String? quantityNote, bool? purchased});
  Future<void> deletePurchaseItem(int id);

  // ---- expenses ---------------------------------
  Future<List<Expense>> listExpenses({DateTime? start, DateTime? end});
  Future<Expense> addExpense(ExpenseDraft draft);
  Future<ProfitSummary> profitSummary({DateTime? start, DateTime? end});

  // ---- users ---------------------------------
  Future<List<AppUser>> listUsers();
  Future<AppUser> createUser(UserDraft draft);
  Future<AppUser> updateUser(int id, UserPatch patch);
  Future<void> deleteUser(int id);

  // ---- notifications ------------------------
  Future<List<AppNotification>> listNotifications();
  Future<void> dismissNotification(int id);
}

/// Bulk import result, transport-neutral (mirrors MemberService's BulkResult
/// without dragging the repository types across the boundary).
class BackendBulkResult {
  const BackendBulkResult({required this.created, required this.failed});

  final List<Member> created;
  final List<({int index, String name, String error})> failed;
}
