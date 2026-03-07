"""Auth request/response schemas."""

import uuid

from pydantic import BaseModel, EmailStr, Field


class RegisterRequest(BaseModel):
    """Registration creates a company + admin user atomically."""

    email: EmailStr
    password: str = Field(min_length=8)
    company_name: str = Field(min_length=1)
    first_name: str | None = None
    last_name: str | None = None


class LoginRequest(BaseModel):
    """Email + password login."""

    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    """Refresh token exchange."""

    refresh_token: str


class TokenResponse(BaseModel):
    """Access + refresh token pair returned on login/register/refresh."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user_id: uuid.UUID
    company_id: uuid.UUID
    roles: list[str]
