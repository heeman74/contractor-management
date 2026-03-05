import uuid
from datetime import datetime

from pydantic import BaseModel


class CompanyCreate(BaseModel):
    """Schema for creating a new company."""

    name: str
    address: str | None = None
    phone: str | None = None
    business_number: str | None = None
    logo_url: str | None = None


class CompanyUpdate(BaseModel):
    """Schema for updating an existing company."""

    name: str | None = None
    address: str | None = None
    phone: str | None = None
    business_number: str | None = None
    logo_url: str | None = None


class CompanyResponse(BaseModel):
    """Schema for company API responses."""

    id: uuid.UUID
    name: str
    address: str | None
    phone: str | None
    business_number: str | None
    logo_url: str | None
    version: int
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
