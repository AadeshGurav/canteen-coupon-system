from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field


class TopupCreate(BaseModel):
    member_id: str
    lunch_units: int = 0
    breakfast_units: int = 0
    brunch_units: int = 0
    amount: float
    payment_method: Literal["cash", "upi"]
    created_by: str


class TopupOut(BaseModel):
    id: str = Field(alias="_id")
    member_id: str
    lunch_units: int
    breakfast_units: int
    brunch_units: int
    amount: float
    payment_method: str
    payment_status: str
    bill_pdf_path: Optional[str] = None
    upi_qr_path: Optional[str] = None
    created_by: str
    created_at: datetime

    class Config:
        populate_by_name = True
