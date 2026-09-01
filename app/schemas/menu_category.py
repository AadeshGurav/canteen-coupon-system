from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class MenuCategoryCreate(BaseModel):
    name: str          # e.g. "Jain", "Normal", "Staff"
    description: Optional[str] = None


class MenuCategoryUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None


class MenuCategoryOut(BaseModel):
    id: str
    name: str
    description: Optional[str] = None
    created_at: datetime
    updated_at: datetime
