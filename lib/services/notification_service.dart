import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/app_mode.dart';
import '../core/errors.dart';
import '../core/role.dart';
import '../core/time/meal_window.dart';
import '../data/local/database.dart' hide Notification;
import '../data/local/mappers.dart';
import '../domain/ops.dart';
import '../domain/settings.dart';
import 'settings_service.dart';

/// Persistent in-app reminders — a port of v1
/// `app/services/notification_service.py` (PRD §6.5.2). No scheduled job:
/// [generateDue] is called on each `GET /notifications` poll, and the upserts
/// are idempotent so polling never duplicates.
class NotificationService {
  NotificationService(this._db, this._settings);

  final AppDatabase _db;
  final SettingsService _settings;

  Future<void> generateDue(DateTime nowUtc) async {
    final s = await _settings.read();
    final localNow = toLocal(nowUtc, s.localTimezone);
    await _generatePrepReminders(localNow, s);
    await _generatePurchaseReminders(localNow, s);
  }

  Future<void> _generatePrepReminders(
      DateTime localNow, SettingsSnapshot s) async {
    final today = DateTime.utc(localNow.year, localNow.month, localNow.day);
    final meals = isSaturday(localNow)
        ? const [MealType.brunch]
        : const [MealType.breakfast, MealType.lunch];

    for (final meal in meals) {
      final window = s.mealWindows[meal.wire];
      if (window == null) continue;

      final planned = await (_db.select(_db.menuEntries)
                ..where(
                    (e) => e.date.equals(today) & e.mealType.equals(meal.wire))
                ..limit(1))
              .getSingleOrNull() !=
          null;
      if (!planned) continue;

      final parts = window.start.split(':');
      final startLocal = DateTime(
        localNow.year,
        localNow.month,
        localNow.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
      final minutesUntil = startLocal.difference(localNow).inSeconds / 60.0;
      if (minutesUntil < 0 || minutesUntil > s.prepLeadMinutes) continue;

      await _upsert(
        type: 'prep_reminder',
        dateKey: _ymd(today),
        mealType: meal.wire,
        title: 'Start prepping ${meal.wire}',
        message:
            '${_capitalize(meal.wire)} service starts at ${window.start} — '
            'about ${minutesUntil.round()} minute(s) from now.',
        visibleRoles: const [Role.admin, Role.counter],
      );
    }
  }

  Future<void> _generatePurchaseReminders(
      DateTime localNow, SettingsSnapshot s) async {
    final target = DateTime.utc(localNow.year, localNow.month, localNow.day)
        .add(Duration(days: s.purchaseLeadDays));
    final pending = await (_db.select(_db.purchaseScheduleItems)
          ..where((p) => p.date.equals(target) & p.purchased.equals(false)))
        .get();
    if (pending.isEmpty) return;

    await _upsert(
      type: 'purchase_due',
      dateKey: _ymd(target),
      mealType: null,
      title: 'Ingredient purchase due',
      message:
          '${pending.length} item(s) still need buying for ${_ymd(target)}.',
      visibleRoles: const [Role.admin, Role.counter],
    );
  }

  /// Idempotent upsert keyed on (type, dateKey, mealType). Done by hand rather
  /// than a DB unique constraint because SQLite treats NULL mealType values as
  /// distinct, which would let `purchase_due` reminders pile up.
  Future<void> _upsert({
    required String type,
    required String dateKey,
    required String? mealType,
    required String title,
    required String message,
    required List<Role> visibleRoles,
  }) async {
    final now = DateTime.now().toUtc();
    final match = _db.select(_db.notifications)
      ..where((n) => n.type.equals(type) & n.dateKey.equals(dateKey));
    if (mealType == null) {
      match.where((n) => n.mealType.isNull());
    } else {
      match.where((n) => n.mealType.equals(mealType));
    }
    final existing = await match.getSingleOrNull();

    final rolesJson = jsonEncode(visibleRoles.map((r) => r.wire).toList());
    if (existing == null) {
      await _db.into(_db.notifications).insert(NotificationsCompanion.insert(
            type: type,
            dateKey: dateKey,
            mealType: Value(mealType),
            title: title,
            message: message,
            visibleRolesJson: rolesJson,
            createdAt: now,
            updatedAt: now,
          ));
    } else {
      await (_db.update(_db.notifications)
            ..where((n) => n.id.equals(existing.id)))
          .write(NotificationsCompanion(
        title: Value(title),
        message: Value(message),
        visibleRolesJson: Value(rolesJson),
        updatedAt: Value(now),
      ));
    }
  }

  /// Active + undismissed for this user, newest first.
  Future<List<AppNotification>> listFor(Role role, String username) async {
    final rows = await (_db.select(_db.notifications)
          ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
        .get();
    return rows
        .where((n) {
          final roles =
              (jsonDecode(n.visibleRolesJson) as List<dynamic>).cast<String>();
          final dismissed =
              (jsonDecode(n.dismissedByJson) as List<dynamic>).cast<String>();
          return roles.contains(role.wire) && !dismissed.contains(username);
        })
        .map(notificationFromRow)
        .toList();
  }

  Future<void> dismiss(int id, String username) async {
    final row = await (_db.select(_db.notifications)
          ..where((n) => n.id.equals(id)))
        .getSingleOrNull();
    if (row == null) throw const NotFoundException('Notification not found.');
    final dismissed = (jsonDecode(row.dismissedByJson) as List<dynamic>)
        .cast<String>()
        .toSet()
      ..add(username);
    await (_db.update(_db.notifications)..where((n) => n.id.equals(id))).write(
      NotificationsCompanion(
          dismissedByJson: Value(jsonEncode(dismissed.toList()))),
    );
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
