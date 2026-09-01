from datetime import date, datetime
from typing import Literal, Optional

from bson import ObjectId
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.core.database import menu_log, menu_categories

router = APIRouter(prefix="/menu", tags=["menu"])


class MenuEntryCreate(BaseModel):
    date: date
    meal_type: Literal["lunch", "breakfast", "brunch"]
    categories: list[str]  # names from menu-categories, e.g. ["Jain", "Normal"]
    items: list[str]
    created_by: str


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
async def list_menu(start: Optional[date] = None, end: Optional[date] = None):
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
    result = await menu_log.delete_one({"_id": ObjectId(entry_id)})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Menu entry not found.")
    return {"success": True}
