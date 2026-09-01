from datetime import datetime, time


def _parse_hhmm(s: str) -> time:
    hour, minute = s.split(":")
    return time(int(hour), int(minute))


def is_saturday(dt: datetime) -> bool:
    return dt.weekday() == 5  # Monday=0 ... Saturday=5


def current_meal_type(dt: datetime, meal_windows: dict) -> str | None:
    """Return 'breakfast' | 'lunch' | 'brunch' | None based on the current time.

    `meal_windows` comes from the settings document, e.g.:
      {"breakfast": {"start": "07:00", "end": "09:30"}, "lunch": {...}, "brunch": {...}}

    On Saturdays, breakfast and lunch don't apply — only brunch does.
    """
    t = dt.time()

    if is_saturday(dt):
        brunch = meal_windows.get("brunch")
        if brunch and _parse_hhmm(brunch["start"]) <= t <= _parse_hhmm(brunch["end"]):
            return "brunch"
        return None

    for meal_type in ("breakfast", "lunch"):
        window = meal_windows.get(meal_type)
        if window and _parse_hhmm(window["start"]) <= t <= _parse_hhmm(window["end"]):
            return meal_type
    return None


def meal_window_bounds(meal_type: str, dt: datetime, meal_windows: dict) -> tuple[datetime, datetime]:
    """Return (start, end) datetimes for the given meal's window on dt's date.
    Used to check whether a member has already been scanned in *this* window,
    which is what actually enforces the one-scan-per-meal lock."""
    window = meal_windows[meal_type]
    start_t = _parse_hhmm(window["start"])
    end_t = _parse_hhmm(window["end"])
    start = dt.replace(hour=start_t.hour, minute=start_t.minute, second=0, microsecond=0)
    end = dt.replace(hour=end_t.hour, minute=end_t.minute, second=59, microsecond=999999)
    return start, end
