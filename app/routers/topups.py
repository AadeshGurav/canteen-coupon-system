import logging
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from app.core.database import member_entities, topups
from app.schemas.topup import TopupCreate
from app.services.billing_service import generate_bill_pdf, generate_upi_qr
from app.utils.object_id import parse_object_id

router = APIRouter(prefix="/topups", tags=["topups"])
logger = logging.getLogger(__name__)


@router.get("")
async def list_topups(member_id: str | None = None, limit: int = 200):
    query = {"member_id": member_id} if member_id else {}
    docs = await topups.find(query).sort("created_at", -1).to_list(length=min(limit, 1000))
    for d in docs:
        d["_id"] = str(d["_id"])
    return docs


@router.post("")
async def create_topup(payload: TopupCreate):
    member = await member_entities.find_one({"_id": parse_object_id(payload.member_id, "member")})
    if member is None:
        raise HTTPException(status_code=404, detail="Member not found.")

    now = datetime.now(timezone.utc)
    doc = {
        "member_id": payload.member_id,
        "lunch_units": payload.lunch_units,
        "breakfast_units": payload.breakfast_units,
        "brunch_units": payload.brunch_units,
        "amount": payload.amount,
        "payment_method": payload.payment_method,
        # cash is settled on the spot; UPI starts pending until admin confirms receipt
        "payment_status": "confirmed" if payload.payment_method == "cash" else "pending",
        "bill_pdf_path": None,
        "upi_qr_path": None,
        "created_by": payload.created_by,
        "created_at": now,
    }
    result = await topups.insert_one(doc)
    topup_id = str(result.inserted_id)

    # Credit balances immediately (bill/QR reflects the new totals either way)
    new_balances = {
        "lunch": member["balances"].get("lunch", 0) + payload.lunch_units,
        "breakfast": member["balances"].get("breakfast", 0) + payload.breakfast_units,
        "brunch": member["balances"].get("brunch", 0) + payload.brunch_units,
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
    logger.info(
        "topup.credited member_id=%s topup_id=%s lunch=%+d breakfast=%+d brunch=%+d amount=%.2f method=%s by=%s",
        payload.member_id,
        topup_id,
        payload.lunch_units,
        payload.breakfast_units,
        payload.brunch_units,
        payload.amount,
        payload.payment_method,
        payload.created_by,
    )

    # Bill/QR generation is a nice-to-have layered on top of a transaction
    # that already happened — the balance credit above must not be lost or
    # silently redone if rendering fails, so isolate the failure here rather
    # than letting it 500 the whole request with the credit already applied.
    bill_path = None
    upi_qr_path = None
    try:
        if payload.payment_method == "upi":
            upi_qr_path = generate_upi_qr(payload.amount, f"Canteen topup {topup_id}", topup_id)

        bill_path = generate_bill_pdf(
            topup_id=topup_id,
            member_name=member["name"],
            member_type=member["type"],
            lunch_units=payload.lunch_units,
            breakfast_units=payload.breakfast_units,
            brunch_units=payload.brunch_units,
            amount=payload.amount,
            payment_method=payload.payment_method,
            new_balances=new_balances,
            upi_qr_path=upi_qr_path,
        )
        await topups.update_one(
            {"_id": result.inserted_id},
            {"$set": {"bill_pdf_path": bill_path, "upi_qr_path": upi_qr_path}},
        )
    except Exception:
        logger.exception(
            "topup.bill_generation_failed topup_id=%s — balance was already credited; "
            "no bill/UPI QR exists for this topup, admin should generate one manually or "
            "inform the payer",
            topup_id,
        )

    updated = await topups.find_one({"_id": result.inserted_id})
    updated["_id"] = str(updated["_id"])
    return updated


@router.post("/{topup_id}/confirm-payment")
async def confirm_payment(topup_id: str):
    """Admin manually marks a UPI topup as paid once they see it land in their UPI app."""
    result = await topups.update_one(
        {"_id": parse_object_id(topup_id, "topup")},
        {"$set": {"payment_status": "confirmed"}},
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Topup not found.")
    logger.info("topup.payment_confirmed topup_id=%s", topup_id)
    return {"success": True}


@router.get("/{topup_id}/bill")
async def get_bill(topup_id: str):
    doc = await topups.find_one({"_id": parse_object_id(topup_id, "topup")})
    if doc is None or not doc.get("bill_pdf_path"):
        raise HTTPException(status_code=404, detail="Bill not found.")
    return FileResponse(doc["bill_pdf_path"], media_type="application/pdf", filename=f"bill_{topup_id}.pdf")
