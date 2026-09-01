from motor.motor_asyncio import AsyncIOMotorClient

from app.core.config import settings

client: AsyncIOMotorClient = AsyncIOMotorClient(settings.mongo_uri)
db = client[settings.mongo_db_name]

# Collections
member_entities = db["member_entities"]
scans = db["scans"]
topups = db["topups"]
menu_log = db["menu_log"]
menu_categories = db["menu_categories"]
refunds = db["refunds"]
expenses = db["expenses"]
settings_collection = db["settings"]


async def ensure_indexes():
    """Create indexes needed for correctness and speed. Call once at startup."""
    await member_entities.create_index("qr_code_id", unique=True)
    await member_entities.create_index("type")
    await scans.create_index([("member_id", 1), ("scanned_at", -1)])
    await scans.create_index([("member_id", 1), ("meal_type", 1), ("scanned_at", -1)])
    await topups.create_index("member_id")
    await menu_log.create_index("date")
    await menu_categories.create_index("name", unique=True)
    await refunds.create_index("member_id")
    await expenses.create_index("date")


async def get_global_settings() -> dict:
    """Fetch the single global settings document, creating sane defaults if missing.
    Meal windows are stored here (as HH:MM strings) so they're editable from the
    admin settings screen without touching code."""
    doc = await settings_collection.find_one({"_id": "global"})
    if doc is None:
        doc = {
            "_id": "global",
            "grace_allowance_enabled": False,
            "grace_allowance_units": 0,
            "reversal_window_minutes": 10,
            "meal_windows": {
                "breakfast": {"start": "07:00", "end": "09:30"},
                "lunch": {"start": "12:00", "end": "14:30"},
                "brunch": {"start": "09:00", "end": "12:00"},  # Saturday only
            },
        }
        await settings_collection.insert_one(doc)
    elif "meal_windows" not in doc:
        # backfill for docs created before this field existed
        doc["meal_windows"] = {
            "breakfast": {"start": "07:00", "end": "09:30"},
            "lunch": {"start": "12:00", "end": "14:30"},
            "brunch": {"start": "09:00", "end": "12:00"},
        }
        await settings_collection.update_one({"_id": "global"}, {"$set": {"meal_windows": doc["meal_windows"]}})
    return doc
