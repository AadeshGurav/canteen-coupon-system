"""Deriving a purchase schedule from planned menu entries and their recipes —
idempotent generation is the property that matters most here, since the
admin can (and will) re-run this over an overlapping date range."""

from datetime import date, datetime, timezone

import pytest

from app.services import purchase_schedule_service
from tests.fakes import FakeCollection

SEPT_1 = date(2026, 9, 1)
SEPT_30 = date(2026, 9, 30)


def as_menu_date(d: date) -> datetime:
    """menu_log stores its `date` field as a naive midnight datetime — a
    calendar date, not a timestamp — matching app/routers/menu.py's own
    `datetime.combine(payload.date, datetime.min.time())`."""
    return datetime.combine(d, datetime.min.time())


@pytest.fixture
def fake_db(monkeypatch):
    menu_log = FakeCollection()
    recipes = FakeCollection()
    ingredients = FakeCollection()
    purchase_schedule_items = FakeCollection()
    monkeypatch.setattr(purchase_schedule_service, "menu_log", menu_log)
    monkeypatch.setattr(purchase_schedule_service, "recipes", recipes)
    monkeypatch.setattr(purchase_schedule_service, "ingredients", ingredients)
    monkeypatch.setattr(purchase_schedule_service, "purchase_schedule_items", purchase_schedule_items)
    return menu_log, recipes, ingredients, purchase_schedule_items


async def make_ingredient(ingredients: FakeCollection, name: str, unit: str = "kg") -> str:
    result = await ingredients.insert_one({"name": name, "unit": unit})
    return str(result.inserted_id)


async def make_recipe(recipes: FakeCollection, dish_name: str, ingredient_entries: list[dict]) -> None:
    await recipes.insert_one(
        {
            "dish_name": dish_name,
            "dish_name_lower": dish_name.lower(),
            "ingredients": ingredient_entries,
        }
    )


async def make_menu_entry(menu_log: FakeCollection, entry_date: date, items: list[str]) -> None:
    await menu_log.insert_one({"date": as_menu_date(entry_date), "meal_type": "lunch", "items": items})


@pytest.mark.asyncio
async def test_no_menu_entries_generates_nothing(fake_db):
    created = await purchase_schedule_service.generate_schedule(SEPT_1, SEPT_30)
    assert created == 0


@pytest.mark.asyncio
async def test_menu_entry_without_a_recipe_generates_nothing(fake_db):
    menu_log, _recipes, _ingredients, _items = fake_db
    await make_menu_entry(menu_log, date(2026, 9, 15), ["Some dish with no recipe"])

    created = await purchase_schedule_service.generate_schedule(SEPT_1, SEPT_30)

    assert created == 0


@pytest.mark.asyncio
async def test_menu_entry_with_a_recipe_creates_one_item_per_ingredient(fake_db):
    menu_log, recipes, ingredients, schedule_items = fake_db
    rice_id = await make_ingredient(ingredients, "Rice")
    dal_id = await make_ingredient(ingredients, "Toor dal")
    await make_recipe(
        recipes,
        "Dal Rice",
        [
            {"ingredient_id": rice_id, "quantity_note": "2kg per 50 servings"},
            {"ingredient_id": dal_id, "quantity_note": "1kg per 50 servings"},
        ],
    )
    await make_menu_entry(menu_log, date(2026, 9, 15), ["Dal Rice"])

    created = await purchase_schedule_service.generate_schedule(SEPT_1, SEPT_30)

    assert created == 2
    stored = await schedule_items.find({}).to_list()
    assert {d["ingredient_name"] for d in stored} == {"Rice", "Toor dal"}
    assert all(d["source"] == "auto" and d["purchased"] is False for d in stored)


@pytest.mark.asyncio
async def test_dish_name_lookup_is_case_insensitive(fake_db):
    menu_log, recipes, ingredients, _schedule_items = fake_db
    rice_id = await make_ingredient(ingredients, "Rice")
    await make_recipe(recipes, "Dal Rice", [{"ingredient_id": rice_id, "quantity_note": "2kg"}])
    await make_menu_entry(menu_log, date(2026, 9, 15), ["dal rice"])  # different case

    created = await purchase_schedule_service.generate_schedule(SEPT_1, SEPT_30)

    assert created == 1


@pytest.mark.asyncio
async def test_regenerating_the_same_range_does_not_duplicate(fake_db):
    menu_log, recipes, ingredients, schedule_items = fake_db
    rice_id = await make_ingredient(ingredients, "Rice")
    await make_recipe(recipes, "Rice", [{"ingredient_id": rice_id, "quantity_note": "2kg"}])
    await make_menu_entry(menu_log, date(2026, 9, 15), ["Rice"])

    first = await purchase_schedule_service.generate_schedule(SEPT_1, SEPT_30)
    second = await purchase_schedule_service.generate_schedule(SEPT_1, SEPT_30)

    assert first == 1
    assert second == 0  # already exists — idempotent, not duplicated
    assert len(await schedule_items.find({}).to_list()) == 1


@pytest.mark.asyncio
async def test_regenerating_does_not_reset_a_purchased_item(fake_db):
    menu_log, recipes, ingredients, schedule_items = fake_db
    rice_id = await make_ingredient(ingredients, "Rice")
    await make_recipe(recipes, "Rice", [{"ingredient_id": rice_id, "quantity_note": "2kg"}])
    await make_menu_entry(menu_log, date(2026, 9, 15), ["Rice"])
    await purchase_schedule_service.generate_schedule(SEPT_1, SEPT_30)

    stored = (await schedule_items.find({}).to_list())[0]
    await schedule_items.update_one(
        {"_id": stored["_id"]},
        {"$set": {"purchased": True, "purchased_by": "admin", "purchased_at": datetime.now(timezone.utc)}},
    )

    await purchase_schedule_service.generate_schedule(SEPT_1, SEPT_30)

    stored_again = (await schedule_items.find({}).to_list())[0]
    assert stored_again["purchased"] is True
    assert stored_again["purchased_by"] == "admin"
