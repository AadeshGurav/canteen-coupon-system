from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class LoginRequest(BaseModel):
    username: str = Field(min_length=1)
    password: str = Field(min_length=1)


class LoginResponse(BaseModel):
    token: str
    username: str
    role: Literal["admin", "counter", "scanner"]


class UserCreate(BaseModel):
    username: str = Field(min_length=3, max_length=50, pattern=r"^[a-zA-Z0-9_.-]+$")
    password: str = Field(min_length=8)
    role: Literal["admin", "counter", "scanner"]


class UserUpdate(BaseModel):
    password: str | None = Field(default=None, min_length=8)
    role: Literal["admin", "counter", "scanner"] | None = None
    status: Literal["active", "inactive"] | None = None


class UserOut(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str = Field(alias="_id")
    username: str
    role: str
    status: str
    created_at: datetime
    updated_at: datetime
