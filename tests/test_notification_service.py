"""Reminder generation — a prep reminder must fire only in the configured
lead window before a meal that's actually planned, and a purchase reminder
must fire only when something's genuinely still unbought. Idempotency is
the other property that matters, since this runs on every poll."""

from datetime import date, datetime, timezone

import pytest

from app.services import notification_service
from tests.fakes import FakeCollection

MEAL_WINDOWS = {
    "breakfast": {"start": "07:00", "end": "09:30"},
    "lunch": {"start": "12:00", "end": "14:30"},
    "brunch": {"start": "09:00", "end": "12:00"},
}


def as_menu_date(d: date) -> datetime:
    """menu_log stores its `date` field as a naive midnight datetime — see
    the same helper's docstring in tests/test_purchase_schedule_service.py."""
    return datetime.combine(d, datetime.min.time())


def make_settings(**overrides) -> dict:
    settings = {
        "local_timezone": "UTC",
        "meal_windows": MEAL_WINDOWS,
        "prep_lead_minutes": 60,
        "purchase_lead_days": 1,
    }
    settings.update(overrides)
    return settings


@pytest.fixture
def fake_db(monkeypatch):
    menu_log = FakeCollection()
    notifications = FakeCollection()
    purchase_schedule_items = FakeCollection()
    monkeypatch.setattr(notification_service, "menu_log", menu_log)
    monkeypatch.setattr(notification_service, "notifications", notifications)
    monkeypatch.setattr(notification_service, "purchase_schedule_items", purchase_schedule_items)
    return menu_log, notifications, purchase_schedule_items


def use_settings(monkeypatch, **overrides) -> dict:
    settings = make_settings(**overrides)

    async def fake_get_global_settings():
        return settings

    monkeypatch.setattr(notification_service, "get_global_settings", fake_get_global_settings)
    return settings


@pytest.mark.asyncio
async def test_no_reminder_without_a_planned_menu(fake_db, monkeypatch):
    use_settings(monkeypatch)
    # 11:15 UTC, 45 minutes before lunch (12:00) — inside the lead window,
    # but nothing is planned for lunch today.
    now = datetime(2026, 9, 1, 11, 15, tzinfo=timezone.utc)

    await notification_service.generate_due_notifications(now)

    _, notifications, _ = fake_db
    assert await notifications.find({}).to_list() == []


@pytest.mark.asyncio
async def test_prep_reminder_fires_inside_the_lead_window(fake_db, monkeypatch):
    use_settings(monkeypatch)
    menu_log, notifications, _ = fake_db
    await menu_log.insert_one(
        {"date": as_menu_date(date(2026, 9, 1)), "meal_type": "lunch", "items": ["Dal"]}
    )
    now = datetime(2026, 9, 1, 11, 15, tzinfo=timezone.utc)  # 45 min before 12:00 lunch

    await notification_service.generate_due_notifications(now)

    docs = await notifications.find({}).to_list()
    assert len(docs) == 1
    assert docs[0]["type"] == "prep_reminder"
    assert docs[0]["meal_type"] == "lunch"


@pytest.mark.asyncio
async def test_prep_reminder_does_not_fire_too_early(fake_db, monkeypatch):
    use_settings(monkeypatch)
    menu_log, notifications, _ = fake_db
    await menu_log.insert_one(
        {"date": as_menu_date(date(2026, 9, 1)), "meal_type": "lunch", "items": ["Dal"]}
    )
    now = datetime(2026, 9, 1, 9, 0, tzinfo=timezone.utc)  # 3 hours before lunch — outside the 60min lead

    await notification_service.generate_due_notifications(now)

    assert await notifications.find({}).to_list() == []


@pytest.mark.asyncio
async def test_prep_reminder_does_not_fire_after_the_meal_starts(fake_db, monkeypatch):
    use_settings(monkeypatch)
    menu_log, notifications, _ = fake_db
    await menu_log.insert_one(
        {"date": as_menu_date(date(2026, 9, 1)), "meal_type": "lunch", "items": ["Dal"]}
    )
    now = datetime(2026, 9, 1, 12, 30, tzinfo=timezone.utc)  # after lunch already started

    await notification_service.generate_due_notifications(now)

    assert await notifications.find({}).to_list() == []


