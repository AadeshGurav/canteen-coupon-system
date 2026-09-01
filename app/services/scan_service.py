import logging
from datetime import datetime, timedelta, timezone

from bson import ObjectId
from bson.errors import InvalidId

from app.core.database import get_global_settings, member_entities, scans
from app.schemas.scan import ScanResult
from app.utils.meal_window import current_meal_type, day_bounds, to_local

logger = logging.getLogger(__name__)


async def process_scan(qr_code_id: str, meal_type_override: str | None = None) -> ScanResult:
    # Stored timestamps stay UTC; meal-window/day-of-week resolution needs
    # the canteen's own local wall-clock time (see to_local()'s docstring).
    # local_timezone is admin-editable settings, not an env var.
    now_utc = datetime.now(timezone.utc)
    global_settings = await get_global_settings()
    now_local = to_local(now_utc, global_settings["local_timezone"])

    member = await member_entities.find_one({"qr_code_id": qr_code_id})
    if member is None:
        logger.warning("scan.rejected reason=unknown_code qr_code_id=%s", qr_code_id)
        return ScanResult(result="rejected_unknown_code", message="No member found for this code.")

    if member.get("status") != "active":
        logger.info("scan.rejected reason=inactive member_id=%s", member["_id"])
        return ScanResult(
            result="rejected_inactive",
            member_name=member["name"],
            member_type=member["type"],
            message="This member's account is inactive.",
        )

    meal_type = meal_type_override or current_meal_type(now_local, global_settings["meal_windows"])
    if meal_type is None:
        logger.info("scan.rejected reason=no_meal_window member_id=%s", member["_id"])
        return ScanResult(
            result="rejected_unknown_code",
            member_name=member["name"],
            member_type=member["type"],
            message="No meal is currently being served.",
        )

    # One-scan-per-meal-window lock — day-scoped, see day_bounds() for why.
    day_start, day_end = day_bounds(now_local)
    already_scanned = await scans.find_one(
        {
            "member_id": str(member["_id"]),
            "meal_type": meal_type,
            "scanned_at": {"$gte": day_start, "$lte": day_end},
            "reversed": False,
        }
    )
    if already_scanned:
        logger.info(
            "scan.rejected reason=already_scanned member_id=%s meal_type=%s", member["_id"], meal_type
        )
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
        logger.info(
            "scan.rejected reason=zero_balance member_id=%s meal_type=%s balance=%d",
            member["_id"],
            meal_type,
            balance,
        )
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
        {"$set": {f"balances.{meal_type}": new_balance, "updated_at": now_utc}},
    )
    await scans.insert_one(
        {
            "member_id": str(member["_id"]),
            "meal_type": meal_type,
            "scanned_at": now_utc,
            "result": "accepted",
            "via_grace": used_grace,
            "reversed": False,
            "reversed_at": None,
            "reversed_by": None,
        }
    )
    logger.info(
        "scan.accepted member_id=%s meal_type=%s new_balance=%d via_grace=%s",
        member["_id"],
        meal_type,
        new_balance,
        used_grace,
    )

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
    try:
        scan_oid = ObjectId(scan_id)
    except InvalidId:
        return {"success": False, "message": "Invalid scan id."}

    scan = await scans.find_one({"_id": scan_oid})
    if scan is None:
        return {"success": False, "message": "Scan not found."}
    if scan["reversed"]:
        return {"success": False, "message": "Scan already reversed."}
    if scan["result"] != "accepted":
        return {"success": False, "message": "Only accepted scans can be reversed."}

    global_settings = await get_global_settings()
    reversal_window = global_settings["reversal_window_minutes"]
    if datetime.now(timezone.utc) - scan["scanned_at"] > timedelta(minutes=reversal_window):
        return {"success": False, "message": f"Reversal window of {reversal_window} minutes has expired."}

    member = await member_entities.find_one({"_id": ObjectId(scan["member_id"])})
    if member is None:
        return {"success": False, "message": "Member not found."}

    meal_type = scan["meal_type"]
    restored_balance = member["balances"].get(meal_type, 0) + 1

    await member_entities.update_one(
        {"_id": member["_id"]},
        {"$set": {f"balances.{meal_type}": restored_balance, "updated_at": datetime.now(timezone.utc)}},
    )
    await scans.update_one(
        {"_id": scan["_id"]},
        {"$set": {"reversed": True, "reversed_at": datetime.now(timezone.utc), "reversed_by": reversed_by}},
    )
    logger.info(
        "scan.reversed scan_id=%s member_id=%s meal_type=%s restored_balance=%d by=%s",
        scan_id,
        scan["member_id"],
        meal_type,
        restored_balance,
        reversed_by,
    )

    return {"success": True, "message": f"Scan reversed, {restored_balance} {meal_type} units restored."}
