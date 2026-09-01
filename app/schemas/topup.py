from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class TopupCreate(BaseModel):
    member_id: str
    lunch_units: int = Field(default=0, ge=0)
    breakfast_units: int = Field(default=0, ge=0)
    brunch_units: int = Field(default=0, ge=0)
    # No amount field — the router computes it server-side from
    # settings.unit_prices x units, the single source of truth for pricing.
    # A client-supplied amount would let it drift from configured prices.
    payment_method: Literal["cash", "upi"]
    created_by: str = Field(min_length=1)

    @model_validator(mode="after")
    def _reject_zero_unit_topup(self) -> "TopupCreate":
        # A top-up that credits nothing is never intentional — its entire
        # purpose is crediting units (docs/PRD.md §7: "every action...
        # should have a clear, unambiguous outcome").
        if self.lunch_units == self.breakfast_units == self.brunch_units == 0:
            raise ValueError("A top-up needs at least one unit.")
        return self


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
    bill_pdf_path: str | None = None
    upi_qr_path: str | None = None
    created_by: str
    created_at: datetime
