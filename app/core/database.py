from motor.motor_asyncio import AsyncIOMotorClient
from pymongo import ReturnDocument

from app.core.config import settings

# tz_aware=True: every datetime read back from Mongo comes back UTC-aware
# rather than naive. Paired with writing timezone-aware datetimes throughout
# (datetime.now(timezone.utc), never datetime.utcnow()) so comparisons never
# mix naive and aware values, and so API responses serialize timestamps with
# an explicit UTC offset instead of an ambiguous naive one — a naive
# timestamp like "2026-09-01T10:30:00" is parsed as *local* time by a
# browser's Date constructor, which was silently misdisplaying every
# timestamp in the admin dashboard for any admin not in UTC.
client: AsyncIOMotorClient = AsyncIOMotorClient(settings.mongo_uri, tz_aware=True)
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
users = db["users"]
sessions = db["sessions"]
ingredients = db["ingredients"]
recipes = db["recipes"]
purchase_schedule_items = db["purchase_schedule_items"]
notifications = db["notifications"]


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
    await users.create_index("username", unique=True)
    # expireAfterSeconds=0: MongoDB deletes a session document itself once
    # its own expires_at is in the past — no scheduled cleanup job needed,
    # same reasoning as the scan-window design elsewhere in this codebase.
    await sessions.create_index("expires_at", expireAfterSeconds=0)
    await ingredients.create_index("name", unique=True)
    # dish_name_lower: recipes are looked up by a menu entry's item name,
    # case-insensitively ("Dal" and "dal" are the same dish) — a unique
    # index on the normalized form prevents two recipes silently shadowing
    # each other for what a menu entry would treat as the same dish.
    await recipes.create_index("dish_name_lower", unique=True)
    await purchase_schedule_items.create_index([("date", 1), ("ingredient_id", 1)])
    await notifications.create_index([("type", 1), ("date", 1), ("meal_type", 1)])


_GLOBAL_SETTINGS_DEFAULTS = {
    "grace_allowance_enabled": False,
    "grace_allowance_units": 0,
    "reversal_window_minutes": 10,
    "meal_windows": {
        "breakfast": {"start": "07:00", "end": "09:30"},
        "lunch": {"start": "12:00", "end": "14:30"},
        "brunch": {"start": "09:00", "end": "12:00"},  # Saturday only
    },
    # Admin-editable via PATCH /settings, not an env var — see
    # app/routers/settings.py's SettingsUpdate for why.
    "local_timezone": "UTC",
    "upi_id": "",
    "upi_payee_name": "",
    # Price per unit — a top-up/refund's amount is computed from units x
    # price, not typed in by hand (see app/routers/topups.py, refunds.py).
    "unit_prices": {"lunch": 0.0, "breakfast": 0.0, "brunch": 0.0},
    # Shown in the dashboard's nav bar and browser tab title — purely
    # cosmetic branding, not the FastAPI/PDF app_name in app.core.config.
    "app_name": "Canteen Coupon System",
    # How far ahead of a meal window's start a "start prepping" notification
    # fires, and how many days ahead of an ingredient's purchase date a
    # "purchase due" notification fires — see app/services/notification_service.py.
    "prep_lead_minutes": 60,
    "purchase_lead_days": 1,
}


async def get_global_settings() -> dict:
    """Fetch the single global settings document, creating sane defaults if
    missing and backfilling any field added to this document after a given
    deployment's copy was first created — no manual migration needed when
    a new setting like local_timezone ships.

    Creation is a single atomic upsert, not a separate find-then-insert:
    gunicorn runs multiple worker processes, each running FastAPI's lifespan
    startup independently, so on a genuinely fresh database more than one
    worker calls this at the same moment. A plain "if not found, insert_one"
    here is a real race — the losing worker's insert hits the unique index
    on _id and raises DuplicateKeyError, crashing that worker's startup.
    find_one_and_update(upsert=True) delegates the check-and-create to
    MongoDB as one operation, so concurrent callers can't race it."""
    doc = await settings_collection.find_one_and_update(
        {"_id": "global"},
        {"$setOnInsert": _GLOBAL_SETTINGS_DEFAULTS},
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )

    missing = {key: value for key, value in _GLOBAL_SETTINGS_DEFAULTS.items() if key not in doc}
    if missing:
        doc.update(missing)
        await settings_collection.update_one({"_id": "global"}, {"$set": missing})
    return doc
