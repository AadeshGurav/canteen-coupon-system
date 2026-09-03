import '../core/app_mode.dart';

/// Scan, top-up and refund models — the unit ledger (PRD §5–§6). Plain,
/// JSON-serializable, shared by host and client.

// ---------------------------------------------------------------------------
// Scan
// ---------------------------------------------------------------------------

/// The outcome the counter operator acts on immediately (PRD §6.4). Mirrors
/// v1's `ScanResult` including the exact `rejected_*` discriminators.
enum ScanOutcome {
  accepted,
  rejectedUnknownCode,
  rejectedInactive,
  rejectedNoMealWindow,
  rejectedAlreadyScanned,
  rejectedZeroBalance;

  static ScanOutcome fromWire(String v) => ScanOutcome.values.firstWhere(
        (o) => o.wire == v,
        orElse: () => throw ArgumentError('Unknown scan outcome: $v'),
      );

  String get wire => switch (this) {
        ScanOutcome.accepted => 'accepted',
        ScanOutcome.rejectedUnknownCode => 'rejected_unknown_code',
        ScanOutcome.rejectedInactive => 'rejected_inactive',
        ScanOutcome.rejectedNoMealWindow => 'rejected_no_meal_window',
        ScanOutcome.rejectedAlreadyScanned => 'rejected_already_scanned',
        ScanOutcome.rejectedZeroBalance => 'rejected_zero_balance',
      };

  bool get isAccepted => this == ScanOutcome.accepted;
}

class ScanResult {
  const ScanResult({
    required this.outcome,
    this.scanId,
    this.memberName,
    this.memberType,
    this.mealType,
    this.remainingBalance,
    this.viaGrace = false,
    required this.message,
  });

  factory ScanResult.fromJson(Map<String, dynamic> j) => ScanResult(
        outcome: ScanOutcome.fromWire(j['outcome'] as String),
        scanId: j['scanId'] as int?,
        memberName: j['memberName'] as String?,
        memberType: j['memberType'] as String?,
        mealType: j['mealType'] == null
            ? null
            : MealType.fromWire(j['mealType'] as String),
        remainingBalance: j['remainingBalance'] as int?,
        viaGrace: j['viaGrace'] as bool? ?? false,
        message: j['message'] as String,
      );

  final ScanOutcome outcome;
  final int? scanId;
  final String? memberName;
  final String? memberType;
  final MealType? mealType;
  final int? remainingBalance;
  final bool viaGrace;
  final String message;

  Map<String, dynamic> toJson() => {
        'outcome': outcome.wire,
        'scanId': scanId,
        'memberName': memberName,
        'memberType': memberType,
        'mealType': mealType?.wire,
        'remainingBalance': remainingBalance,
        'viaGrace': viaGrace,
        'message': message,
      };
}

/// A stored scan row (PRD §8) — backs the admin scan log and reversal.
class ScanRecord {
  const ScanRecord({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.mealType,
    required this.scannedAt,
    required this.result,
    required this.viaGrace,
    required this.reversed,
    this.reversedAt,
    this.reversedBy,
  });

  factory ScanRecord.fromJson(Map<String, dynamic> j) => ScanRecord(
        id: j['id'] as int,
        memberId: j['memberId'] as int,
        memberName: j['memberName'] as String,
        mealType: MealType.fromWire(j['mealType'] as String),
        scannedAt: DateTime.parse(j['scannedAt'] as String),
        result: j['result'] as String,
        viaGrace: j['viaGrace'] as bool,
        reversed: j['reversed'] as bool,
        reversedAt: j['reversedAt'] == null
            ? null
            : DateTime.parse(j['reversedAt'] as String),
        reversedBy: j['reversedBy'] as String?,
      );

  final int id;
  final int memberId;
  final String memberName;
  final MealType mealType;
  final DateTime scannedAt;
  final String result;
  final bool viaGrace;
  final bool reversed;
  final DateTime? reversedAt;
  final String? reversedBy;

  Map<String, dynamic> toJson() => {
        'id': id,
        'memberId': memberId,
        'memberName': memberName,
        'mealType': mealType.wire,
        'scannedAt': scannedAt.toUtc().toIso8601String(),
        'result': result,
        'viaGrace': viaGrace,
        'reversed': reversed,
        'reversedAt': reversedAt?.toUtc().toIso8601String(),
        'reversedBy': reversedBy,
      };
}

class ReversalResult {
  const ReversalResult({required this.success, required this.message});

  factory ReversalResult.fromJson(Map<String, dynamic> j) => ReversalResult(
        success: j['success'] as bool,
        message: j['message'] as String,
      );

  final bool success;
  final String message;

  Map<String, dynamic> toJson() => {'success': success, 'message': message};
}

// ---------------------------------------------------------------------------
// Top-up
// ---------------------------------------------------------------------------

enum PaymentMethod {
  cash,
  upi;

  static PaymentMethod fromWire(String v) =>
      PaymentMethod.values.firstWhere((p) => p.name == v,
          orElse: () => throw ArgumentError('Unknown payment method: $v'));
  String get wire => name;
}

/// A top-up request (PRD §6.3). Amount is never in the request — the host
/// computes it from `settings.unitPrices`.
class TopupDraft {
  const TopupDraft({
    required this.memberId,
    this.lunchUnits = 0,
    this.breakfastUnits = 0,
    this.brunchUnits = 0,
    required this.paymentMethod,
    required this.createdBy,
  });

