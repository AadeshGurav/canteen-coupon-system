import '../core/app_mode.dart';
import '../domain/inventory.dart';
import '../domain/ledger.dart';
import '../domain/member.dart';
import '../domain/menu.dart';
import '../domain/ops.dart';
import '../domain/settings.dart';
import 'backend.dart';
import 'remote/api_client.dart';

/// [Backend] backed by the JSON API on a discovered host (client mode). Every
/// method is a request; the [ApiClient] maps errors back to the same
/// [AppException] types the host threw.
class ClientBackend implements Backend {
  ClientBackend(this._api);

  final ApiClient _api;

  List<T> _list<T>(dynamic json, T Function(Map<String, dynamic>) fromJson) =>
      (json as List<dynamic>)
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList();

  Map<String, dynamic> _obj(dynamic json) => json as Map<String, dynamic>;

  Map<String, dynamic> _range(DateTime? start, DateTime? end) => {
        if (start != null) 'start': _ymd(start),
        if (end != null) 'end': _ymd(end),
      };

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---- auth --------------------------------------------------------
  @override
  Future<AuthSession> login(String username, String password) async {
    final json = await _api.postJson('/auth/login', {
      'username': username,
      'password': password,
    });
    final session = AuthSession.fromJson(_obj(json));
    _api.token = session.token;
    return session;
  }

  @override
  Future<void> logout() async {
    try {
      await _api.postJson('/auth/logout', null);
    } finally {
      _api.token = null;
    }
  }

  // ---- settings -------------------------------------------------
  @override
  Future<String> branding() async =>
      _obj(await _api.getJson('/settings/branding'))['appName'] as String;

  @override
  Future<SettingsSnapshot> getSettings() async =>
      SettingsSnapshot.fromJson(_obj(await _api.getJson('/settings')));

  @override
  Future<List<String>> timezones() async =>
      (await _api.getJson('/settings/timezones') as List<dynamic>)
          .cast<String>();

  @override
  Future<SettingsSnapshot> updateSettings(SettingsPatch patch) async =>
      SettingsSnapshot.fromJson(
          _obj(await _api.patchJson('/settings', patch.toJson())));

  // ---- members ----------------------------------------------
  @override
  Future<List<Member>> listMembers({String? type, String? status}) async =>
      _list(
        await _api.getJson('/members', query: {
          if (type != null) 'type': type,
          if (status != null) 'status': status,
        }),
        Member.fromJson,
      );

  @override
  Future<Member> getMember(int id) async =>
      Member.fromJson(_obj(await _api.getJson('/members/$id')));

  @override
  Future<Member> createMember(MemberDraft draft) async =>
      Member.fromJson(_obj(await _api.postJson('/members', draft.toJson())));

  @override
  Future<BackendBulkResult> bulkCreateMembers(List<MemberDraft> drafts) async {
    final json = _obj(await _api.postJson(
        '/members/bulk', drafts.map((d) => d.toJson()).toList()));
    return BackendBulkResult(
      created: _list(json['created'], Member.fromJson),
      failed: (json['failed'] as List<dynamic>)
          .map((e) => (
                index: (e as Map)['index'] as int,
                name: e['name'] as String,
                error: e['error'] as String,
              ))
          .toList(),
    );
  }

  @override
  Future<Member> updateMember(int id, MemberPatch patch) async {
    final body = <String, dynamic>{
      if (patch.name != null) 'name': patch.name,
      if (patch.className != null) 'className': patch.className,
      if (patch.rollNumber != null) 'rollNumber': patch.rollNumber,
      if (patch.staffId != null) 'staffId': patch.staffId,
      if (patch.status != null) 'status': patch.status,
      if (patch.touchesGrace) 'graceAllowanceOverride': patch.graceValue,
    };
    return Member.fromJson(_obj(await _api.patchJson('/members/$id', body)));
  }

  @override
  Future<void> deleteMember(int id) => _api.deleteJson('/members/$id');

  @override
  Future<Member> creditMember(int id, UnitCounts units) async =>
      Member.fromJson(
          _obj(await _api.postJson('/members/$id/credit', units.toJson())));

