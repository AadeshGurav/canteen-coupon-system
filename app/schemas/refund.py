from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class RefundCreate(BaseModel):
    member_id: str
    lunch_units: int = Field(default=0, ge=0)
    breakfast_units: int = Field(default=0, ge=0)
    brunch_units: int = Field(default=0, ge=0)
    refund_amount: float = Field(ge=0)
    reason: Optional[str] = None
    processed_by: str = Field(
        min_length=1
    )  # admin recording this refund; the actual payout happens outside the app


class RefundOut(BaseModel):
    id: str
    member_id: str
    lunch_units: int
    breakfast_units: int
    brunch_units: int
    refund_amount: float
    reason: Optional[str] = None
    processed_by: str
    created_at: datetime
