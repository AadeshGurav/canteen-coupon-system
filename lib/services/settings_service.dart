import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/errors.dart';
import '../core/logging.dart';
import '../data/local/database.dart';
import '../domain/settings.dart';

/// Reads and validates the single global settings row (PRD §6.8). The row is
/// seeded on database creation (see `AppDatabase.migration`), so `read()` is a
/// plain lookup with no create-if-missing branch — the v1 upsert race that
/// motivated `get_global_settings`'s comment doesn't exist here (one process,
/// one writer).
class SettingsService {
  SettingsService(this._db);

  final AppDatabase _db;
  final _log = log('settings');

  static final _hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  Future<SettingsSnapshot> read() async {
    final row = await (_db.select(_db.appSettings)
          ..where((s) => s.id.equals(0)))
        .getSingle();
    return _toSnapshot(row);
  }

  SettingsSnapshot _toSnapshot(AppSetting r) => SettingsSnapshot(
        graceAllowanceEnabled: r.graceAllowanceEnabled,
        graceAllowanceUnits: r.graceAllowanceUnits,
        reversalWindowMinutes: r.reversalWindowMinutes,
        mealWindows: {
          'breakfast':
              MealWindowConfig(start: r.breakfastStart, end: r.breakfastEnd),
          'lunch': MealWindowConfig(start: r.lunchStart, end: r.lunchEnd),
          'brunch': MealWindowConfig(start: r.brunchStart, end: r.brunchEnd),
        },
        localTimezone: r.localTimezone,
        upiId: r.upiId,
        upiPayeeName: r.upiPayeeName,
        unitPrices: UnitPrices(
            lunch: r.lunchPrice,
            breakfast: r.breakfastPrice,
            brunch: r.brunchPrice),
        appName: r.appName,
        prepLeadMinutes: r.prepLeadMinutes,
        purchaseLeadDays: r.purchaseLeadDays,
        enforceAppearance: r.enforceAppearance,
        appearanceTheme: r.appearanceTheme,
        appearanceMode: r.appearanceMode,
        appearanceMotion: r.appearanceMotion,
      );

  /// What a device needs before anyone has a session: the branding name and,
  /// if the host enforces one, the appearance to render. Fetching it pre-login
  /// is what stops the theme snapping the moment someone signs in.
  Future<Map<String, dynamic>> readPublicAppearance() async =>
      (await read()).toAppearanceJson();

  /// The one field the login screen needs before anyone has a session —
  /// deliberately just this (PRD §6.8, matching v1's `GET /settings/branding`).
  Future<String> readAppName() async {
    final row = await (_db.select(_db.appSettings)
          ..where((s) => s.id.equals(0)))
        .getSingle();
    return row.appName;
  }

  /// Every IANA zone the bundled tz database knows — backs the Settings
  /// timezone dropdown so a value it accepts is the only value pickable
  /// (PRD §6.8, no freehand text).
  List<String> availableTimezones() =>
      tz.timeZoneDatabase.locations.keys.toList()..sort();

