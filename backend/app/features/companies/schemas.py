import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class CompanyCreate(BaseModel):
    """Schema for creating a new company.

    All fields except name are optional — company can be updated later.
    id is optional — when provided by the client (e.g., during sync), it is
    used as the UUID primary key enabling idempotent creates via ON CONFLICT DO NOTHING.
    """

    id: uuid.UUID | None = None
    name: str = Field(min_length=1)
    address: str | None = None
    phone: str | None = None
    trade_types: list[str] | None = None
    logo_url: str | None = None
    business_number: str | None = None


class CompanyUpdate(BaseModel):
    """Schema for partial update of an existing company.

    All fields are optional — only provided fields are updated.
    """

    name: str | None = Field(default=None, min_length=1)
    address: str | None = None
    phone: str | None = None
    trade_types: list[str] | None = None
    logo_url: str | None = None
    business_number: str | None = None


class CompanyResponse(BaseModel):
    """Schema for company API responses.

    Includes all fields plus server-generated id, version, and timestamps.
    deleted_at is included for tombstone propagation during delta sync.
    """

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    address: str | None
    phone: str | None
    trade_types: list[str] | None
    logo_url: str | None
    business_number: str | None
    version: int
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
