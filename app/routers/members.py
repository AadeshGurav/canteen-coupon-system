import logging
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from app.core.database import member_entities
from app.schemas.member import CreditUpdate, MemberCreate, MemberUpdate
from app.services.qr_service import generate_qr_code_id, render_qr_image
from app.utils.object_id import parse_object_id

router = APIRouter(prefix="/members", tags=["members"])
logger = logging.getLogger(__name__)


def _oid(id_str: str):
    return parse_object_id(id_str, "member")


def _serialize(doc: dict) -> dict:
    doc["_id"] = str(doc["_id"])
    return doc


async def _insert_member(payload: MemberCreate) -> dict:
    now = datetime.utcnow()
    qr_code_id = generate_qr_code_id()

    doc = payload.model_dump()
    doc.update(
        {
            "qr_code_id": qr_code_id,
            "status": "active",
            "created_at": now,
            "updated_at": now,
        }
    )
    result = await member_entities.insert_one(doc)
    render_qr_image(qr_code_id)

    created = await member_entities.find_one({"_id": result.inserted_id})
    return _serialize(created)


@router.post("")
async def create_member(payload: MemberCreate):
    created = await _insert_member(payload)
    logger.info(
        "member.created member_id=%s type=%s name=%s", created["_id"], created["type"], created["name"]
    )
    return created


@router.post("/bulk")
async def bulk_create_members(payload: list[MemberCreate]):
    """Migrate existing paper-based records in one request. Each row is
    inserted independently — one bad row doesn't fail the whole batch, since
    the point of this endpoint is a large, messy, one-time paper-to-digital
    migration (see docs/PRD.md §6.1)."""
    created = []
    failed = []
    for index, member in enumerate(payload):
        try:
            created.append(await _insert_member(member))
        except Exception as exc:
            logger.exception("member.bulk_create_failed index=%d name=%s", index, member.name)
            failed.append({"index": index, "name": member.name, "error": str(exc)})

    logger.info("member.bulk_created count=%d failed=%d", len(created), len(failed))
    return {"created": created, "failed": failed}


@router.get("")
async def list_members(type: Optional[str] = None, status: Optional[str] = None):
    query = {}
    if type:
        query["type"] = type
    if status:
        query["status"] = status
    docs = await member_entities.find(query).to_list(length=5000)
    return [_serialize(d) for d in docs]


@router.get("/{member_id}")
async def get_member(member_id: str):
    doc = await member_entities.find_one({"_id": _oid(member_id)})
    if doc is None:
        raise HTTPException(status_code=404, detail="Member not found.")
    return _serialize(doc)


@router.patch("/{member_id}")
async def update_member(member_id: str, payload: MemberUpdate):
    updates = {k: v for k, v in payload.model_dump(exclude_unset=True).items()}
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update.")
    updates["updated_at"] = datetime.utcnow()

    result = await member_entities.update_one({"_id": _oid(member_id)}, {"$set": updates})
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Member not found.")
    logger.info("member.updated member_id=%s fields=%s", member_id, list(updates.keys()))

    doc = await member_entities.find_one({"_id": _oid(member_id)})
    return _serialize(doc)


@router.delete("/{member_id}")
async def delete_member(member_id: str):
    result = await member_entities.delete_one({"_id": _oid(member_id)})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Member not found.")
    logger.warning("member.deleted member_id=%s", member_id)
    return {"success": True}


@router.post("/{member_id}/credit")
async def credit_member(member_id: str, payload: CreditUpdate):
    member = await member_entities.find_one({"_id": _oid(member_id)})
    if member is None:
        raise HTTPException(status_code=404, detail="Member not found.")

    new_balances = {
        "balances.lunch": member["balances"].get("lunch", 0) + payload.lunch_units,
        "balances.breakfast": member["balances"].get("breakfast", 0) + payload.breakfast_units,
        "balances.brunch": member["balances"].get("brunch", 0) + payload.brunch_units,
    }
    await member_entities.update_one(
        {"_id": member["_id"]},
        {"$set": {**new_balances, "updated_at": datetime.utcnow()}},
    )
    logger.info(
        "member.credited member_id=%s lunch=%+d breakfast=%+d brunch=%+d",
        member_id,
        payload.lunch_units,
        payload.breakfast_units,
        payload.brunch_units,
    )
    doc = await member_entities.find_one({"_id": member["_id"]})
    return _serialize(doc)


@router.post("/{member_id}/reprint-qr")
async def reprint_qr(member_id: str):
    """Reprint the member's original QR code — never generates a new code id,
    so a lost or damaged card never creates a duplicate entity."""
    member = await member_entities.find_one({"_id": _oid(member_id)})
    if member is None:
        raise HTTPException(status_code=404, detail="Member not found.")

    path = render_qr_image(member["qr_code_id"])
    return FileResponse(path, media_type="image/png", filename=f"{member['name']}_qr.png")
