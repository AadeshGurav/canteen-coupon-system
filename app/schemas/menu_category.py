from datetime import datetime

from pydantic import BaseModel, Field


class MenuCategoryCreate(BaseModel):
    name: str = Field(min_length=1)  # e.g. "Jain", "Normal", "Staff"
    description: str | None = None


class MenuCategoryUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1)
    description: str | None = None


class MenuCategoryOut(BaseModel):
    id: str
    name: str
    description: str | None = None
    created_at: datetime
    updated_at: datetime
