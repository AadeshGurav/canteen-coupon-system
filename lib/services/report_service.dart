import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/logging.dart';
import '../data/local/database.dart';
import 'expense_service.dart';
import 'settings_service.dart';
import 'xlsx_writer.dart';

/// Builds the admin's `.xlsx` report.
///
/// Export only, on purpose: a spreadsheet loses types, ids and referential
/// integrity, so reading one back would be a route to corrupt balances. Moving
/// data between phones is the backup file's job — this one is for people to
/// read, print and pivot.
class ReportService {
  ReportService(this._db, this._settings, this._expenses);

  final AppDatabase _db;
  final SettingsService _settings;
  final ExpenseService _expenses;
  final _log = log('report');

  /// [start]/[end] are inclusive local dates; null means "everything".
  Future<List<int>> build({
    DateTime? start,
    DateTime? end,
    Set<ReportSection> sections = ReportSection.all,
  }) async {
    final settings = await _settings.read();
    final zone = _zoneOf(settings.localTimezone);
    final members = await _db.select(_db.members).get();
    final nameById = {for (final m in members) m.id: m.name};

    // Dates are formatted in the canteen's own timezone, not UTC and not the
    // exporting phone's — the report has to agree with the meal windows the
    // scans were judged against (CLAUDE.md §13).
    String at(DateTime utc) => DateFormat('yyyy-MM-dd HH:mm')
        .format(tz.TZDateTime.from(utc.toUtc(), zone));
    String day(DateTime utc) =>
        DateFormat('yyyy-MM-dd').format(tz.TZDateTime.from(utc.toUtc(), zone));

    bool inRange(DateTime when) =>
        (start == null || !when.isBefore(start)) &&
        (end == null || !when.isAfter(end));

    final sheets = <Sheet>[];

    if (sections.contains(ReportSection.summary)) {
      final profit = await _expenses.summary(start: start, end: end);
      final sheet = Sheet('Summary', headers: ['Figure', 'Value']);
      sheet
        ..add(['Generated', at(DateTime.now().toUtc())])
        ..add(['Timezone', settings.localTimezone])
        ..add(['Range from', start == null ? 'the beginning' : day(start)])
        ..add(['Range to', end == null ? 'today' : day(end)])
        ..add(['Members', members.length])
        ..add(['Revenue (confirmed top-ups)', profit.revenue])
        ..add(['Expenses', profit.expenses])
        ..add(['Profit', profit.profit]);
      sheets.add(sheet);
    }

    if (sections.contains(ReportSection.members)) {
      final sheet = Sheet('Members', headers: [
        'ID',
        'Type',
        'Name',
        'Class',
        'Roll no',
        'Staff ID',
        'QR code',
        'Status',
        'Added',
      ]);
      for (final m in members) {
        sheet.add([
          m.id,
          m.type,
          m.name,
          m.className,
          m.rollNumber,
          m.staffId,
          m.qrCodeId,
          m.status,
          day(m.createdAt),
        ]);
      }
      sheets.add(sheet);
    }

    if (sections.contains(ReportSection.balances)) {
      final sheet = Sheet('Balances', headers: [
        'ID',
        'Name',
        'Lunch',
        'Breakfast',
        'Brunch',
        'Total',
        'Status',
      ]);
      for (final m in members) {
        sheet.add([
          m.id,
          m.name,
          m.lunchBalance,
          m.breakfastBalance,
          m.brunchBalance,
          m.lunchBalance + m.breakfastBalance + m.brunchBalance,
          m.status,
        ]);
      }
      sheets.add(sheet);
    }

    if (sections.contains(ReportSection.scans)) {
      final scans = await (_db.select(_db.scans)
            ..orderBy([(s) => OrderingTerm.desc(s.scannedAt)]))
          .get();
      final sheet = Sheet('Scans', headers: [
        'When',
        'Member',
        'Meal',
        'On grace',
        'Reversed',
        'Reversed by',
      ]);
      for (final s in scans.where((s) => inRange(s.scannedAt))) {
        sheet.add([
          at(s.scannedAt),
          nameById[s.memberId] ?? 'member ${s.memberId}',
          s.mealType,
          s.viaGrace ? 'yes' : 'no',
          s.reversed ? 'yes' : 'no',
          s.reversedBy,
        ]);
      }
      sheets.add(sheet);
    }

    if (sections.contains(ReportSection.topups)) {
      final topups = await (_db.select(_db.topups)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();
      final sheet = Sheet('Top-ups', headers: [
        'When',
        'Member',
        'Lunch',
        'Breakfast',
        'Brunch',
        'Amount',
        'Method',
        'Status',
        'By',
      ]);
      for (final t in topups.where((t) => inRange(t.createdAt))) {
        sheet.add([
          at(t.createdAt),
          nameById[t.memberId] ?? 'member ${t.memberId}',
          t.lunchUnits,
          t.breakfastUnits,
          t.brunchUnits,
          t.amount,
          t.paymentMethod,
          t.paymentStatus,
          t.createdBy,
        ]);
      }
      sheets.add(sheet);
    }

    if (sections.contains(ReportSection.refunds)) {
      final refunds = await (_db.select(_db.refunds)
            ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
          .get();
      final sheet = Sheet('Refunds', headers: [
        'When',
        'Member',
        'Lunch',
        'Breakfast',
        'Brunch',
        'Amount',
        'Reason',
        'By',
      ]);
      for (final r in refunds.where((r) => inRange(r.createdAt))) {
        sheet.add([
          at(r.createdAt),
          nameById[r.memberId] ?? 'member ${r.memberId}',
          r.lunchUnits,
          r.breakfastUnits,
          r.brunchUnits,
          r.refundAmount,
          r.reason,
          r.processedBy,
        ]);
      }
      sheets.add(sheet);
    }

    if (sections.contains(ReportSection.expenses)) {
      final expenses = await (_db.select(_db.expenses)
            ..orderBy([(e) => OrderingTerm.desc(e.date)]))
          .get();
      final sheet = Sheet('Expenses',
          headers: ['Date', 'Category', 'Description', 'Amount', 'By']);
      for (final e in expenses.where((e) => inRange(e.date))) {
        sheet.add(
            [day(e.date), e.category, e.description, e.amount, e.createdBy]);
      }
      sheets.add(sheet);
    }

    if (sections.contains(ReportSection.menu)) {
      final entries = await (_db.select(_db.menuEntries)
            ..orderBy([(m) => OrderingTerm.desc(m.date)]))
          .get();
      final sheet =
          Sheet('Menu', headers: ['Date', 'Meal', 'Categories', 'Items', 'By']);
      for (final e in entries.where((e) => inRange(e.date))) {
        sheet.add([
          day(e.date),
          e.mealType,
          _joinJsonList(e.categoriesJson),
          _joinJsonList(e.itemsJson),
          e.createdBy,
        ]);
      }
      sheets.add(sheet);
    }

    // A workbook with no tabs is a file Excel refuses to open, so an
    // all-deselected export becomes an honest summary rather than a bad file.
    if (sheets.isEmpty) {
      sheets.add(Sheet('Summary', headers: ['Figure', 'Value'])
        ..add(['Generated', at(DateTime.now().toUtc())])
        ..add(['Note', 'No sections were selected.']));
    }

    _log.info('report_built sheets=${sheets.length}');
    return const XlsxWriter().build(sheets);
  }

  /// Suggested filename, dated so successive exports don't overwrite.
  String fileName({DateTime? now}) =>
      'tiffin-report-${DateFormat('yyyy-MM-dd').format(now ?? DateTime.now())}'
      '.xlsx';

  tz.Location _zoneOf(String name) {
    try {
      return tz.getLocation(name);
    } catch (_) {
      // A report is not worth failing over a bad zone; UTC and carry on.
      _log.warning('unknown timezone "$name", formatting in UTC');
      return tz.UTC;
    }
  }

  static String _joinJsonList(String json) {
    final trimmed = json.trim();
    if (trimmed.length < 2) return '';
    return trimmed
        .substring(1, trimmed.length - 1)
        .split(',')
        .map((s) => s.trim().replaceAll('"', ''))
        .where((s) => s.isNotEmpty)
        .join(', ');
  }
}

/// The tabs an export can include.
enum ReportSection {
  summary,
  members,
  balances,
  scans,
  topups,
  refunds,
  expenses,
  menu;

  static const all = <ReportSection>{
    ReportSection.summary,
    ReportSection.members,
    ReportSection.balances,
    ReportSection.scans,
    ReportSection.topups,
    ReportSection.refunds,
    ReportSection.expenses,
    ReportSection.menu,
  };

  String get label => switch (this) {
        ReportSection.summary => 'Summary',
        ReportSection.members => 'Members',
        ReportSection.balances => 'Balances',
        ReportSection.scans => 'Scans',
        ReportSection.topups => 'Top-ups',
        ReportSection.refunds => 'Refunds',
        ReportSection.expenses => 'Expenses',
        ReportSection.menu => 'Menu',
      };
}
