from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field


class Balances(BaseModel):
    lunch: int = 0
    breakfast: int = 0
    brunch: int = 0


class MemberCreate(BaseModel):
    type: Literal["student", "staff"]
    name: str
    class_name: Optional[str] = None      # students only
    roll_number: Optional[str] = None     # students only
    staff_id: Optional[str] = None        # staff only
    balances: Balances = Balances()
    grace_allowance_override: Optional[int] = None


class MemberUpdate(BaseModel):
    name: Optional[str] = None
    class_name: Optional[str] = None
    roll_number: Optional[str] = None
    staff_id: Optional[str] = None
    status: Optional[Literal["active", "inactive"]] = None
    grace_allowance_override: Optional[int] = None


class CreditUpdate(BaseModel):
    lunch_units: int = 0
    breakfast_units: int = 0
    brunch_units: int = 0


class MemberOut(BaseModel):
    id: str = Field(alias="_id")
    type: str
    name: str
    class_name: Optional[str] = None
    roll_number: Optional[str] = None
    staff_id: Optional[str] = None
    qr_code_id: str
    balances: Balances
    grace_allowance_override: Optional[int] = None
    status: str
    created_at: datetime
    updated_at: datetime

    class Config:
        populate_by_name = True
