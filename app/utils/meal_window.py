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


def day_bounds(dt: datetime) -> tuple[datetime, datetime]:
    """Return (start, end) datetimes spanning dt's calendar date.

    Used to check whether a member has already been scanned for a given meal
    *today*, which is what enforces the one-scan-per-meal lock. Deliberately
    day-based rather than tied to the meal's configured clock window: a scan
    accepted via `meal_type_override` (see ScanRequest) can legitimately fall
    outside that window's normal hours, and the lock must still catch a
    second scan for the same meal — using the meal window's own bounds here
    would let an overridden scan's real timestamp fall outside the range it's
    searched against, silently defeating the lock.
    """
    start = dt.replace(hour=0, minute=0, second=0, microsecond=0)
    end = dt.replace(hour=23, minute=59, second=59, microsecond=999999)
    return start, end
