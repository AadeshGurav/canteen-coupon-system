import logging
from typing import Literal, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.core.database import get_global_settings, settings_collection

router = APIRouter(prefix="/settings", tags=["settings"])
logger = logging.getLogger(__name__)

# HH:MM, 24-hour — validated here so a malformed value can never reach
# app/utils/meal_window.py, which would otherwise crash the scan endpoint
# (the highest-stakes flow in the system) on the next scan attempt.
_HHMM_PATTERN = r"^([01]\d|2[0-3]):[0-5]\d$"


class MealWindow(BaseModel):
    start: str = Field(pattern=_HHMM_PATTERN)
    end: str = Field(pattern=_HHMM_PATTERN)


class SettingsUpdate(BaseModel):
    grace_allowance_enabled: Optional[bool] = None
    grace_allowance_units: Optional[int] = Field(default=None, ge=0)
    reversal_window_minutes: Optional[int] = Field(default=None, ge=0)
    # Partial updates supported: only include the meal(s) you want to change,
    # e.g. {"meal_windows": {"lunch": {"start": "12:30", "end": "14:00"}}}
    meal_windows: Optional[dict[Literal["breakfast", "lunch", "brunch"], MealWindow]] = None


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
            if window.start >= window.end:
                raise HTTPException(
                    status_code=400,
                    detail=f"{meal_type} window start ({window.start}) must be before end ({window.end}).",
                )
            merged[meal_type] = window.model_dump()
        updates["meal_windows"] = merged

    if updates:
        await settings_collection.update_one({"_id": "global"}, {"$set": updates}, upsert=True)
        logger.info("settings.updated fields=%s", list(updates.keys()))
    return await get_global_settings()
