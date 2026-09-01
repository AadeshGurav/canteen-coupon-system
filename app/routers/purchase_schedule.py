from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, HTTPException

from app.core.database import ingredients, purchase_schedule_items
from app.core.security import require_role
from app.schemas.purchase_schedule import PurchaseScheduleItemCreate, PurchaseScheduleItemUpdate
from app.services.purchase_schedule_service import generate_schedule
from app.utils.object_id import parse_object_id

# Admin manages ingredients/recipes (app/routers/ingredients.py,
# app/routers/recipes.py); admin AND counter can view, check off, and add
# ad-hoc items on the resulting shopping list — whoever's actually at the
# counter running errands needs to update it, not just look at it.
router = APIRouter(prefix="/purchase-schedule", tags=["purchase-schedule"])


def _oid(id_str: str):
    return parse_object_id(id_str, "purchase schedule item")


def _serialize(doc: dict) -> dict:
    doc["_id"] = str(doc["_id"])
    return doc


@router.post("/generate", dependencies=[Depends(require_role("admin"))])
async def generate(start: date, end: date):
    if start > end:
        raise HTTPException(status_code=400, detail="start must be on or before end.")
    created = await generate_schedule(start, end)
    return {"created": created}


@router.get("", dependencies=[Depends(require_role("admin", "counter"))])
async def list_schedule(start: date | None = None, end: date | None = None):
    query = {}
    if start or end:
        query["date"] = {}
        if start:
            query["date"]["$gte"] = datetime.combine(start, datetime.min.time())
        if end:
            query["date"]["$lte"] = datetime.combine(end, datetime.min.time())
    docs = await purchase_schedule_items.find(query).sort("date", 1).to_list(length=2000)
    return [_serialize(d) for d in docs]


@router.post("", dependencies=[Depends(require_role("admin", "counter"))])
async def add_manual_item(payload: PurchaseScheduleItemCreate):
    ingredient = await ingredients.find_one({"_id": parse_object_id(payload.ingredient_id, "ingredient")})
    if ingredient is None:
        raise HTTPException(status_code=404, detail="Ingredient not found.")

    now = datetime.now(timezone.utc)
    doc = {
        "date": datetime.combine(payload.date, datetime.min.time()),
        "ingredient_id": payload.ingredient_id,
        "ingredient_name": ingredient["name"],
        "ingredient_unit": ingredient["unit"],
        "quantity_note": payload.quantity_note,
        "source": "manual",
        "purchased": False,
        "purchased_by": None,
        "purchased_at": None,
        "created_at": now,
        "updated_at": now,
    }
    result = await purchase_schedule_items.insert_one(doc)
    doc["_id"] = result.inserted_id
    return _serialize(doc)


@router.patch("/{item_id}")
async def update_item(
    item_id: str,
    payload: PurchaseScheduleItemUpdate,
    user: dict = Depends(require_role("admin", "counter")),
):
    updates = payload.model_dump(exclude_unset=True)
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update.")

    if "purchased" in updates:
        if updates["purchased"]:
            updates["purchased_by"] = user["username"]
            updates["purchased_at"] = datetime.now(timezone.utc)
        else:
            updates["purchased_by"] = None
            updates["purchased_at"] = None
    updates["updated_at"] = datetime.now(timezone.utc)

    result = await purchase_schedule_items.update_one({"_id": _oid(item_id)}, {"$set": updates})
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Purchase schedule item not found.")

    doc = await purchase_schedule_items.find_one({"_id": _oid(item_id)})
    return _serialize(doc)


@router.delete("/{item_id}", dependencies=[Depends(require_role("admin"))])
async def delete_item(item_id: str):
    result = await purchase_schedule_items.delete_one({"_id": _oid(item_id)})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Purchase schedule item not found.")
    return {"success": True}
