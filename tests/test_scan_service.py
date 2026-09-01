from datetime import datetime, timedelta

import pytest

from app.services import scan_service
from tests.fakes import FakeCollection

MEAL_WINDOWS = {
    "breakfast": {"start": "07:00", "end": "09:30"},
    "lunch": {"start": "12:00", "end": "14:30"},
    "brunch": {"start": "09:00", "end": "12:00"},
}


def make_settings(**overrides) -> dict:
    settings = {
        "grace_allowance_enabled": False,
        "grace_allowance_units": 0,
        "reversal_window_minutes": 10,
        "meal_windows": MEAL_WINDOWS,
    }
    settings.update(overrides)
    return settings


@pytest.fixture
def fake_db(monkeypatch):
    members = FakeCollection()
    scans = FakeCollection()
    monkeypatch.setattr(scan_service, "member_entities", members)
    monkeypatch.setattr(scan_service, "scans", scans)
    return members, scans


def use_settings(monkeypatch, **overrides) -> dict:
    settings = make_settings(**overrides)

    async def fake_get_global_settings():
        return settings

    monkeypatch.setattr(scan_service, "get_global_settings", fake_get_global_settings)
    return settings


async def create_member(members: FakeCollection, **overrides) -> dict:
    doc = {
        "qr_code_id": "abc123",
        "type": "student",
        "name": "Test Kid",
        "status": "active",
        "balances": {"lunch": 1, "breakfast": 1, "brunch": 1},
        "grace_allowance_override": None,
    }
    doc.update(overrides)
    result = await members.insert_one(doc)
    doc["_id"] = result.inserted_id
    return doc


@pytest.mark.asyncio
async def test_unknown_qr_code_is_rejected(fake_db, monkeypatch):
    use_settings(monkeypatch)
    result = await scan_service.process_scan("does-not-exist")
    assert result.result == "rejected_unknown_code"


@pytest.mark.asyncio
async def test_inactive_member_is_rejected(fake_db, monkeypatch):
    members, _ = fake_db
    use_settings(monkeypatch)
    await create_member(members, status="inactive")
    result = await scan_service.process_scan("abc123", meal_type_override="lunch")
    assert result.result == "rejected_inactive"


@pytest.mark.asyncio
async def test_no_meal_currently_served_is_rejected(fake_db, monkeypatch):
    members, _ = fake_db
    use_settings(monkeypatch)
    monkeypatch.setattr(scan_service, "current_meal_type", lambda *a, **k: None)
    await create_member(members)
    result = await scan_service.process_scan("abc123")
    assert result.result == "rejected_unknown_code"
    assert "No meal" in result.message


@pytest.mark.asyncio
async def test_accepted_scan_deducts_one_unit(fake_db, monkeypatch):
    members, _ = fake_db
    use_settings(monkeypatch)
    await create_member(members, balances={"lunch": 2, "breakfast": 0, "brunch": 0})

    result = await scan_service.process_scan("abc123", meal_type_override="lunch")

    assert result.result == "accepted"
    assert result.remaining_balance == 1
    assert result.via_grace is False

    updated = await members.find_one({"qr_code_id": "abc123"})
    assert updated["balances"]["lunch"] == 1


@pytest.mark.asyncio
async def test_already_scanned_lock_holds_even_with_an_out_of_window_override(fake_db, monkeypatch):
    """Regression test: meal_type_override lets a counter operator force a
    meal type outside its configured clock window (see ScanRequest). The
    one-scan-per-meal lock must still catch a second scan in that case —
    it previously keyed off the meal's configured window bounds instead of
    the calendar day, so an overridden scan's real timestamp could fall
    outside the range the lock searched, silently letting a member be
    scanned twice for the same meal."""
    members, _ = fake_db
    use_settings(monkeypatch)  # lunch window is 12:00-14:30; test runs whenever it runs
    await create_member(members, balances={"lunch": 5, "breakfast": 0, "brunch": 0})

    first = await scan_service.process_scan("abc123", meal_type_override="lunch")
    second = await scan_service.process_scan("abc123", meal_type_override="lunch")

    assert first.result == "accepted"
    assert second.result == "rejected_already_scanned"


@pytest.mark.asyncio
async def test_zero_balance_without_grace_is_rejected(fake_db, monkeypatch):
    members, _ = fake_db
    use_settings(monkeypatch)
    await create_member(members, balances={"lunch": 0, "breakfast": 0, "brunch": 0})

    result = await scan_service.process_scan("abc123", meal_type_override="lunch")
    assert result.result == "rejected_zero_balance"


