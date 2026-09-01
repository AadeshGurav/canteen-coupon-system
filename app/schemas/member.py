from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class Balances(BaseModel):
    lunch: int = Field(default=0, ge=0)
    breakfast: int = Field(default=0, ge=0)
    brunch: int = Field(default=0, ge=0)


class MemberCreate(BaseModel):
    type: Literal["student", "staff"]
    name: str = Field(min_length=1)
    class_name: Optional[str] = None  # students only
    roll_number: Optional[str] = None  # students only
    staff_id: Optional[str] = None  # staff only
    balances: Balances = Balances()
    grace_allowance_override: Optional[int] = Field(default=None, ge=0)


class MemberUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1)
    class_name: Optional[str] = None
    roll_number: Optional[str] = None
    staff_id: Optional[str] = None
    status: Optional[Literal["active", "inactive"]] = None
    grace_allowance_override: Optional[int] = Field(default=None, ge=0)


class CreditUpdate(BaseModel):
    lunch_units: int = Field(default=0, ge=0)
    breakfast_units: int = Field(default=0, ge=0)
    brunch_units: int = Field(default=0, ge=0)


class MemberOut(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

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
