from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class TopupCreate(BaseModel):
    member_id: str
    lunch_units: int = Field(default=0, ge=0)
    breakfast_units: int = Field(default=0, ge=0)
    brunch_units: int = Field(default=0, ge=0)
    amount: float = Field(ge=0)
    payment_method: Literal["cash", "upi"]
    created_by: str = Field(min_length=1)


class TopupOut(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

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
