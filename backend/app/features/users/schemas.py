import uuid
from datetime import datetime
from enum import Enum

from pydantic import BaseModel


class UserRoleEnum(str, Enum):
    """Valid user roles."""

    admin = "admin"
    contractor = "contractor"
    client = "client"


class UserCreate(BaseModel):
    """Schema for creating a new user."""

    company_id: uuid.UUID
    email: str
    first_name: str | None = None
    last_name: str | None = None
    phone: str | None = None


class UserResponse(BaseModel):
    """Schema for user API responses."""

    id: uuid.UUID
    company_id: uuid.UUID
    email: str
    first_name: str | None
    last_name: str | None
    phone: str | None
    version: int
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class UserRoleCreate(BaseModel):
    """Schema for assigning a role to a user."""

    user_id: uuid.UUID
    company_id: uuid.UUID
    role: UserRoleEnum


class UserRoleResponse(BaseModel):
    """Schema for user role API responses."""

    id: uuid.UUID
    user_id: uuid.UUID
    company_id: uuid.UUID
    role: UserRoleEnum
    created_at: datetime

    model_config = {"from_attributes": True}
