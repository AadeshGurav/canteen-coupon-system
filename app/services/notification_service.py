"""Persistent, in-app notifications — no email/SMS/push infrastructure, no
scheduled job. Reminders are computed lazily, on each `GET /notifications`
call: the endpoint is polled every ~45s from the dashboard nav (see
static/admin/js/nav.js), so "due right now" is evaluated often enough to
feel live, and idempotent upserts mean polling never creates duplicates.
This keeps the whole feature dependency-free (no APScheduler/Celery —
CLAUDE.md §10: "every new dependency is a decision, not a default")."""

from datetime import datetime, timedelta, timezone

from app.core.database import get_global_settings, menu_log, notifications, purchase_schedule_items
from app.utils.meal_window import is_saturday, to_local


async def generate_due_notifications(now: datetime) -> None:
    global_settings = await get_global_settings()
    local_now = to_local(now, global_settings["local_timezone"])
    await _generate_prep_reminders(local_now, global_settings)
    await _generate_purchase_reminders(local_now, global_settings)


async def _generate_prep_reminders(local_now: datetime, global_settings: dict) -> None:
    today = local_now.date()
    meal_types = ["brunch"] if is_saturday(local_now) else ["breakfast", "lunch"]
    lead_minutes = global_settings["prep_lead_minutes"]

    for meal_type in meal_types:
        window = global_settings["meal_windows"].get(meal_type)
        if not window:
            continue

        has_menu_planned = await menu_log.count_documents(
            {
                "date": datetime.combine(today, datetime.min.time()),
                "meal_type": meal_type,
            },
            limit=1,
        )
        if not has_menu_planned:
            continue  # nothing planned for this meal — nothing to prep

        hour, minute = (int(part) for part in window["start"].split(":"))
        window_start = local_now.replace(hour=hour, minute=minute, second=0, microsecond=0)
        minutes_until_start = (window_start - local_now).total_seconds() / 60
        if not (0 <= minutes_until_start <= lead_minutes):
            continue

        await _upsert_notification(
            notif_type="prep_reminder",
            date_=today,
            meal_type=meal_type,
            title=f"Start prepping {meal_type}",
            message=f"{meal_type.capitalize()} service starts at {window['start']} — "
            f"about {int(minutes_until_start)} minute(s) from now.",
            visible_roles=["admin", "counter"],
        )


async def _generate_purchase_reminders(local_now: datetime, global_settings: dict) -> None:
    target_date = (local_now + timedelta(days=global_settings["purchase_lead_days"])).date()
    pending_count = await purchase_schedule_items.count_documents(
        {"date": datetime.combine(target_date, datetime.min.time()), "purchased": False}
    )
    if pending_count == 0:
        return

    await _upsert_notification(
        notif_type="purchase_due",
        date_=target_date,
        meal_type=None,
        title="Ingredient purchase due",
        message=f"{pending_count} item(s) still need buying for {target_date.isoformat()}.",
        visible_roles=["admin", "counter"],
    )


async def _upsert_notification(
    *, notif_type: str, date_, meal_type: str | None, title: str, message: str, visible_roles: list[str]
) -> None:
    now = datetime.now(timezone.utc)
    key = {"type": notif_type, "date": date_.isoformat(), "meal_type": meal_type}
    await notifications.update_one(
        key,
        {
            "$set": {"title": title, "message": message, "visible_roles": visible_roles, "updated_at": now},
            "$setOnInsert": {"created_at": now, "dismissed_by": []},
        },
        upsert=True,
    )


async def list_active_for_role(role: str, username: str) -> list[dict]:
    docs = (
        await notifications.find({"visible_roles": role, "dismissed_by": {"$ne": username}})
        .sort("created_at", -1)
        .to_list(length=100)
    )
    for doc in docs:
        doc["_id"] = str(doc["_id"])
    return docs


async def dismiss_notification(notification_id, username: str) -> bool:
    result = await notifications.update_one(
        {"_id": notification_id}, {"$addToSet": {"dismissed_by": username}}
    )
    return result.matched_count > 0
