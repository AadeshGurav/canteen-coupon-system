from datetime import datetime, timedelta

from app.core.database import member_entities, scans, get_global_settings
from app.schemas.scan import ScanResult
from app.utils.meal_window import current_meal_type, meal_window_bounds


async def process_scan(qr_code_id: str, meal_type_override: str | None = None) -> ScanResult:
    now = datetime.utcnow()
    global_settings = await get_global_settings()

    member = await member_entities.find_one({"qr_code_id": qr_code_id})
    if member is None:
        return ScanResult(result="rejected_unknown_code", message="No member found for this code.")

    if member.get("status") != "active":
        return ScanResult(
            result="rejected_inactive",
            member_name=member["name"],
            member_type=member["type"],
            message="This member's account is inactive.",
        )

    meal_type = meal_type_override or current_meal_type(now, global_settings["meal_windows"])
    if meal_type is None:
        return ScanResult(
            result="rejected_unknown_code",
            member_name=member["name"],
            member_type=member["type"],
            message="No meal is currently being served.",
        )

    # One-scan-per-meal-window lock
    window_start, window_end = meal_window_bounds(meal_type, now, global_settings["meal_windows"])
    already_scanned = await scans.find_one({
        "member_id": str(member["_id"]),
        "meal_type": meal_type,
        "scanned_at": {"$gte": window_start, "$lte": window_end},
        "reversed": False,
    })
    if already_scanned:
        return ScanResult(
            result="rejected_already_scanned",
            member_name=member["name"],
            member_type=member["type"],
            meal_type=meal_type,
            message=f"{member['name']} has already collected {meal_type} in this window.",
        )

    # Balance + grace allowance check
    balance = member["balances"].get(meal_type, 0)
    grace = member.get("grace_allowance_override")
    if grace is None:
        grace = global_settings["grace_allowance_units"] if global_settings["grace_allowance_enabled"] else 0

    min_allowed_balance = -grace

    if balance <= min_allowed_balance:
        return ScanResult(
            result="rejected_zero_balance",
            member_name=member["name"],
            member_type=member["type"],
            meal_type=meal_type,
            remaining_balance=balance,
            message=f"{member['name']} has no {meal_type} units remaining.",
        )

    # Accept: deduct unit and log the scan
    new_balance = balance - 1
    used_grace = new_balance < 0  # meal was only possible because of the grace allowance
    await member_entities.update_one(
        {"_id": member["_id"]},
        {"$set": {f"balances.{meal_type}": new_balance, "updated_at": now}},
    )
    await scans.insert_one({
        "member_id": str(member["_id"]),
        "meal_type": meal_type,
        "scanned_at": now,
        "result": "accepted",
        "via_grace": used_grace,
        "reversed": False,
        "reversed_at": None,
        "reversed_by": None,
    })

    grace_note = " (via grace allowance)" if used_grace else ""
    return ScanResult(
        result="accepted",
        member_name=member["name"],
        member_type=member["type"],
        meal_type=meal_type,
        remaining_balance=new_balance,
        via_grace=used_grace,
        message=f"Confirmed — {member['name']} ({meal_type}){grace_note}. {new_balance} remaining.",
    )


async def reverse_scan(scan_id: str, reversed_by: str) -> dict:
    from bson import ObjectId

    scan = await scans.find_one({"_id": ObjectId(scan_id)})
    if scan is None:
        return {"success": False, "message": "Scan not found."}
    if scan["reversed"]:
        return {"success": False, "message": "Scan already reversed."}
    if scan["result"] != "accepted":
        return {"success": False, "message": "Only accepted scans can be reversed."}

    global_settings = await get_global_settings()
    reversal_window = global_settings["reversal_window_minutes"]
    if datetime.utcnow() - scan["scanned_at"] > timedelta(minutes=reversal_window):
        return {"success": False, "message": f"Reversal window of {reversal_window} minutes has expired."}

    member = await member_entities.find_one({"_id": ObjectId(scan["member_id"])})
    if member is None:
        return {"success": False, "message": "Member not found."}

    meal_type = scan["meal_type"]
    restored_balance = member["balances"].get(meal_type, 0) + 1

    await member_entities.update_one(
        {"_id": member["_id"]},
        {"$set": {f"balances.{meal_type}": restored_balance, "updated_at": datetime.utcnow()}},
    )
    await scans.update_one(
        {"_id": scan["_id"]},
        {"$set": {"reversed": True, "reversed_at": datetime.utcnow(), "reversed_by": reversed_by}},
    )

    return {"success": True, "message": f"Scan reversed, {restored_balance} {meal_type} units restored."}