@pytest.mark.asyncio
async def test_grace_allowance_permits_going_to_the_floor(fake_db, monkeypatch):
    members, _ = fake_db
    use_settings(monkeypatch, grace_allowance_enabled=True, grace_allowance_units=1)
    await create_member(members, balances={"lunch": 0, "breakfast": 0, "brunch": 0})

    result = await scan_service.process_scan("abc123", meal_type_override="lunch")
    assert result.result == "accepted"
    assert result.remaining_balance == -1
    assert result.via_grace is True


@pytest.mark.asyncio
async def test_grace_allowance_blocks_past_the_floor(fake_db, monkeypatch):
    members, _ = fake_db
    use_settings(monkeypatch, grace_allowance_enabled=True, grace_allowance_units=1)
    # Balance is already sitting at the floor for a grace of 1 unit.
    await create_member(members, balances={"lunch": -1, "breakfast": 0, "brunch": 0})

    result = await scan_service.process_scan("abc123", meal_type_override="lunch")
    assert result.result == "rejected_zero_balance"


@pytest.mark.asyncio
async def test_per_member_grace_override_takes_precedence_over_global(fake_db, monkeypatch):
    members, _ = fake_db
    # Global grace disabled, but this member has a personal override of 2.
    use_settings(monkeypatch, grace_allowance_enabled=False, grace_allowance_units=0)
    await create_member(
        members, balances={"lunch": 0, "breakfast": 0, "brunch": 0}, grace_allowance_override=2
    )

    result = await scan_service.process_scan("abc123", meal_type_override="lunch")
    assert result.result == "accepted"
    assert result.remaining_balance == -1


@pytest.mark.asyncio
async def test_reversal_restores_balance_and_marks_scan_reversed(fake_db, monkeypatch):
    members, scans = fake_db
    use_settings(monkeypatch)
    await create_member(members, balances={"lunch": 5, "breakfast": 0, "brunch": 0})

    await scan_service.process_scan("abc123", meal_type_override="lunch")
    scan_doc = await scans.find_one(
        {"member_id": str((await members.find_one({"qr_code_id": "abc123"}))["_id"])}
    )

    result = await scan_service.reverse_scan(str(scan_doc["_id"]), reversed_by="tester")

    assert result["success"] is True
    updated_member = await members.find_one({"qr_code_id": "abc123"})
    assert updated_member["balances"]["lunch"] == 5

    reversed_scan = await scans.find_one({"_id": scan_doc["_id"]})
    assert reversed_scan["reversed"] is True
    assert reversed_scan["reversed_by"] == "tester"


@pytest.mark.asyncio
async def test_cannot_reverse_the_same_scan_twice(fake_db, monkeypatch):
    members, scans = fake_db
    use_settings(monkeypatch)
    await create_member(members, balances={"lunch": 5, "breakfast": 0, "brunch": 0})
    await scan_service.process_scan("abc123", meal_type_override="lunch")
    scan_doc = await scans.find_one({})

    first = await scan_service.reverse_scan(str(scan_doc["_id"]), reversed_by="tester")
    second = await scan_service.reverse_scan(str(scan_doc["_id"]), reversed_by="tester")

    assert first["success"] is True
    assert second["success"] is False


@pytest.mark.asyncio
async def test_reversal_fails_outside_the_configured_window(fake_db, monkeypatch):
    members, scans = fake_db
    use_settings(monkeypatch, reversal_window_minutes=10)
    await create_member(members, balances={"lunch": 5, "breakfast": 0, "brunch": 0})
    await scan_service.process_scan("abc123", meal_type_override="lunch")

    scan_doc = await scans.find_one({})
    # find_one returns a shallow copy — mutate the fake collection's stored
    # doc directly so the backdated timestamp actually takes effect.
    scans._docs[scan_doc["_id"]]["scanned_at"] = datetime.utcnow() - timedelta(minutes=11)

    result = await scan_service.reverse_scan(str(scan_doc["_id"]), reversed_by="tester")
    assert result["success"] is False
    assert "expired" in result["message"]


@pytest.mark.asyncio
async def test_reversal_with_invalid_scan_id_fails_cleanly(fake_db, monkeypatch):
    use_settings(monkeypatch)
    result = await scan_service.reverse_scan("not-a-valid-object-id", reversed_by="tester")
    assert result["success"] is False
    assert "Invalid" in result["message"]


@pytest.mark.asyncio
async def test_reversal_of_nonexistent_scan_fails_cleanly(fake_db, monkeypatch):
    use_settings(monkeypatch)
    from bson import ObjectId

    result = await scan_service.reverse_scan(str(ObjectId()), reversed_by="tester")
    assert result["success"] is False
    assert result["message"] == "Scan not found."