  /// Applies a partial update. Only non-null fields in [patch] are written.
  /// Meal windows merge (send just `lunch` without breakfast/brunch); each
  /// window's start must be before its end. A bad timezone or HH:MM is
  /// rejected here so it can never reach the scan path (the highest-stakes
  /// flow) and crash it — same guard as v1's field validators.
  Future<SettingsSnapshot> update(SettingsPatch patch) async {
    final companion = AppSettingsCompanion(
      graceAllowanceEnabled: _val(patch.graceAllowanceEnabled),
      graceAllowanceUnits:
          _valNonNeg(patch.graceAllowanceUnits, 'grace allowance units'),
      reversalWindowMinutes:
          _valNonNeg(patch.reversalWindowMinutes, 'reversal window minutes'),
      localTimezone: _validatedTz(patch.localTimezone),
      upiId: _val(patch.upiId),
      upiPayeeName: _val(patch.upiPayeeName),
      appName: patch.appName == null
          ? const Value.absent()
          : Value(_nonEmpty(patch.appName!, 'app name')),
      prepLeadMinutes: _valNonNeg(patch.prepLeadMinutes, 'prep lead minutes'),
      purchaseLeadDays:
          _valNonNeg(patch.purchaseLeadDays, 'purchase lead days'),
      lunchPrice: _valPrice(patch.unitPrices?.lunch),
      breakfastPrice: _valPrice(patch.unitPrices?.breakfast),
      brunchPrice: _valPrice(patch.unitPrices?.brunch),
      breakfastStart: _windowStart(patch, 'breakfast'),
      breakfastEnd: _windowEnd(patch, 'breakfast'),
      lunchStart: _windowStart(patch, 'lunch'),
      lunchEnd: _windowEnd(patch, 'lunch'),
      brunchStart: _windowStart(patch, 'brunch'),
      brunchEnd: _windowEnd(patch, 'brunch'),
      enforceAppearance: _val(patch.enforceAppearance),
      appearanceTheme: _val(patch.appearanceTheme),
      appearanceMode: _val(patch.appearanceMode),
      appearanceMotion: _val(patch.appearanceMotion),
    );

    if (patch.mealWindows != null) {
      patch.mealWindows!.forEach((meal, w) {
        _requireHhMm(w.start, '$meal start');
        _requireHhMm(w.end, '$meal end');
        if (w.start.compareTo(w.end) >= 0) {
          throw ValidationException(
              '$meal window start (${w.start}) must be before end (${w.end}).');
        }
      });
    }

    await (_db.update(_db.appSettings)..where((s) => s.id.equals(0)))
        .write(companion);
    _log.info('updated fields=${patch.changedFields}');
    return read();
  }

  // ---- validation helpers ---------------------------------------------

  Value<T> _val<T>(T? v) => v == null ? const Value.absent() : Value(v);

  Value<int> _valNonNeg(int? v, String label) {
    if (v == null) return const Value.absent();
    if (v < 0) throw ValidationException('$label cannot be negative.');
    return Value(v);
  }

  Value<double> _valPrice(double? v) {
    if (v == null) return const Value.absent();
    if (v < 0) {
      throw const ValidationException('Unit price cannot be negative.');
    }
    return Value(v);
  }

  Value<String> _validatedTz(String? name) {
    if (name == null) return const Value.absent();
    try {
      tz.getLocation(name);
    } catch (_) {
      throw ValidationException(
          "'$name' is not a valid IANA timezone name (e.g. 'Asia/Kolkata', 'UTC').");
    }
    return Value(name);
  }

  Value<String> _windowStart(SettingsPatch p, String meal) =>
      p.mealWindows?[meal] == null
          ? const Value.absent()
          : Value(p.mealWindows![meal]!.start);
  Value<String> _windowEnd(SettingsPatch p, String meal) =>
      p.mealWindows?[meal] == null
          ? const Value.absent()
          : Value(p.mealWindows![meal]!.end);

  void _requireHhMm(String v, String label) {
    if (!_hhmm.hasMatch(v)) {
      throw ValidationException('$label must be HH:MM in 24-hour form.');
    }
  }

  String _nonEmpty(String v, String label) {
    if (v.trim().isEmpty) throw ValidationException('$label cannot be blank.');
    return v;
  }
}

/// A partial settings update (PRD §6.8). Every field optional.
class SettingsPatch {
  const SettingsPatch({
    this.graceAllowanceEnabled,
    this.graceAllowanceUnits,
    this.reversalWindowMinutes,
    this.mealWindows,
    this.localTimezone,
    this.upiId,
    this.upiPayeeName,
    this.unitPrices,
    this.appName,
    this.prepLeadMinutes,
    this.purchaseLeadDays,
    this.enforceAppearance,
    this.appearanceTheme,
    this.appearanceMode,
    this.appearanceMotion,
  });

