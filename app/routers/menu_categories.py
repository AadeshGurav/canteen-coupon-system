from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pymongo.errors import DuplicateKeyError

from app.core.database import menu_categories
from app.core.security import require_role
from app.schemas.menu_category import MenuCategoryCreate, MenuCategoryUpdate
from app.utils.object_id import parse_object_id

router = APIRouter(
    prefix="/menu-categories", tags=["menu-categories"], dependencies=[Depends(require_role("admin"))]
)


def _oid(id_str: str):
    return parse_object_id(id_str, "menu category")


def _serialize(doc: dict) -> dict:
    doc["_id"] = str(doc["_id"])
    return doc


@router.post("")
async def create_menu_category(payload: MenuCategoryCreate):
    now = datetime.now(timezone.utc)
    doc = payload.model_dump()
    doc.update({"created_at": now, "updated_at": now})
    try:
        result = await menu_categories.insert_one(doc)
    except DuplicateKeyError:
        raise HTTPException(status_code=409, detail=f"Menu category '{payload.name}' already exists.")
    created = await menu_categories.find_one({"_id": result.inserted_id})
    return _serialize(created)


@router.get("")
async def list_menu_categories():
    docs = await menu_categories.find().sort("name", 1).to_list(length=200)
    return [_serialize(d) for d in docs]


@router.patch("/{category_id}")
async def update_menu_category(category_id: str, payload: MenuCategoryUpdate):
    updates = {k: v for k, v in payload.model_dump(exclude_unset=True).items()}
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update.")
    updates["updated_at"] = datetime.now(timezone.utc)

    try:
        result = await menu_categories.update_one({"_id": _oid(category_id)}, {"$set": updates})
    except DuplicateKeyError:
        raise HTTPException(status_code=409, detail=f"Menu category '{updates.get('name')}' already exists.")
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Menu category not found.")

    doc = await menu_categories.find_one({"_id": _oid(category_id)})
    return _serialize(doc)


@router.delete("/{category_id}")
async def delete_menu_category(category_id: str):
    result = await menu_categories.delete_one({"_id": _oid(category_id)})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Menu category not found.")
    return {"success": True}
