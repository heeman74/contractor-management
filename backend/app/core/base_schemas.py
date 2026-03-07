"""Base Pydantic response schemas with shared fields.

All new response schemas MUST inherit from BaseResponseSchema (non-tenant)
or TenantResponseSchema (tenant-scoped with company_id).
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class BaseResponseSchema(BaseModel):
    """Base response schema with id, version, and timestamps."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    version: int
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None


class TenantResponseSchema(BaseResponseSchema):
    """Response schema for tenant-scoped entities — adds company_id."""

    company_id: uuid.UUID
