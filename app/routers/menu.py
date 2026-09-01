from datetime import date, datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.core.database import menu_categories, menu_log
from app.core.security import require_role
from app.utils.object_id import parse_object_id

router = APIRouter(prefix="/menu", tags=["menu"], dependencies=[Depends(require_role("admin"))])


class MenuEntryCreate(BaseModel):
    date: date
    meal_type: Literal["lunch", "breakfast", "brunch"]
    # names from menu-categories, e.g. ["Jain", "Normal"] — at least one,
    # per docs/PRD.md §6.5 ("tagged with one or more menu categories")
    categories: list[str] = Field(min_length=1)
    items: list[str] = Field(min_length=1)
    created_by: str = Field(min_length=1)


async def _validate_categories(names: list[str]) -> None:
    existing = {doc["name"] async for doc in menu_categories.find({"name": {"$in": names}})}
    unknown = [n for n in names if n not in existing]
    if unknown:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown menu category/categories: {', '.join(unknown)}. Create them first via /menu-categories.",
        )


@router.post("")
async def add_menu_entry(payload: MenuEntryCreate):
    await _validate_categories(payload.categories)
    doc = payload.model_dump()
    doc["date"] = datetime.combine(payload.date, datetime.min.time())
    result = await menu_log.insert_one(doc)
    doc["_id"] = str(result.inserted_id)
    return doc


@router.get("")
async def list_menu(start: date | None = None, end: date | None = None):
    query = {}
    if start or end:
        query["date"] = {}
        if start:
            query["date"]["$gte"] = datetime.combine(start, datetime.min.time())
        if end:
            query["date"]["$lte"] = datetime.combine(end, datetime.min.time())
    docs = await menu_log.find(query).sort("date", 1).to_list(length=1000)
    for d in docs:
        d["_id"] = str(d["_id"])
    return docs


@router.delete("/{entry_id}")
async def delete_menu_entry(entry_id: str):
    result = await menu_log.delete_one({"_id": parse_object_id(entry_id, "menu entry")})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Menu entry not found.")
    return {"success": True}
