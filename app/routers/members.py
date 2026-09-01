import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from pymongo.errors import DuplicateKeyError

from app.core.database import member_entities, refunds, scans, topups
from app.core.security import require_role
from app.schemas.member import (
    CreditUpdate,
    MemberCreate,
    MemberUpdate,
    validate_type_specific_fields,
)
from app.services.qr_service import generate_qr_code_id, render_qr_image
from app.utils.object_id import parse_object_id

router = APIRouter(prefix="/members", tags=["members"])
logger = logging.getLogger(__name__)

# Counter operators need to look members up to select who's topping up, but
# nothing else here — everything that changes a member is admin-only.
_READ_ROLES = ("admin", "counter")


def _oid(id_str: str):
    return parse_object_id(id_str, "member")


def _serialize(doc: dict) -> dict:
    doc["_id"] = str(doc["_id"])
    return doc


async def _insert_member(payload: MemberCreate) -> dict:
    now = datetime.now(timezone.utc)

    doc = payload.model_dump()
    doc.update({"status": "active", "created_at": now, "updated_at": now})

    # qr_code_id is a random 12-hex-char id (see generate_qr_code_id) — a
    # collision is astronomically unlikely, but "unlikely" isn't "never":
    # retry with a fresh id rather than surfacing a raw DuplicateKeyError to
    # the admin as a generic 500 (same defensive pattern as
    # menu_categories.py's uniqueness constraint).
    for _ in range(3):
        doc["qr_code_id"] = generate_qr_code_id()
        try:
            result = await member_entities.insert_one(doc)
            break
        except DuplicateKeyError:
            continue
    else:
        raise HTTPException(status_code=500, detail="Could not generate a unique QR code — please try again.")
    render_qr_image(doc["qr_code_id"])

    created = await member_entities.find_one({"_id": result.inserted_id})
    return _serialize(created)


@router.post("", dependencies=[Depends(require_role("admin"))])
async def create_member(payload: MemberCreate):
    created = await _insert_member(payload)
    logger.info(
        "member.created member_id=%s type=%s name=%s", created["_id"], created["type"], created["name"]
    )
    return created


@router.post("/bulk", dependencies=[Depends(require_role("admin"))])
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


@router.get("", dependencies=[Depends(require_role(*_READ_ROLES))])
async def list_members(type: str | None = None, status: str | None = None):
    query = {}
    if type:
        query["type"] = type
    if status:
        query["status"] = status
    docs = await member_entities.find(query).to_list(length=5000)
    return [_serialize(d) for d in docs]


@router.get("/{member_id}", dependencies=[Depends(require_role(*_READ_ROLES))])
async def get_member(member_id: str):
    doc = await member_entities.find_one({"_id": _oid(member_id)})
    if doc is None:
        raise HTTPException(status_code=404, detail="Member not found.")
    return _serialize(doc)


@router.patch("/{member_id}", dependencies=[Depends(require_role("admin"))])
async def update_member(member_id: str, payload: MemberUpdate):
    updates = {k: v for k, v in payload.model_dump(exclude_unset=True).items()}
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update.")

    existing = await member_entities.find_one({"_id": _oid(member_id)})
    if existing is None:
        raise HTTPException(status_code=404, detail="Member not found.")

    # type itself isn't in MemberUpdate (immutable after creation — see
    # reprint_qr's docstring on qr_code_id for the same "never lets an
    # identity split into two records" reasoning), but a raw PATCH could
    # still set a staff_id on a student or vice versa without this check.
    try:
        validate_type_specific_fields(
            existing["type"],
            updates.get("class_name", existing.get("class_name")),
            updates.get("roll_number", existing.get("roll_number")),
            updates.get("staff_id", existing.get("staff_id")),
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    updates["updated_at"] = datetime.now(timezone.utc)
    await member_entities.update_one({"_id": existing["_id"]}, {"$set": updates})
    logger.info("member.updated member_id=%s fields=%s", member_id, list(updates.keys()))

    doc = await member_entities.find_one({"_id": existing["_id"]})
    return _serialize(doc)


@router.delete("/{member_id}", dependencies=[Depends(require_role("admin"))])
async def delete_member(member_id: str):
    """Only for a member with no history yet (e.g. created by mistake).
    Once a member has scans/top-ups/refunds, deleting them would orphan
    those records' member_id references — breaking the audit trail this
    system otherwise goes out of its way to preserve (scan reversal and
    refunds both keep a record rather than delete one). Use PATCH
    {"status": "inactive"} for a member who's actually leaving."""
    oid = _oid(member_id)
    has_history = any(
        [
            await scans.find_one({"member_id": member_id}),
            await topups.find_one({"member_id": member_id}),
            await refunds.find_one({"member_id": member_id}),
        ]
    )
    if has_history:
        raise HTTPException(
            status_code=409,
            detail=(
                "This member has scan, top-up, or refund history and can't be deleted — "
                "it would orphan those records. Set status to 'inactive' instead."
            ),
        )

    result = await member_entities.delete_one({"_id": oid})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Member not found.")
    logger.warning("member.deleted member_id=%s", member_id)
    return {"success": True}


@router.post("/{member_id}/credit", dependencies=[Depends(require_role("admin"))])
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
        {"$set": {**new_balances, "updated_at": datetime.now(timezone.utc)}},
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


@router.post("/{member_id}/reprint-qr", dependencies=[Depends(require_role("admin"))])
async def reprint_qr(member_id: str):
    """Reprint the member's original QR code — never generates a new code id,
    so a lost or damaged card never creates a duplicate entity."""
    member = await member_entities.find_one({"_id": _oid(member_id)})
    if member is None:
        raise HTTPException(status_code=404, detail="Member not found.")

    path = render_qr_image(member["qr_code_id"])
    return FileResponse(path, media_type="image/png", filename=f"{member['name']}_qr.png")
