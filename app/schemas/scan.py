from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class ScanRequest(BaseModel):
    qr_code_id: str
    # meal_type is normally auto-detected from current time/day, but can be
    # overridden by the counter operator if needed (e.g. testing, edge cases)
    meal_type_override: Optional[Literal["lunch", "breakfast", "brunch"]] = None


class ScanResult(BaseModel):
    result: Literal[
        "accepted",
        "rejected_zero_balance",
        "rejected_already_scanned",
        "rejected_unknown_code",
        "rejected_inactive",
    ]
    member_name: Optional[str] = None
    member_type: Optional[str] = None
    meal_type: Optional[str] = None
    remaining_balance: Optional[int] = None
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
    reversed_at: Optional[datetime] = None


class ReversalRequest(BaseModel):
    scan_id: str
    reversed_by: str
