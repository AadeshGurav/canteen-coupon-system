import logging
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException

from app.core.database import member_entities, refunds
from app.schemas.refund import RefundCreate
from app.utils.object_id import parse_object_id

router = APIRouter(prefix="/refunds", tags=["refunds"])
logger = logging.getLogger(__name__)


@router.post("")
async def create_refund(payload: RefundCreate):
    """Record a refund and deduct the refunded units from the member's balance.

    The actual money movement (cash handed back, bank transfer, etc.) happens
    outside the app and is the admin's responsibility — this just keeps the
    unit ledger accurate and creates a record of what was refunded and why,
    e.g. when a student leaves the school."""
    member = await member_entities.find_one({"_id": parse_object_id(payload.member_id, "member")})
    if member is None:
        raise HTTPException(status_code=404, detail="Member not found.")

    balances = member["balances"]
    for meal_type, requested in (
        ("lunch", payload.lunch_units),
        ("breakfast", payload.breakfast_units),
        ("brunch", payload.brunch_units),
    ):
        if requested > balances.get(meal_type, 0):
            raise HTTPException(
                status_code=400,
                detail=f"Cannot refund {requested} {meal_type} units — member only has {balances.get(meal_type, 0)}.",
            )

    now = datetime.now(timezone.utc)
    new_balances = {
        "lunch": balances.get("lunch", 0) - payload.lunch_units,
        "breakfast": balances.get("breakfast", 0) - payload.breakfast_units,
        "brunch": balances.get("brunch", 0) - payload.brunch_units,
    }
    await member_entities.update_one(
        {"_id": member["_id"]},
        {
            "$set": {
                "balances.lunch": new_balances["lunch"],
                "balances.breakfast": new_balances["breakfast"],
                "balances.brunch": new_balances["brunch"],
                "updated_at": now,
            }
        },
    )

    doc = payload.model_dump()
    doc["created_at"] = now
    result = await refunds.insert_one(doc)
    doc["_id"] = str(result.inserted_id)
    logger.info(
        "refund.created member_id=%s refund_id=%s lunch=%d breakfast=%d brunch=%d amount=%.2f by=%s",
        payload.member_id,
        doc["_id"],
        payload.lunch_units,
        payload.breakfast_units,
        payload.brunch_units,
        payload.refund_amount,
        payload.processed_by,
    )
    return doc


@router.get("")
async def list_refunds(member_id: str | None = None):
    query = {"member_id": member_id} if member_id else {}
    docs = await refunds.find(query).sort("created_at", -1).to_list(length=5000)
    for d in docs:
        d["_id"] = str(d["_id"])
    return docs
