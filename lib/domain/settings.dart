/// The global settings, as a plain immutable snapshot (PRD §6.8). The drift
/// `AppSettings` row is the storage; this is what services and the API pass
/// around. Nested v1 maps (`meal_windows`, `unit_prices`) are modelled as
/// small value types here.
library;

class MealWindowConfig {
  const MealWindowConfig({required this.start, required this.end});

  factory MealWindowConfig.fromJson(Map<String, dynamic> j) =>
      MealWindowConfig(start: j['start'] as String, end: j['end'] as String);

  final String start; // "HH:MM", 24h
  final String end;

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

class UnitPrices {
  const UnitPrices(
      {required this.lunch, required this.breakfast, required this.brunch});

  factory UnitPrices.fromJson(Map<String, dynamic> j) => UnitPrices(
        lunch: (j['lunch'] as num).toDouble(),
        breakfast: (j['breakfast'] as num).toDouble(),
        brunch: (j['brunch'] as num).toDouble(),
      );

  final double lunch;
  final double breakfast;
  final double brunch;

  Map<String, dynamic> toJson() =>
      {'lunch': lunch, 'breakfast': breakfast, 'brunch': brunch};
}

class SettingsSnapshot {
  factory SettingsSnapshot.fromJson(Map<String, dynamic> j) => SettingsSnapshot(
        graceAllowanceEnabled: j['graceAllowanceEnabled'] as bool,
        graceAllowanceUnits: (j['graceAllowanceUnits'] as num).toInt(),
        reversalWindowMinutes: (j['reversalWindowMinutes'] as num).toInt(),
        mealWindows: (j['mealWindows'] as Map<String, dynamic>).map(
          (k, v) =>
              MapEntry(k, MealWindowConfig.fromJson(v as Map<String, dynamic>)),
        ),
        localTimezone: j['localTimezone'] as String,
        upiId: j['upiId'] as String,
        upiPayeeName: j['upiPayeeName'] as String,
        unitPrices:
            UnitPrices.fromJson(j['unitPrices'] as Map<String, dynamic>),
        appName: j['appName'] as String,
        prepLeadMinutes: (j['prepLeadMinutes'] as num).toInt(),
        purchaseLeadDays: (j['purchaseLeadDays'] as num).toInt(),
        enforceAppearance: j['enforceAppearance'] as bool? ?? false,
        appearanceTheme: j['appearanceTheme'] as String? ?? 'neobrutal',
        appearanceMode: j['appearanceMode'] as String? ?? 'system',
        appearanceMotion: j['appearanceMotion'] as bool? ?? true,
      );

  const SettingsSnapshot({
    required this.graceAllowanceEnabled,
    required this.graceAllowanceUnits,
    required this.reversalWindowMinutes,
    required this.mealWindows,
    required this.localTimezone,
    required this.upiId,
    required this.upiPayeeName,
    required this.unitPrices,
    required this.appName,
    required this.prepLeadMinutes,
    required this.purchaseLeadDays,
    this.enforceAppearance = false,
    this.appearanceTheme = 'neobrutal',
    this.appearanceMode = 'system',
    this.appearanceMotion = true,
  });

  final bool graceAllowanceEnabled;
  final int graceAllowanceUnits;
  final int reversalWindowMinutes;

  /// Keyed by meal type wire name: 'breakfast' | 'lunch' | 'brunch'.
  final Map<String, MealWindowConfig> mealWindows;

  final String localTimezone;
  final String upiId;
  final String upiPayeeName;
  final UnitPrices unitPrices;
  final String appName;
  final int prepLeadMinutes;
  final int purchaseLeadDays;

  /// When true, every device on this host renders the appearance below rather
  /// than its own (CLAUDE.md §11.5). Wire names, not enums, because this
  /// crosses the HTTP boundary — an unknown value degrades to the default
  /// theme rather than failing a client's launch.
  final bool enforceAppearance;
  final String appearanceTheme;
  final String appearanceMode;
  final bool appearanceMotion;

  /// Effective grace units for a member, given an optional per-member override
  /// (PRD §5). Null override → the global default when enabled, else 0.
  int effectiveGrace(int? memberOverride) {
    if (memberOverride != null) return memberOverride;
    return graceAllowanceEnabled ? graceAllowanceUnits : 0;
  }

  Map<String, dynamic> toJson() => {
        'graceAllowanceEnabled': graceAllowanceEnabled,
        'graceAllowanceUnits': graceAllowanceUnits,
        'reversalWindowMinutes': reversalWindowMinutes,
        'mealWindows': mealWindows.map((k, v) => MapEntry(k, v.toJson())),
        'localTimezone': localTimezone,
        'upiId': upiId,
        'upiPayeeName': upiPayeeName,
        'unitPrices': unitPrices.toJson(),
        'appName': appName,
        'prepLeadMinutes': prepLeadMinutes,
        'purchaseLeadDays': purchaseLeadDays,
        'enforceAppearance': enforceAppearance,
        'appearanceTheme': appearanceTheme,
        'appearanceMode': appearanceMode,
        'appearanceMotion': appearanceMotion,
      };

  /// The subset a device needs before anyone signs in, so the theme is right
  /// on the login screen rather than snapping after authentication.
  Map<String, dynamic> toAppearanceJson() => {
        'appName': appName,
        'enforceAppearance': enforceAppearance,
        'theme': appearanceTheme,
        'mode': appearanceMode,
        'motion': appearanceMotion,
      };
}