@pytest.mark.asyncio
async def test_saturday_only_reminds_about_brunch(fake_db, monkeypatch):
    use_settings(monkeypatch)
    menu_log, notifications, _ = fake_db
    # 2026-09-05 is a Saturday.
    await menu_log.insert_one(
        {"date": as_menu_date(date(2026, 9, 5)), "meal_type": "brunch", "items": ["Poha"]}
    )
    now = datetime(2026, 9, 5, 8, 30, tzinfo=timezone.utc)  # 30 min before 09:00 brunch

    await notification_service.generate_due_notifications(now)

    docs = await notifications.find({}).to_list()
    assert len(docs) == 1
    assert docs[0]["meal_type"] == "brunch"


@pytest.mark.asyncio
async def test_polling_again_does_not_duplicate_the_same_reminder(fake_db, monkeypatch):
    use_settings(monkeypatch)
    menu_log, notifications, _ = fake_db
    await menu_log.insert_one(
        {"date": as_menu_date(date(2026, 9, 1)), "meal_type": "lunch", "items": ["Dal"]}
    )
    now = datetime(2026, 9, 1, 11, 15, tzinfo=timezone.utc)

    await notification_service.generate_due_notifications(now)
    await notification_service.generate_due_notifications(now)

    assert len(await notifications.find({}).to_list()) == 1


@pytest.mark.asyncio
async def test_purchase_reminder_fires_when_items_are_still_pending(fake_db, monkeypatch):
    use_settings(monkeypatch, purchase_lead_days=1)
    _, notifications, schedule_items = fake_db
    await schedule_items.insert_one(
        {"date": as_menu_date(date(2026, 9, 2)), "ingredient_id": "x", "purchased": False}
    )
    now = datetime(2026, 9, 1, 6, 0, tzinfo=timezone.utc)

    await notification_service.generate_due_notifications(now)

    docs = await notifications.find({"type": "purchase_due"}).to_list()
    assert len(docs) == 1


@pytest.mark.asyncio
async def test_no_purchase_reminder_once_everything_is_purchased(fake_db, monkeypatch):
    use_settings(monkeypatch, purchase_lead_days=1)
    _, notifications, schedule_items = fake_db
    await schedule_items.insert_one(
        {"date": as_menu_date(date(2026, 9, 2)), "ingredient_id": "x", "purchased": True}
    )
    now = datetime(2026, 9, 1, 6, 0, tzinfo=timezone.utc)

    await notification_service.generate_due_notifications(now)

    assert await notifications.find({"type": "purchase_due"}).to_list() == []


@pytest.mark.asyncio
async def test_list_active_for_role_excludes_dismissed_and_other_roles(fake_db):
    _, notifications, _ = fake_db
    await notifications.insert_one(
        {
            "type": "prep_reminder",
            "visible_roles": ["admin", "counter"],
            "dismissed_by": [],
            "created_at": datetime.now(timezone.utc),
        }
    )
    await notifications.insert_one(
        {
            "type": "prep_reminder",
            "visible_roles": ["admin"],
            "dismissed_by": [],
            "created_at": datetime.now(timezone.utc),
        }
    )

    for_counter = await notification_service.list_active_for_role("counter", "counter1")
    assert len(for_counter) == 1

    for_scanner = await notification_service.list_active_for_role("scanner", "scanner1")
    assert len(for_scanner) == 0


@pytest.mark.asyncio
async def test_dismissing_hides_it_only_for_that_user(fake_db):
    _, notifications, _ = fake_db
    result = await notifications.insert_one(
        {
            "type": "prep_reminder",
            "visible_roles": ["admin", "counter"],
            "dismissed_by": [],
            "created_at": datetime.now(timezone.utc),
        }
    )

    dismissed = await notification_service.dismiss_notification(result.inserted_id, "counter1")
    assert dismissed is True

    assert await notification_service.list_active_for_role("counter", "counter1") == []
    assert len(await notification_service.list_active_for_role("counter", "someone_else")) == 1


@pytest.mark.asyncio
async def test_dismissing_an_unknown_notification_returns_false(fake_db):
    from bson import ObjectId

    dismissed = await notification_service.dismiss_notification(ObjectId(), "counter1")
    assert dismissed is False