  @override
  Future<List<int>> memberQrPng(int id) => _api.getBytes('/members/$id/qr');

  // ---- scanning -------------------------------------------
  @override
  Future<ScanResult> scan(String qrCodeId,
          {MealType? mealTypeOverride}) async =>
      ScanResult.fromJson(_obj(await _api.postJson('/scan', {
        'qrCodeId': qrCodeId,
        if (mealTypeOverride != null) 'mealTypeOverride': mealTypeOverride.wire,
      })));

  @override
  Future<ReversalResult> reverseScan(int scanId) async =>
      ReversalResult.fromJson(
          _obj(await _api.postJson('/scan/reverse', {'scanId': scanId})));

  @override
  Future<List<ScanRecord>> recentScans(
          {int? memberId, int limit = 200}) async =>
      _list(
        await _api.getJson('/scans', query: {
          if (memberId != null) 'memberId': memberId,
          'limit': limit,
        }),
        ScanRecord.fromJson,
      );

  // ---- top-ups ------------------------------------------
  @override
  Future<List<Topup>> listTopups({int? memberId, int limit = 200}) async =>
      _list(
        await _api.getJson('/topups', query: {
          if (memberId != null) 'memberId': memberId,
          'limit': limit,
        }),
        Topup.fromJson,
      );

  @override
  Future<Topup> createTopup(TopupDraft draft) async =>
      Topup.fromJson(_obj(await _api.postJson('/topups', draft.toJson())));

  @override
  Future<void> confirmTopupPayment(int id) =>
      _api.postJson('/topups/$id/confirm-payment', null);

  @override
  Future<List<int>> topupBillPdf(int id) => _api.getBytes('/topups/$id/bill');

  @override
  Future<List<int>> topupUpiQrPng(int id) =>
      _api.getBytes('/topups/$id/upi-qr');

  // ---- refunds ---------------------------------------
  @override
  Future<List<Refund>> listRefunds({int? memberId}) async => _list(
        await _api.getJson('/refunds', query: {
          if (memberId != null) 'memberId': memberId,
        }),
        Refund.fromJson,
      );

  @override
  Future<Refund> createRefund(RefundDraft draft) async =>
      Refund.fromJson(_obj(await _api.postJson('/refunds', draft.toJson())));

  // ---- menu -----------------------------------------
  @override
  Future<List<MenuCategory>> listMenuCategories() async =>
      _list(await _api.getJson('/menu-categories'), MenuCategory.fromJson);

  @override
  Future<MenuCategory> createMenuCategory(
          String name, String? description) async =>
      MenuCategory.fromJson(_obj(await _api.postJson('/menu-categories', {
        'name': name,
        'description': description,
      })));

