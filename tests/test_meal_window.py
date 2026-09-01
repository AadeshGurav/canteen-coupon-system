from datetime import datetime, timedelta, timezone

from app.utils.meal_window import current_meal_type, day_bounds, is_saturday, to_local

MEAL_WINDOWS = {
    "breakfast": {"start": "07:00", "end": "09:30"},
    "lunch": {"start": "12:00", "end": "14:30"},
    "brunch": {"start": "09:00", "end": "12:00"},
}


def _dt(*args) -> datetime:
    """Every real datetime this code ever sees is UTC-aware (see the tz_aware
    note in app/core/database.py) — build test fixtures the same way."""
    return datetime(*args, tzinfo=timezone.utc)


def test_is_saturday_matches_only_saturday():
    monday = _dt(2026, 9, 7)  # a Monday
    saturday = _dt(2026, 9, 5)  # the preceding Saturday
    assert is_saturday(saturday) is True
    assert is_saturday(monday) is False


def test_weekday_within_breakfast_window():
    dt = _dt(2026, 9, 7, 8, 0)  # Monday 08:00
    assert current_meal_type(dt, MEAL_WINDOWS) == "breakfast"


def test_weekday_within_lunch_window():
    dt = _dt(2026, 9, 7, 13, 0)  # Monday 13:00
    assert current_meal_type(dt, MEAL_WINDOWS) == "lunch"


def test_weekday_outside_any_window_is_none():
    dt = _dt(2026, 9, 7, 16, 0)  # Monday 16:00, nothing being served
    assert current_meal_type(dt, MEAL_WINDOWS) is None


def test_weekday_never_resolves_to_brunch():
    dt = _dt(2026, 9, 7, 10, 0)  # Monday 10:00, inside the brunch *time* window
    assert current_meal_type(dt, MEAL_WINDOWS) is None


def test_saturday_within_brunch_window():
    dt = _dt(2026, 9, 5, 10, 0)  # Saturday 10:00
    assert current_meal_type(dt, MEAL_WINDOWS) == "brunch"


def test_saturday_never_resolves_to_breakfast_or_lunch():
    dt = _dt(2026, 9, 5, 8, 0)  # Saturday 08:00, inside the weekday breakfast window
    assert current_meal_type(dt, MEAL_WINDOWS) is None


def test_day_bounds_span_the_full_calendar_date():
    dt = _dt(2026, 9, 7, 13, 15, 30)
    start, end = day_bounds(dt)
    assert start == _dt(2026, 9, 7, 0, 0, 0, 0)
    assert end == _dt(2026, 9, 7, 23, 59, 59, 999999)


class TestToLocal:
    """Regression coverage for a real bug: meal windows like "07:00" are the
    canteen's local wall-clock hours, not UTC — comparing them against raw
    UTC "now" silently breaks scan acceptance (and the Saturday-brunch
    day-of-week check) for any non-UTC deployment, e.g. India (UTC+5:30,
    the timezone this PRD's UPI-based billing implies)."""

    def test_converts_utc_to_the_configured_zone(self):
        utc_dt = _dt(2026, 9, 5, 2, 30)  # 02:30 UTC
        local_dt = to_local(utc_dt, "Asia/Kolkata")  # UTC+5:30
        assert local_dt.hour == 8
        assert local_dt.minute == 0

    def test_utc_late_evening_can_already_be_the_next_local_day(self):
        # 19:00 UTC on a Friday is 00:30 the *next* day (Saturday) in IST —
        # this is exactly the boundary where comparing against raw UTC time
        # would apply weekday breakfast/lunch windows instead of the
        # Saturday-only brunch rule, or vice versa.
        utc_friday_evening = _dt(2026, 9, 4, 19, 0)
        local = to_local(utc_friday_evening, "Asia/Kolkata")
        assert local.strftime("%A") == "Saturday"
        assert utc_friday_evening.strftime("%A") == "Friday"

    def test_meal_type_resolution_uses_local_time_not_utc(self):
        # 02:30 UTC is outside every configured window taken at face value,
        # but is 08:00 IST — squarely inside the breakfast window. A caller
        # that forgot to convert to local time first would get None here.
        utc_dt = _dt(2026, 9, 7, 2, 30)  # Monday 02:30 UTC = Monday 08:00 IST
        local_dt = to_local(utc_dt, "Asia/Kolkata")
        assert current_meal_type(local_dt, MEAL_WINDOWS) == "breakfast"

    def test_utc_passthrough_when_timezone_is_utc(self):
        utc_dt = _dt(2026, 9, 7, 8, 0)
        assert to_local(utc_dt, "UTC") == utc_dt

    def test_day_bounds_in_local_time_differ_from_utc_near_midnight(self):
        # Just after local midnight in IST is still the previous UTC day —
        # day_bounds() must be computed on local time so "today" means the
        # canteen's today, not UTC's.
        utc_dt = _dt(2026, 9, 4, 19, 30)  # Friday 19:30 UTC = Saturday 01:00 IST
        local_dt = to_local(utc_dt, "Asia/Kolkata")
        start, end = day_bounds(local_dt)
        assert start.strftime("%A %Y-%m-%d") == "Saturday 2026-09-05"
        assert end - start == timedelta(hours=23, minutes=59, seconds=59, microseconds=999999)
