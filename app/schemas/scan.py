from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class ScanRequest(BaseModel):
    qr_code_id: str = Field(min_length=1)
    # meal_type is normally auto-detected from current time/day, but can be
    # overridden by the counter operator if needed (e.g. testing, edge cases)
    meal_type_override: Literal["lunch", "breakfast", "brunch"] | None = None


class ScanResult(BaseModel):
    result: Literal[
        "accepted",
        "rejected_zero_balance",
        "rejected_already_scanned",
        "rejected_unknown_code",
        "rejected_inactive",
    ]
    member_name: str | None = None
    member_type: str | None = None
    meal_type: str | None = None
    remaining_balance: int | None = None
    via_grace: bool = False  # true if this meal was only possible because of the grace allowance
    message: str


class ScanOut(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str = Field(alias="_id")
    member_id: str
    meal_type: str
    scanned_at: datetime
    result: str
    via_grace: bool = False
    reversed: bool = False
    reversed_at: datetime | None = None


class ReversalRequest(BaseModel):
    scan_id: str = Field(min_length=1)
    reversed_by: str = Field(min_length=1)
