import 'package:canteen_coupon/core/app_mode.dart';
import 'package:canteen_coupon/core/time/meal_window.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Regression tests for the port of v1 `app/utils/meal_window.py` — the
/// Saturday rule and the day-scoped lock are decision branches (CLAUDE.md §6).
void main() {
  setUpAll(tzdata.initializeTimeZones);

  final windows = {
    'breakfast': const MealWindow(start: HhMm(7, 0), end: HhMm(9, 30)),
    'lunch': const MealWindow(start: HhMm(12, 0), end: HhMm(14, 30)),
    'brunch': const MealWindow(start: HhMm(9, 0), end: HhMm(12, 0)),
  };

  tz.TZDateTime at(int year, int month, int day, int hour, int minute) =>
      tz.TZDateTime(
          tz.getLocation('Asia/Kolkata'), year, month, day, hour, minute);

  group('currentMealType', () {
    test('resolves breakfast inside its window on a weekday', () {
      // 2026-09-03 is a Thursday.
      expect(
          currentMealType(at(2026, 9, 3, 8, 0), windows), MealType.breakfast);
    });

    test('is null between windows', () {
      expect(currentMealType(at(2026, 9, 3, 10, 30), windows), isNull);
    });

    test('resolves lunch at the exact end boundary (inclusive)', () {
      expect(currentMealType(at(2026, 9, 3, 14, 30), windows), MealType.lunch);
    });

    test('on Saturday only brunch applies, never breakfast/lunch', () {
      // 2026-09-05 is a Saturday.
      expect(currentMealType(at(2026, 9, 5, 8, 0), windows),
          isNull); // would be breakfast on a weekday
      expect(currentMealType(at(2026, 9, 5, 10, 0), windows), MealType.brunch);
      expect(currentMealType(at(2026, 9, 5, 13, 0), windows),
          isNull); // would be lunch on a weekday
    });
  });

  group('dayBounds', () {
    test('spans midnight to 23:59:59.999 of the same local date', () {
      final b = dayBounds(at(2026, 9, 3, 14, 30));
      expect(b.start, at(2026, 9, 3, 0, 0));
      expect(b.end.hour, 23);
      expect(b.end.minute, 59);
      expect(b.end.day, 3);
    });
  });
}
