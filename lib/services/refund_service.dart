import 'package:drift/drift.dart';

import '../core/errors.dart';
import '../core/logging.dart';
import '../data/local/database.dart' hide Refund;
import '../data/local/mappers.dart';
import '../domain/ledger.dart';
import 'settings_service.dart';

/// Refunds — a port of v1 `app/routers/refunds.py`. Keeps the unit ledger
/// accurate and records what/when/why; the actual payout happens outside the
/// app (PRD §6.7). Amount is computed from configured prices, never typed in.
class RefundService {
  RefundService(this._db, this._settings);

  final AppDatabase _db;
  final SettingsService _settings;
  final _log = log('refund');

  Future<List<Refund>> list({int? memberId}) async {
    final query = _db.select(_db.refunds)
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
    if (memberId != null) query.where((r) => r.memberId.equals(memberId));
    return (await query.get()).map(refundFromRow).toList();
  }

  Future<Refund> create(RefundDraft draft) async {
    if (draft.isAllZero) {
      throw const ValidationException('A refund needs at least one unit.');
    }
    final member = await (_db.select(_db.members)
          ..where((m) => m.id.equals(draft.memberId)))
        .getSingleOrNull();
    if (member == null) throw const NotFoundException('Member not found.');

    _rejectOverRefund('lunch', draft.lunchUnits, member.lunchBalance);
    _rejectOverRefund(
        'breakfast', draft.breakfastUnits, member.breakfastBalance);
    _rejectOverRefund('brunch', draft.brunchUnits, member.brunchBalance);

    final prices = (await _settings.read()).unitPrices;
    final amount = draft.lunchUnits * prices.lunch +
        draft.breakfastUnits * prices.breakfast +
        draft.brunchUnits * prices.brunch;

    final now = DateTime.now().toUtc();
    final id = await _db.transaction(() async {
      await (_db.update(_db.members)..where((m) => m.id.equals(member.id)))
          .write(
        MembersCompanion(
          lunchBalance: Value(member.lunchBalance - draft.lunchUnits),
          breakfastBalance:
              Value(member.breakfastBalance - draft.breakfastUnits),
          brunchBalance: Value(member.brunchBalance - draft.brunchUnits),
          updatedAt: Value(now),
        ),
      );
      return _db.into(_db.refunds).insert(RefundsCompanion.insert(
            memberId: draft.memberId,
            lunchUnits: Value(draft.lunchUnits),
            breakfastUnits: Value(draft.breakfastUnits),
            brunchUnits: Value(draft.brunchUnits),
            refundAmount: amount,
            reason: Value(draft.reason),
            processedBy: draft.processedBy,
            createdAt: now,
          ));
    });

    _log.info('created member_id=${draft.memberId} refund_id=$id '
        'amount=${amount.toStringAsFixed(2)} by=${draft.processedBy}');
    final row = await (_db.select(_db.refunds)..where((r) => r.id.equals(id)))
        .getSingle();
    return refundFromRow(row);
  }

  void _rejectOverRefund(String meal, int requested, int available) {
    if (requested > available) {
      throw ValidationException(
        'Cannot refund $requested $meal units — member only has $available.',
      );
    }
  }
}
