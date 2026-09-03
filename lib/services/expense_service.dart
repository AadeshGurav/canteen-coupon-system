import 'package:drift/drift.dart';

import '../core/errors.dart';
import '../core/logging.dart';
import '../data/local/database.dart' hide Expense;
import '../data/local/mappers.dart';
import '../domain/ops.dart';

/// Expense logging + a revenue-vs-expense summary — a port of v1
/// `app/routers/expenses.py` (PRD §6.6). Revenue = confirmed top-ups in range.
class ExpenseService {
  ExpenseService(this._db);

  final AppDatabase _db;
  final _log = log('expense');

  Future<Expense> add(ExpenseDraft draft) async {
    if (draft.amount < 0) {
      throw const ValidationException('Amount cannot be negative.');
    }
    final id = await _db.into(_db.expenses).insert(ExpensesCompanion.insert(
          category: draft.category,
          description: draft.description,
          amount: draft.amount,
          date: _dateOnly(draft.date),
          createdBy: draft.createdBy,
        ));
    _log.info('logged category=${draft.category} '
        'amount=${draft.amount.toStringAsFixed(2)} by=${draft.createdBy}');
    final row = await (_db.select(_db.expenses)..where((e) => e.id.equals(id)))
        .getSingle();
    return expenseFromRow(row);
  }

  Future<List<Expense>> list({DateTime? start, DateTime? end}) async {
    final query = _db.select(_db.expenses)
      ..orderBy([(e) => OrderingTerm.asc(e.date)]);
    if (start != null) {
      query.where((e) => e.date.isBiggerOrEqualValue(_dateOnly(start)));
    }
    if (end != null) {
      query.where((e) => e.date.isSmallerOrEqualValue(_dateOnly(end)));
    }
    return (await query.get()).map(expenseFromRow).toList();
  }

  Future<ProfitSummary> summary({DateTime? start, DateTime? end}) async {
    final topupQuery = _db.select(_db.topups)
      ..where((t) => t.paymentStatus.equals('confirmed'));
    final expenseQuery = _db.select(_db.expenses);
    if (start != null) {
      topupQuery.where((t) => t.createdAt.isBiggerOrEqualValue(start.toUtc()));
      expenseQuery.where((e) => e.date.isBiggerOrEqualValue(_dateOnly(start)));
    }
    if (end != null) {
      topupQuery.where((t) => t.createdAt.isSmallerOrEqualValue(end.toUtc()));
      expenseQuery.where((e) => e.date.isSmallerOrEqualValue(_dateOnly(end)));
    }

    final revenue =
        (await topupQuery.get()).fold<double>(0, (sum, t) => sum + t.amount);
    final spend =
        (await expenseQuery.get()).fold<double>(0, (sum, e) => sum + e.amount);

    return ProfitSummary(
        revenue: revenue, expenses: spend, profit: revenue - spend);
  }

  DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);
}
