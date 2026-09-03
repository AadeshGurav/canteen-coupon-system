import 'package:drift/drift.dart';

import '../core/app_mode.dart';
import '../core/errors.dart';
import '../core/logging.dart';
import '../core/time/meal_window.dart';
import '../data/local/database.dart';
import '../data/local/mappers.dart';
import '../domain/ledger.dart';
import 'settings_service.dart';

/// The counter scan flow — a faithful port of v1 `app/services/scan_service.py`
/// including rejection order and messages (PRD §5, §6.4). Runs on the host
/// only; the client reaches it over the JSON API.
class ScanService {
  ScanService(this._db, this._settings);

  final AppDatabase _db;
  final SettingsService _settings;
  final _log = log('scan');

  /// Resolve a code, decide accept/reject, and on accept deduct one unit and
  /// log the scan. Rejections are logged, not stored (matches v1).
  Future<ScanResult> processScan(
    String qrCodeId, {
    MealType? mealTypeOverride,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final settings = await _settings.read();
    final nowLocal = toLocal(nowUtc, settings.localTimezone);

    final member = await (_db.select(_db.members)
          ..where((m) => m.qrCodeId.equals(qrCodeId)))
        .getSingleOrNull();

    if (member == null) {
      _log.warning('rejected reason=unknown_code qr=$qrCodeId');
      return const ScanResult(
        outcome: ScanOutcome.rejectedUnknownCode,
        message: 'No member found for this code.',
      );
    }

    if (member.status != 'active') {
      _log.info('rejected reason=inactive member_id=${member.id}');
      return ScanResult(
        outcome: ScanOutcome.rejectedInactive,
        memberName: member.name,
        memberType: member.type,
        message: "This member's account is inactive.",
      );
    }

    final windows = settings.mealWindows.map(
      (k, v) => MapEntry(k, MealWindow.parse(v.toJson())),
    );
    final mealType = mealTypeOverride ?? currentMealType(nowLocal, windows);
    if (mealType == null) {
      _log.info('rejected reason=no_meal_window member_id=${member.id}');
      return ScanResult(
        outcome: ScanOutcome.rejectedNoMealWindow,
        memberName: member.name,
        memberType: member.type,
        message: 'No meal is currently being served.',
      );
    }

    // One-scan-per-meal lock — day-scoped (see dayBounds' docstring).
    final bounds = dayBounds(nowLocal);
    final existing = await (_db.select(_db.scans)
          ..where((s) =>
              s.memberId.equals(member.id) &
              s.mealType.equals(mealType.wire) &
              s.reversed.equals(false) &
              s.scannedAt
                  .isBetweenValues(bounds.start.toUtc(), bounds.end.toUtc())))
        .getSingleOrNull();
    if (existing != null) {
      _log.info(
          'rejected reason=already_scanned member_id=${member.id} meal=${mealType.wire}');
      return ScanResult(
        outcome: ScanOutcome.rejectedAlreadyScanned,
        memberName: member.name,
        memberType: member.type,
        mealType: mealType,
        message: '${member.name} has already collected ${mealType.wire} today.',
      );
    }

    final balance = _balanceFor(member, mealType);
    final grace = settings.effectiveGrace(member.graceAllowanceOverride);
    final minAllowed = -grace;

    if (balance <= minAllowed) {
      _log.info(
          'rejected reason=zero_balance member_id=${member.id} meal=${mealType.wire} balance=$balance');
      return ScanResult(
        outcome: ScanOutcome.rejectedZeroBalance,
        memberName: member.name,
        memberType: member.type,
        mealType: mealType,
        remainingBalance: balance,
        message: '${member.name} has no ${mealType.wire} units left.',
      );
    }

    final newBalance = balance - 1;
    final usedGrace = newBalance < 0;

    final scanId = await _db.transaction(() async {
      await (_db.update(_db.members)..where((m) => m.id.equals(member.id)))
          .write(_balanceCompanion(mealType, newBalance, nowUtc));
      return _db.into(_db.scans).insert(ScansCompanion.insert(
            memberId: member.id,
            mealType: mealType.wire,
            scannedAt: nowUtc,
            viaGrace: Value(usedGrace),
          ));
    });

    _log.info(
        'accepted member_id=${member.id} meal=${mealType.wire} new_balance=$newBalance via_grace=$usedGrace');

    final graceNote = usedGrace ? ' (on grace allowance)' : '';
    return ScanResult(
      outcome: ScanOutcome.accepted,
      scanId: scanId,
      memberName: member.name,
      memberType: member.type,
      mealType: mealType,
      remainingBalance: newBalance,
      viaGrace: usedGrace,
      message:
          'Confirmed — ${member.name} (${mealType.wire})$graceNote. $newBalance left.',
    );
  }

  /// Undo a mistaken accepted scan within the configured window (PRD §5). The
  /// scan row is flagged reversed, never deleted (audit trail).
  Future<ReversalResult> reverseScan(int scanId, String reversedBy) async {
    final scan = await (_db.select(_db.scans)
          ..where((s) => s.id.equals(scanId)))
        .getSingleOrNull();
    if (scan == null) {
      return const ReversalResult(success: false, message: 'Scan not found.');
    }
    if (scan.reversed) {
      return const ReversalResult(
          success: false, message: 'Scan already reversed.');
    }
    if (scan.result != 'accepted') {
      return const ReversalResult(
          success: false, message: 'Only accepted scans can be reversed.');
    }

    final settings = await _settings.read();
    final window = Duration(minutes: settings.reversalWindowMinutes);
    if (DateTime.now().toUtc().difference(scan.scannedAt) > window) {
      return ReversalResult(
        success: false,
        message:
            'Reversal window of ${settings.reversalWindowMinutes} minutes has expired.',
      );
    }

    final member = await (_db.select(_db.members)
          ..where((m) => m.id.equals(scan.memberId)))
        .getSingleOrNull();
    if (member == null) {
      return const ReversalResult(success: false, message: 'Member not found.');
    }

    final meal = MealType.fromWire(scan.mealType);
    final restored = _balanceFor(member, meal) + 1;
    final now = DateTime.now().toUtc();

    await _db.transaction(() async {
      await (_db.update(_db.members)..where((m) => m.id.equals(member.id)))
          .write(_balanceCompanion(meal, restored, now));
      await (_db.update(_db.scans)..where((s) => s.id.equals(scan.id))).write(
        ScansCompanion(
          reversed: const Value(true),
          reversedAt: Value(now),
          reversedBy: Value(reversedBy),
        ),
      );
    });

    _log.info(
        'reversed scan_id=$scanId member_id=${member.id} meal=${meal.wire} restored=$restored by=$reversedBy');
    return ReversalResult(
      success: true,
      message: 'Scan reversed, $restored ${meal.wire} units restored.',
    );
  }

  /// Recent scans, newest first — backs the admin scan log and reversal picker.
  Future<List<ScanRecord>> recentScans({int? memberId, int limit = 200}) async {
    final query = _db.select(_db.scans).join([
      innerJoin(_db.members, _db.members.id.equalsExp(_db.scans.memberId)),
    ])
      ..orderBy([OrderingTerm.desc(_db.scans.scannedAt)])
      ..limit(limit.clamp(1, 1000));
    if (memberId != null) {
      query.where(_db.scans.memberId.equals(memberId));
    }
    final rows = await query.get();
    return rows
        .map((r) =>
            scanFromRow(r.readTable(_db.scans), r.readTable(_db.members).name))
        .toList();
  }

  // ---- helpers --------------------------------------------------------

  int _balanceFor(Member m, MealType meal) => switch (meal) {
        MealType.lunch => m.lunchBalance,
        MealType.breakfast => m.breakfastBalance,
        MealType.brunch => m.brunchBalance,
      };

  MembersCompanion _balanceCompanion(MealType meal, int value, DateTime now) =>
      switch (meal) {
        MealType.lunch =>
          MembersCompanion(lunchBalance: Value(value), updatedAt: Value(now)),
        MealType.breakfast => MembersCompanion(
            breakfastBalance: Value(value), updatedAt: Value(now)),
        MealType.brunch =>
          MembersCompanion(brunchBalance: Value(value), updatedAt: Value(now)),
      };
}

/// Only thrown for a genuinely malformed request the router couldn't catch.
class ScanRequestException extends ValidationException {
  const ScanRequestException(super.message);
}
