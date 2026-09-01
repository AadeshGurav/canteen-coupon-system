from datetime import datetime

from pydantic import BaseModel, Field


class IngredientCreate(BaseModel):
    name: str = Field(min_length=1)  # e.g. "Rice", "Toor dal", "Onion"
    unit: str = Field(min_length=1)  # e.g. "kg", "litre", "pcs" — free text, admin's own convention


class IngredientUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1)
    unit: str | None = Field(default=None, min_length=1)


class IngredientOut(BaseModel):
    id: str
    name: str
    unit: str
    created_at: datetime
    updated_at: datetime
