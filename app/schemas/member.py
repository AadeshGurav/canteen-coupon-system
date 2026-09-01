from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Balances(BaseModel):
    lunch: int = Field(default=0, ge=0)
    breakfast: int = Field(default=0, ge=0)
    brunch: int = Field(default=0, ge=0)


def validate_type_specific_fields(member_type: str | None, class_name, roll_number, staff_id) -> None:
    """docs/PRD.md §4: student/staff are one entity type distinguished by
    `type`, with a couple of type-specific fields — not a free-for-all where
    a student could be saved with a staff_id, or vice versa."""
    if member_type == "student" and staff_id:
        raise ValueError("staff_id should not be set for a student member.")
    if member_type == "staff" and (class_name or roll_number):
        raise ValueError("class_name/roll_number should not be set for a staff member.")


class MemberCreate(BaseModel):
    type: Literal["student", "staff"]
    name: str = Field(min_length=1)
    class_name: str | None = None  # students only
    roll_number: str | None = None  # students only
    staff_id: str | None = None  # staff only
    balances: Balances = Balances()
    grace_allowance_override: int | None = Field(default=None, ge=0)

    @model_validator(mode="after")
    def _validate_type_specific_fields(self) -> "MemberCreate":
        validate_type_specific_fields(self.type, self.class_name, self.roll_number, self.staff_id)
        return self


class MemberUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1)
    class_name: str | None = None
    roll_number: str | None = None
    staff_id: str | None = None
    status: Literal["active", "inactive"] | None = None
    grace_allowance_override: int | None = Field(default=None, ge=0)


class CreditUpdate(BaseModel):
    lunch_units: int = Field(default=0, ge=0)
    breakfast_units: int = Field(default=0, ge=0)
    brunch_units: int = Field(default=0, ge=0)


class MemberOut(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str = Field(alias="_id")
    type: str
    name: str
    class_name: str | None = None
    roll_number: str | None = None
    staff_id: str | None = None
    qr_code_id: str
    balances: Balances
    grace_allowance_override: int | None = None
    status: str
    created_at: datetime
    updated_at: datetime
