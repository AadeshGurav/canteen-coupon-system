from datetime import date, datetime

from pydantic import BaseModel, Field


class PurchaseScheduleItemCreate(BaseModel):
    """A manually-added purchase item — the auto-generated ones (from
    POST /purchase-schedule/generate) don't go through this; this is for
    something needed that the menu calendar/recipes wouldn't otherwise
    surface (e.g. a one-off supply, not a recipe ingredient)."""

    date: date
    ingredient_id: str
    quantity_note: str = Field(min_length=1)


class PurchaseScheduleItemUpdate(BaseModel):
    quantity_note: str | None = Field(default=None, min_length=1)
    purchased: bool | None = None


class PurchaseScheduleItemOut(BaseModel):
    id: str
    date: date
    ingredient_id: str
    ingredient_name: str
    ingredient_unit: str
    quantity_note: str
    source: str  # "auto" | "manual"
    purchased: bool
    purchased_by: str | None = None
    purchased_at: datetime | None = None
    created_at: datetime
    updated_at: datetime
