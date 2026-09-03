import '../core/app_mode.dart';

/// Plain domain models — no drift, no HTTP, no Flutter. Shared by every layer
/// so host mode and client mode speak the same types. (§13.7 lists interfaces
/// per domain; the models they carry live here.)

/// Units per meal type — the shape of a balance, a top-up, or a refund line.
class UnitCounts {
  const UnitCounts({this.lunch = 0, this.breakfast = 0, this.brunch = 0});

  factory UnitCounts.fromJson(Map<String, dynamic> j) => UnitCounts(
        lunch: (j['lunch'] as num?)?.toInt() ?? 0,
        breakfast: (j['breakfast'] as num?)?.toInt() ?? 0,
        brunch: (j['brunch'] as num?)?.toInt() ?? 0,
      );

  final int lunch;
  final int breakfast;
  final int brunch;

  int forMeal(MealType m) => switch (m) {
        MealType.lunch => lunch,
        MealType.breakfast => breakfast,
        MealType.brunch => brunch,
      };

  bool get isAllZero => lunch == 0 && breakfast == 0 && brunch == 0;

  Map<String, dynamic> toJson() =>
      {'lunch': lunch, 'breakfast': breakfast, 'brunch': brunch};
}

class Member {
  const Member({
    required this.id,
    required this.type,
    required this.name,
    this.className,
    this.rollNumber,
    this.staffId,
    required this.qrCodeId,
    required this.balances,
    this.graceAllowanceOverride,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: j['id'] as int,
        type: j['type'] as String,
        name: j['name'] as String,
        className: j['className'] as String?,
        rollNumber: j['rollNumber'] as String?,
        staffId: j['staffId'] as String?,
        qrCodeId: j['qrCodeId'] as String,
        balances: UnitCounts.fromJson(j['balances'] as Map<String, dynamic>),
        graceAllowanceOverride: j['graceAllowanceOverride'] as int?,
        status: j['status'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );

  final int id;
  final String type; // 'student' | 'staff'
  final String name;
  final String? className;
  final String? rollNumber;
  final String? staffId;
  final String qrCodeId;
  final UnitCounts balances;
  final int? graceAllowanceOverride;
  final String status; // 'active' | 'inactive'
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == 'active';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'className': className,
        'rollNumber': rollNumber,
        'staffId': staffId,
        'qrCodeId': qrCodeId,
        'balances': balances.toJson(),
        'graceAllowanceOverride': graceAllowanceOverride,
        'status': status,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}

/// Fields accepted when creating a member (PRD §6.1).
class MemberDraft {
  const MemberDraft({
    required this.type,
    required this.name,
    this.className,
    this.rollNumber,
    this.staffId,
    this.balances = const UnitCounts(),
    this.graceAllowanceOverride,
  });

  factory MemberDraft.fromJson(Map<String, dynamic> j) => MemberDraft(
        type: j['type'] as String,
        name: j['name'] as String,
        className: j['className'] as String?,
        rollNumber: j['rollNumber'] as String?,
        staffId: j['staffId'] as String?,
        balances: j['balances'] == null
            ? const UnitCounts()
            : UnitCounts.fromJson(j['balances'] as Map<String, dynamic>),
        graceAllowanceOverride: j['graceAllowanceOverride'] as int?,
      );

  final String type;
  final String name;
  final String? className;
  final String? rollNumber;
  final String? staffId;
  final UnitCounts balances;
  final int? graceAllowanceOverride;

  Map<String, dynamic> toJson() => {
        'type': type,
        'name': name,
        'className': className,
        'rollNumber': rollNumber,
        'staffId': staffId,
        'balances': balances.toJson(),
        'graceAllowanceOverride': graceAllowanceOverride,
      };
}

/// A partial update (PRD §6.1). `null` on an entry means "leave unchanged";
/// `graceAllowanceOverride` uses [Sentinel] so it can be explicitly set to null.
class MemberPatch {
  const MemberPatch({
    this.name,
    this.className,
    this.rollNumber,
    this.staffId,
    this.status,
    this.graceAllowanceOverride = const _Unset(),
  });

  final String? name;
  final String? className;
  final String? rollNumber;
  final String? staffId;
  final String? status;
  final Object? graceAllowanceOverride; // int? value, or _Unset

  bool get touchesGrace => graceAllowanceOverride is! _Unset;
  int? get graceValue => graceAllowanceOverride as int?;
}

class _Unset {
  const _Unset();
}