  @override
  Future<MenuCategory> updateMenuCategory(int id,
      {String? name, Object? description}) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (description != null && description is String?)
        'description': description,
    };
    return MenuCategory.fromJson(
        _obj(await _api.patchJson('/menu-categories/$id', body)));
  }

  @override
  Future<void> deleteMenuCategory(int id) =>
      _api.deleteJson('/menu-categories/$id');

  @override
  Future<List<MenuEntry>> listMenu({DateTime? start, DateTime? end}) async =>
      _list(await _api.getJson('/menu', query: _range(start, end)),
          MenuEntry.fromJson);

  @override
  Future<MenuEntry> addMenuEntry(MenuEntryDraft draft) async =>
      MenuEntry.fromJson(_obj(await _api.postJson('/menu', draft.toJson())));

  @override
  Future<void> deleteMenuEntry(int id) => _api.deleteJson('/menu/$id');

  // ---- ingredients & recipes -----------------------
  @override
  Future<List<Ingredient>> listIngredients() async =>
      _list(await _api.getJson('/ingredients'), Ingredient.fromJson);

  @override
  Future<Ingredient> createIngredient(String name, String unit) async =>
      Ingredient.fromJson(_obj(
          await _api.postJson('/ingredients', {'name': name, 'unit': unit})));

  @override
  Future<Ingredient> updateIngredient(int id,
      {String? name, String? unit}) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (unit != null) 'unit': unit,
    };
    return Ingredient.fromJson(
        _obj(await _api.patchJson('/ingredients/$id', body)));
  }

  @override
  Future<void> deleteIngredient(int id) => _api.deleteJson('/ingredients/$id');

  @override
  Future<List<Recipe>> listRecipes() async =>
      _list(await _api.getJson('/recipes'), Recipe.fromJson);

  @override
  Future<Recipe> createRecipe(RecipeDraft draft) async =>
      Recipe.fromJson(_obj(await _api.postJson('/recipes', draft.toJson())));

  @override
  Future<Recipe> updateRecipe(int id,
      {String? dishName, List<RecipeIngredient>? ingredients}) async {
    final body = <String, dynamic>{
      if (dishName != null) 'dishName': dishName,
      if (ingredients != null)
        'ingredients': ingredients.map((i) => i.toJson()).toList(),
    };
    return Recipe.fromJson(_obj(await _api.patchJson('/recipes/$id', body)));
  }

  @override
  Future<void> deleteRecipe(int id) => _api.deleteJson('/recipes/$id');

  // ---- purchase schedule -------------------------
  @override
  Future<int> generatePurchaseSchedule(DateTime start, DateTime end) async =>
      _obj(await _api.postJson('/purchase-schedule/generate', null,
          query: {'start': _ymd(start), 'end': _ymd(end)}))['created'] as int;

  @override
  Future<List<PurchaseScheduleItem>> listPurchaseSchedule(
          {DateTime? start, DateTime? end}) async =>
      _list(
        await _api.getJson('/purchase-schedule', query: _range(start, end)),
        PurchaseScheduleItem.fromJson,
      );

  @override
  Future<PurchaseScheduleItem> addManualPurchaseItem(
          DateTime date, int ingredientId, String quantityNote) async =>
      PurchaseScheduleItem.fromJson(
          _obj(await _api.postJson('/purchase-schedule', {
        'date': _ymd(date),
        'ingredientId': ingredientId,
        'quantityNote': quantityNote,
      })));

  @override
  Future<PurchaseScheduleItem> updatePurchaseItem(int id,
      {String? quantityNote, bool? purchased}) async {
    final body = <String, dynamic>{
      if (quantityNote != null) 'quantityNote': quantityNote,
      if (purchased != null) 'purchased': purchased,
    };
    return PurchaseScheduleItem.fromJson(
        _obj(await _api.patchJson('/purchase-schedule/$id', body)));
  }

  @override
  Future<void> deletePurchaseItem(int id) =>
      _api.deleteJson('/purchase-schedule/$id');

  // ---- expenses --------------------------------
  @override
  Future<List<Expense>> listExpenses({DateTime? start, DateTime? end}) async =>
      _list(await _api.getJson('/expenses', query: _range(start, end)),
          Expense.fromJson);

  @override
  Future<Expense> addExpense(ExpenseDraft draft) async =>
      Expense.fromJson(_obj(await _api.postJson('/expenses', draft.toJson())));

  @override
  Future<ProfitSummary> profitSummary({DateTime? start, DateTime? end}) async =>
      ProfitSummary.fromJson(_obj(
          await _api.getJson('/expenses/summary', query: _range(start, end))));

  // ---- users ----------------------------------
  @override
  Future<List<AppUser>> listUsers() async =>
      _list(await _api.getJson('/users'), AppUser.fromJson);

  @override
  Future<AppUser> createUser(UserDraft draft) async =>
      AppUser.fromJson(_obj(await _api.postJson('/users', draft.toJson())));

  @override
  Future<AppUser> updateUser(int id, UserPatch patch) async => AppUser.fromJson(
      _obj(await _api.patchJson('/users/$id', patch.toJson())));

  @override
  Future<void> deleteUser(int id) => _api.deleteJson('/users/$id');

  // ---- notifications -------------------------
  @override
  Future<List<AppNotification>> listNotifications() async =>
      _list(await _api.getJson('/notifications'), AppNotification.fromJson);

  @override
  Future<void> dismissNotification(int id) =>
      _api.postJson('/notifications/$id/dismiss', null);
}
