import 'package:timezone/timezone.dart' as tz;

import '../app_mode.dart';

/// Meal-window and day-of-week resolution — a direct port of the v1
/// `app/utils/meal_window.py`, kept as pure, testable functions with no I/O
/// (CLAUDE.md §5). Business rules from PRD §5.
///
/// Timestamps are stored UTC everywhere. Meal windows and "today" are meant in
/// the canteen's own local wall-clock time — an admin typing "07:00" means 7am
/// at the canteen — so callers must convert `now` with [toLocal] before asking
/// [currentMealType] or [dayBounds] anything.

/// A single configured serving window, e.g. breakfast 07:00–09:30.
class MealWindow {
  const MealWindow({required this.start, required this.end});

  factory MealWindow.parse(Map<String, dynamic> json) => MealWindow(
        start: _HhMm.parse(json['start'] as String),
        end: _HhMm.parse(json['end'] as String),
      );

  final _HhMm start;
  final _HhMm end;

  bool contains(DateTime local) {
    final t = _HhMm(local.hour, local.minute);
    return !t.isBefore(start) && !t.isAfter(end);
  }
}

class _HhMm {
  const _HhMm(this.hour, this.minute);

  factory _HhMm.parse(String s) {
    final parts = s.split(':');
    return _HhMm(int.parse(parts[0]), int.parse(parts[1]));
  }

  final int hour;
  final int minute;

  int get _asMinutes => hour * 60 + minute;
  bool isBefore(_HhMm other) => _asMinutes < other._asMinutes;
  bool isAfter(_HhMm other) => _asMinutes > other._asMinutes;
}

/// Convert an aware UTC [dt] to the canteen's configured [tzName] (IANA).
/// Throws [tz.LocationNotFoundException] for an unknown zone — callers validate
/// the setting before it can ever reach here.
tz.TZDateTime toLocal(DateTime dt, String tzName) =>
    tz.TZDateTime.from(dt.toUtc(), tz.getLocation(tzName));

bool isSaturday(DateTime local) => local.weekday == DateTime.saturday;

/// The meal currently being served for [local], or null if nothing is.
///
/// On Saturdays only brunch applies; on other days only breakfast and lunch.
/// [windows] is keyed by [MealType.wire].
MealType? currentMealType(DateTime local, Map<String, MealWindow> windows) {
  if (isSaturday(local)) {
    final brunch = windows[MealType.brunch.wire];
    return (brunch != null && brunch.contains(local)) ? MealType.brunch : null;
  }
  for (final meal in const [MealType.breakfast, MealType.lunch]) {
    final w = windows[meal.wire];
    if (w != null && w.contains(local)) return meal;
  }
  return null;
}

/// (startOfDay, endOfDay) spanning [local]'s calendar date, in [local]'s zone.
///
/// Deliberately day-based, not tied to a meal's clock window: a scan accepted
/// via a counter operator's meal-type override can legitimately fall outside
/// normal hours, and the one-scan-per-meal lock must still catch a second scan
/// for the same meal that day (see PRD §5, and the v1 docstring this ports).
({DateTime start, DateTime end}) dayBounds(tz.TZDateTime local) {
  final loc = local.location;
  return (
    start: tz.TZDateTime(loc, local.year, local.month, local.day),
    end: tz.TZDateTime(
        loc, local.year, local.month, local.day, 23, 59, 59, 999),
  );
}
