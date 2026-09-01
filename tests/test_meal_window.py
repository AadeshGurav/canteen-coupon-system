from datetime import datetime

from app.utils.meal_window import current_meal_type, day_bounds, is_saturday

MEAL_WINDOWS = {
    "breakfast": {"start": "07:00", "end": "09:30"},
    "lunch": {"start": "12:00", "end": "14:30"},
    "brunch": {"start": "09:00", "end": "12:00"},
}


def test_is_saturday_matches_only_saturday():
    monday = datetime(2026, 9, 7)  # a Monday
    saturday = datetime(2026, 9, 5)  # the preceding Saturday
    assert is_saturday(saturday) is True
    assert is_saturday(monday) is False


def test_weekday_within_breakfast_window():
    dt = datetime(2026, 9, 7, 8, 0)  # Monday 08:00
    assert current_meal_type(dt, MEAL_WINDOWS) == "breakfast"


def test_weekday_within_lunch_window():
    dt = datetime(2026, 9, 7, 13, 0)  # Monday 13:00
    assert current_meal_type(dt, MEAL_WINDOWS) == "lunch"


def test_weekday_outside_any_window_is_none():
    dt = datetime(2026, 9, 7, 16, 0)  # Monday 16:00, nothing being served
    assert current_meal_type(dt, MEAL_WINDOWS) is None


def test_weekday_never_resolves_to_brunch():
    dt = datetime(2026, 9, 7, 10, 0)  # Monday 10:00, inside the brunch *time* window
    assert current_meal_type(dt, MEAL_WINDOWS) is None


def test_saturday_within_brunch_window():
    dt = datetime(2026, 9, 5, 10, 0)  # Saturday 10:00
    assert current_meal_type(dt, MEAL_WINDOWS) == "brunch"


def test_saturday_never_resolves_to_breakfast_or_lunch():
    dt = datetime(2026, 9, 5, 8, 0)  # Saturday 08:00, inside the weekday breakfast window
    assert current_meal_type(dt, MEAL_WINDOWS) is None


def test_day_bounds_span_the_full_calendar_date():
    dt = datetime(2026, 9, 7, 13, 15, 30)
    start, end = day_bounds(dt)
    assert start == datetime(2026, 9, 7, 0, 0, 0, 0)
    assert end == datetime(2026, 9, 7, 23, 59, 59, 999999)
