from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class RefundCreate(BaseModel):
    member_id: str
    lunch_units: int = 0
    breakfast_units: int = 0
    brunch_units: int = 0
    refund_amount: float
    reason: Optional[str] = None
    processed_by: str  # admin recording this refund; the actual payout happens outside the app


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
