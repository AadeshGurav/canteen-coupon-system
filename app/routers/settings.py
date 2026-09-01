import logging
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError, available_timezones

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from app.core.database import get_global_settings, settings_collection
from app.core.security import require_role

router = APIRouter(prefix="/settings", tags=["settings"])
logger = logging.getLogger(__name__)

# HH:MM, 24-hour — validated here so a malformed value can never reach
# app/utils/meal_window.py, which would otherwise crash the scan endpoint
# (the highest-stakes flow in the system) on the next scan attempt.
_HHMM_PATTERN = r"^([01]\d|2[0-3]):[0-5]\d$"

# Sorted once at import time, not per-request — the set of IANA zones a
# given Python/OS ships with doesn't change while the process is running.
_SORTED_TIMEZONES = sorted(available_timezones())


class MealWindow(BaseModel):
    start: str = Field(pattern=_HHMM_PATTERN)
    end: str = Field(pattern=_HHMM_PATTERN)


class UnitPrices(BaseModel):
    lunch: float = Field(ge=0)
    breakfast: float = Field(ge=0)
    brunch: float = Field(ge=0)


class SettingsUpdate(BaseModel):
    grace_allowance_enabled: bool | None = None
    grace_allowance_units: int | None = Field(default=None, ge=0)
    reversal_window_minutes: int | None = Field(default=None, ge=0)
    # Partial updates supported: only include the meal(s) you want to change,
    # e.g. {"meal_windows": {"lunch": {"start": "12:30", "end": "14:00"}}}
    meal_windows: dict[Literal["breakfast", "lunch", "brunch"], MealWindow] | None = None
    # The canteen's own IANA timezone (e.g. "Asia/Kolkata") — meal windows
    # above are this zone's local wall-clock hours, not UTC. Admin-editable
    # here rather than an env var, same as everything else on this page —
    # it can change if the canteen itself ever does.
    local_timezone: str | None = None
    # UPI ID/payee name for the payment QR on a top-up bill (see
    # app/services/billing_service.py). Blank upi_id means "no UPI QR" —
    # cash-only setups don't need either set.
    upi_id: str | None = None
    upi_payee_name: str | None = None
    # Price per unit — top-up/refund amounts are computed from this, never
    # typed in by hand (see app/routers/topups.py, refunds.py).
    unit_prices: UnitPrices | None = None
    # Shown in the dashboard's nav bar and browser tab title.
    app_name: str | None = Field(default=None, min_length=1)

    @field_validator("local_timezone")
    @classmethod
    def _validate_timezone(cls, value: str | None) -> str | None:
        if value is None:
            return value
        try:
            ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError(f"'{value}' is not a valid IANA timezone name (e.g. 'Asia/Kolkata', 'UTC').")
        return value


@router.get("/branding")
async def get_branding():
    """The one setting the login page needs before anyone has a session —
    deliberately public and deliberately just this one field, not the rest
    of GET /settings (grace allowance, UPI id, etc. stay behind login)."""
    global_settings = await get_global_settings()
    return {"app_name": global_settings["app_name"]}


@router.get("", dependencies=[Depends(require_role("admin", "counter"))])
async def get_settings():
    return await get_global_settings()


@router.get("/timezones", dependencies=[Depends(require_role("admin"))])
async def list_timezones():
    """Backs the Settings page's timezone dropdown — served from Python's
    own tzdata rather than a hand-maintained list in JS, so it can never
    drift from what local_timezone actually accepts (see the field
    validator above)."""
    return _SORTED_TIMEZONES


@router.patch("", dependencies=[Depends(require_role("admin"))])
async def update_settings(payload: SettingsUpdate):
    updates = payload.model_dump(exclude_unset=True, exclude={"meal_windows", "unit_prices"})

    if payload.unit_prices is not None:
        updates["unit_prices"] = payload.unit_prices.model_dump()

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
