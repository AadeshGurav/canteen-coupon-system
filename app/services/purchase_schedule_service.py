"""Derives a purchase schedule from the menu calendar: for every planned menu
entry in a date range, look up that dish's recipe (if one exists) and ensure
one purchase-schedule item exists per (date, ingredient) — idempotently, so
running this again for an overlapping range never duplicates or resets an
item someone already checked off or edited."""

from datetime import date, datetime, timezone

from app.core.database import ingredients, menu_log, purchase_schedule_items, recipes
from app.utils.object_id import parse_object_id


async def generate_schedule(start: date, end: date) -> int:
    """Returns the number of new purchase-schedule items created."""
    date_range = {
        "$gte": datetime.combine(start, datetime.min.time()),
        "$lte": datetime.combine(end, datetime.min.time()),
    }
    entries = await menu_log.find({"date": date_range}).to_list(length=2000)
    if not entries:
        return 0

    dish_names = {item.strip().lower() for entry in entries for item in entry["items"]}
    recipe_docs = await recipes.find({"dish_name_lower": {"$in": list(dish_names)}}).to_list(length=500)
    recipes_by_dish = {r["dish_name_lower"]: r for r in recipe_docs}

    ingredient_ids = {ing["ingredient_id"] for r in recipe_docs for ing in r["ingredients"]}
    ingredient_docs = await ingredients.find(
        {"_id": {"$in": [_as_object_id(i) for i in ingredient_ids]}}
    ).to_list(length=500)
    ingredients_by_id = {str(i["_id"]): i for i in ingredient_docs}

    created = 0
    now = datetime.now(timezone.utc)
    for entry in entries:
        entry_date = entry["date"].date() if isinstance(entry["date"], datetime) else entry["date"]
        for item_name in entry["items"]:
            recipe = recipes_by_dish.get(item_name.strip().lower())
            if not recipe:
                continue
            for recipe_ingredient in recipe["ingredients"]:
                ingredient_id = recipe_ingredient["ingredient_id"]
                ingredient = ingredients_by_id.get(ingredient_id)
                if not ingredient:
                    continue  # ingredient was deleted after the recipe was saved
                result = await purchase_schedule_items.update_one(
                    {
                        "date": datetime.combine(entry_date, datetime.min.time()),
                        "ingredient_id": ingredient_id,
                    },
                    {
                        "$setOnInsert": {
                            "ingredient_name": ingredient["name"],
                            "ingredient_unit": ingredient["unit"],
                            "quantity_note": recipe_ingredient["quantity_note"],
                            "source": "auto",
                            "purchased": False,
                            "purchased_by": None,
                            "purchased_at": None,
                            "created_at": now,
                            "updated_at": now,
                        }
                    },
                    upsert=True,
                )
                if result.upserted_id is not None:
                    created += 1
    return created


def _as_object_id(id_str: str):
    return parse_object_id(id_str, "ingredient")