  factory SettingsPatch.fromJson(Map<String, dynamic> j) => SettingsPatch(
        graceAllowanceEnabled: j['graceAllowanceEnabled'] as bool?,
        graceAllowanceUnits: (j['graceAllowanceUnits'] as num?)?.toInt(),
        reversalWindowMinutes: (j['reversalWindowMinutes'] as num?)?.toInt(),
        mealWindows: (j['mealWindows'] as Map<String, dynamic>?)?.map(
          (k, v) =>
              MapEntry(k, MealWindowConfig.fromJson(v as Map<String, dynamic>)),
        ),
        localTimezone: j['localTimezone'] as String?,
        upiId: j['upiId'] as String?,
        upiPayeeName: j['upiPayeeName'] as String?,
        unitPrices: j['unitPrices'] == null
            ? null
            : UnitPrices.fromJson(j['unitPrices'] as Map<String, dynamic>),
        appName: j['appName'] as String?,
        prepLeadMinutes: (j['prepLeadMinutes'] as num?)?.toInt(),
        purchaseLeadDays: (j['purchaseLeadDays'] as num?)?.toInt(),
        enforceAppearance: j['enforceAppearance'] as bool?,
        appearanceTheme: j['appearanceTheme'] as String?,
        appearanceMode: j['appearanceMode'] as String?,
        appearanceMotion: j['appearanceMotion'] as bool?,
      );

  final bool? graceAllowanceEnabled;
  final int? graceAllowanceUnits;
  final int? reversalWindowMinutes;
  final Map<String, MealWindowConfig>? mealWindows;
  final String? localTimezone;
  final String? upiId;
  final String? upiPayeeName;
  final UnitPrices? unitPrices;
  final String? appName;
  final int? prepLeadMinutes;
  final int? purchaseLeadDays;
  final bool? enforceAppearance;
  final String? appearanceTheme;
  final String? appearanceMode;
  final bool? appearanceMotion;

  /// Wire form for the client → host PATCH. Only set fields are included, so
  /// the host's partial-update semantics are preserved.
  Map<String, dynamic> toJson() => {
        if (graceAllowanceEnabled != null)
          'graceAllowanceEnabled': graceAllowanceEnabled,
        if (graceAllowanceUnits != null)
          'graceAllowanceUnits': graceAllowanceUnits,
        if (reversalWindowMinutes != null)
          'reversalWindowMinutes': reversalWindowMinutes,
        if (mealWindows != null)
          'mealWindows': mealWindows!.map((k, v) => MapEntry(k, v.toJson())),
        if (localTimezone != null) 'localTimezone': localTimezone,
        if (upiId != null) 'upiId': upiId,
        if (upiPayeeName != null) 'upiPayeeName': upiPayeeName,
        if (unitPrices != null) 'unitPrices': unitPrices!.toJson(),
        if (appName != null) 'appName': appName,
        if (prepLeadMinutes != null) 'prepLeadMinutes': prepLeadMinutes,
        if (purchaseLeadDays != null) 'purchaseLeadDays': purchaseLeadDays,
        if (enforceAppearance != null) 'enforceAppearance': enforceAppearance,
        if (appearanceTheme != null) 'appearanceTheme': appearanceTheme,
        if (appearanceMode != null) 'appearanceMode': appearanceMode,
        if (appearanceMotion != null) 'appearanceMotion': appearanceMotion,
      };

  List<String> get changedFields => {
        if (graceAllowanceEnabled != null) 'graceAllowanceEnabled',
        if (graceAllowanceUnits != null) 'graceAllowanceUnits',
        if (reversalWindowMinutes != null) 'reversalWindowMinutes',
        if (mealWindows != null) 'mealWindows',
        if (localTimezone != null) 'localTimezone',
        if (upiId != null) 'upiId',
        if (upiPayeeName != null) 'upiPayeeName',
        if (unitPrices != null) 'unitPrices',
        if (appName != null) 'appName',
        if (prepLeadMinutes != null) 'prepLeadMinutes',
        if (purchaseLeadDays != null) 'purchaseLeadDays',
        if (enforceAppearance != null) 'enforceAppearance',
        if (appearanceTheme != null) 'appearanceTheme',
        if (appearanceMode != null) 'appearanceMode',
        if (appearanceMotion != null) 'appearanceMotion',
      }.toList();
}
