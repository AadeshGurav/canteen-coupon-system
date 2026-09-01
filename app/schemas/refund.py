from datetime import datetime

from pydantic import BaseModel, Field, model_validator


class RefundCreate(BaseModel):
    member_id: str
    lunch_units: int = Field(default=0, ge=0)
    breakfast_units: int = Field(default=0, ge=0)
    brunch_units: int = Field(default=0, ge=0)
    # No refund_amount field — the router computes it server-side from
    # settings.unit_prices x units, same reasoning as TopupCreate.
    reason: str | None = None
    processed_by: str = Field(
        min_length=1
    )  # admin recording this refund; the actual payout happens outside the app

    @model_validator(mode="after")
    def _reject_zero_unit_refund(self) -> "RefundCreate":
        if self.lunch_units == self.breakfast_units == self.brunch_units == 0:
            raise ValueError("A refund needs at least one unit.")
        return self


class RefundOut(BaseModel):
    id: str
    member_id: str
    lunch_units: int
    breakfast_units: int
    brunch_units: int
    refund_amount: float
    reason: str | None = None
    processed_by: str
    created_at: datetime