  factory TopupDraft.fromJson(Map<String, dynamic> j) => TopupDraft(
        memberId: j['memberId'] as int,
        lunchUnits: (j['lunchUnits'] as num?)?.toInt() ?? 0,
        breakfastUnits: (j['breakfastUnits'] as num?)?.toInt() ?? 0,
        brunchUnits: (j['brunchUnits'] as num?)?.toInt() ?? 0,
        paymentMethod: PaymentMethod.fromWire(j['paymentMethod'] as String),
        createdBy: j['createdBy'] as String,
      );

  final int memberId;
  final int lunchUnits;
  final int breakfastUnits;
  final int brunchUnits;
  final PaymentMethod paymentMethod;
  final String createdBy;

  bool get isAllZero =>
      lunchUnits == 0 && breakfastUnits == 0 && brunchUnits == 0;

  Map<String, dynamic> toJson() => {
        'memberId': memberId,
        'lunchUnits': lunchUnits,
        'breakfastUnits': breakfastUnits,
        'brunchUnits': brunchUnits,
        'paymentMethod': paymentMethod.wire,
        'createdBy': createdBy,
      };
}

class Topup {
  const Topup({
    required this.id,
    required this.memberId,
    required this.lunchUnits,
    required this.breakfastUnits,
    required this.brunchUnits,
    required this.amount,
    required this.paymentMethod,
    required this.paymentStatus,
    this.hasBill = false,
    this.hasUpiQr = false,
    required this.createdBy,
    required this.createdAt,
  });

  factory Topup.fromJson(Map<String, dynamic> j) => Topup(
        id: j['id'] as int,
        memberId: j['memberId'] as int,
        lunchUnits: j['lunchUnits'] as int,
        breakfastUnits: j['breakfastUnits'] as int,
        brunchUnits: j['brunchUnits'] as int,
        amount: (j['amount'] as num).toDouble(),
        paymentMethod: PaymentMethod.fromWire(j['paymentMethod'] as String),
        paymentStatus: j['paymentStatus'] as String,
        hasBill: j['hasBill'] as bool? ?? false,
        hasUpiQr: j['hasUpiQr'] as bool? ?? false,
        createdBy: j['createdBy'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  final int id;
  final int memberId;
  final int lunchUnits;
  final int breakfastUnits;
  final int brunchUnits;
  final double amount;
  final PaymentMethod paymentMethod;
  final String paymentStatus; // 'pending' | 'confirmed'
  final bool hasBill;
  final bool hasUpiQr;
  final String createdBy;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'memberId': memberId,
        'lunchUnits': lunchUnits,
        'breakfastUnits': breakfastUnits,
        'brunchUnits': brunchUnits,
        'amount': amount,
        'paymentMethod': paymentMethod.wire,
        'paymentStatus': paymentStatus,
        'hasBill': hasBill,
        'hasUpiQr': hasUpiQr,
        'createdBy': createdBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// Refund
// ---------------------------------------------------------------------------

class RefundDraft {
  const RefundDraft({
    required this.memberId,
    this.lunchUnits = 0,
    this.breakfastUnits = 0,
    this.brunchUnits = 0,
    this.reason,
    required this.processedBy,
  });

  factory RefundDraft.fromJson(Map<String, dynamic> j) => RefundDraft(
        memberId: j['memberId'] as int,
        lunchUnits: (j['lunchUnits'] as num?)?.toInt() ?? 0,
        breakfastUnits: (j['breakfastUnits'] as num?)?.toInt() ?? 0,
        brunchUnits: (j['brunchUnits'] as num?)?.toInt() ?? 0,
        reason: j['reason'] as String?,
        processedBy: j['processedBy'] as String,
      );

  final int memberId;
  final int lunchUnits;
  final int breakfastUnits;
  final int brunchUnits;
  final String? reason;
  final String processedBy;

  bool get isAllZero =>
      lunchUnits == 0 && breakfastUnits == 0 && brunchUnits == 0;

  Map<String, dynamic> toJson() => {
        'memberId': memberId,
        'lunchUnits': lunchUnits,
        'breakfastUnits': breakfastUnits,
        'brunchUnits': brunchUnits,
        'reason': reason,
        'processedBy': processedBy,
      };
}

class Refund {
  const Refund({
    required this.id,
    required this.memberId,
    required this.lunchUnits,
    required this.breakfastUnits,
    required this.brunchUnits,
    required this.refundAmount,
    this.reason,
    required this.processedBy,
    required this.createdAt,
  });

  factory Refund.fromJson(Map<String, dynamic> j) => Refund(
        id: j['id'] as int,
        memberId: j['memberId'] as int,
        lunchUnits: j['lunchUnits'] as int,
        breakfastUnits: j['breakfastUnits'] as int,
        brunchUnits: j['brunchUnits'] as int,
        refundAmount: (j['refundAmount'] as num).toDouble(),
        reason: j['reason'] as String?,
        processedBy: j['processedBy'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  final int id;
  final int memberId;
  final int lunchUnits;
  final int breakfastUnits;
  final int brunchUnits;
  final double refundAmount;
  final String? reason;
  final String processedBy;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'memberId': memberId,
        'lunchUnits': lunchUnits,
        'breakfastUnits': breakfastUnits,
        'brunchUnits': brunchUnits,
        'refundAmount': refundAmount,
        'reason': reason,
        'processedBy': processedBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}
