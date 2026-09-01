from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pymongo.errors import DuplicateKeyError

from app.core.database import ingredients
from app.core.security import require_role
from app.schemas.ingredient import IngredientCreate, IngredientUpdate
from app.utils.object_id import parse_object_id

# Admin manages the master list; counter can only read it — needed to pick
# an ingredient when adding a manual purchase-schedule item (see
# app/routers/purchase_schedule.py, which counter can also update).
router = APIRouter(prefix="/ingredients", tags=["ingredients"])


def _oid(id_str: str):
    return parse_object_id(id_str, "ingredient")


def _serialize(doc: dict) -> dict:
    doc["_id"] = str(doc["_id"])
    return doc


@router.post("", dependencies=[Depends(require_role("admin"))])
async def create_ingredient(payload: IngredientCreate):
    now = datetime.now(timezone.utc)
    doc = payload.model_dump()
    doc.update({"created_at": now, "updated_at": now})
    try:
        result = await ingredients.insert_one(doc)
    except DuplicateKeyError:
        raise HTTPException(status_code=409, detail=f"Ingredient '{payload.name}' already exists.")
    created = await ingredients.find_one({"_id": result.inserted_id})
    return _serialize(created)


@router.get("", dependencies=[Depends(require_role("admin", "counter"))])
async def list_ingredients():
    docs = await ingredients.find().sort("name", 1).to_list(length=500)
    return [_serialize(d) for d in docs]


@router.patch("/{ingredient_id}", dependencies=[Depends(require_role("admin"))])
async def update_ingredient(ingredient_id: str, payload: IngredientUpdate):
    updates = payload.model_dump(exclude_unset=True)
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update.")
    updates["updated_at"] = datetime.now(timezone.utc)

    try:
        result = await ingredients.update_one({"_id": _oid(ingredient_id)}, {"$set": updates})
    except DuplicateKeyError:
        raise HTTPException(status_code=409, detail=f"Ingredient '{updates.get('name')}' already exists.")
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Ingredient not found.")

    doc = await ingredients.find_one({"_id": _oid(ingredient_id)})
    return _serialize(doc)


@router.delete("/{ingredient_id}", dependencies=[Depends(require_role("admin"))])
async def delete_ingredient(ingredient_id: str):
    result = await ingredients.delete_one({"_id": _oid(ingredient_id)})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Ingredient not found.")
    return {"success": True}
