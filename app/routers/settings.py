from typing import Optional

from fastapi import APIRouter
from pydantic import BaseModel

from app.core.database import settings_collection, get_global_settings

router = APIRouter(prefix="/settings", tags=["settings"])


class MealWindow(BaseModel):
    start: str  # "HH:MM", 24-hour
    end: str    # "HH:MM", 24-hour


class SettingsUpdate(BaseModel):
    grace_allowance_enabled: Optional[bool] = None
    grace_allowance_units: Optional[int] = None
    reversal_window_minutes: Optional[int] = None
    # Partial updates supported: only include the meal(s) you want to change,
    # e.g. {"meal_windows": {"lunch": {"start": "12:30", "end": "14:00"}}}
    meal_windows: Optional[dict[str, MealWindow]] = None


@router.get("")
async def get_settings():
    return await get_global_settings()


@router.patch("")
async def update_settings(payload: SettingsUpdate):
    updates = payload.model_dump(exclude_unset=True, exclude={"meal_windows"})

    if payload.meal_windows is not None:
        # merge into existing meal_windows rather than overwriting the whole map,
        # so you can update just "lunch" without resending breakfast/brunch
        current = await get_global_settings()
        merged = dict(current["meal_windows"])
        for meal_type, window in payload.meal_windows.items():
            merged[meal_type] = window.model_dump()
        updates["meal_windows"] = merged

    if updates:
        await settings_collection.update_one({"_id": "global"}, {"$set": updates}, upsert=True)
    return await get_global_settings()
