"""Pydantic schemas for the billing milestones domain.

Create/Update schemas validate incoming request data.
Response schema inherits BaseResponseSchema.
"""

import uuid
from decimal import Decimal

from pydantic import BaseModel, Field

from app.core.base_schemas import BaseResponseSchema


class BillingMilestoneCreate(BaseModel):
    """Schema for creating a new billing milestone within a trade scope."""

    trade_scope_id: uuid.UUID
    name: str = Field(..., min_length=1, max_length=200)
    percentage: Decimal = Field(..., gt=0, le=100, decimal_places=2)
    description: str | None = None
    sort_order: int = Field(default=0, ge=0)


class BillingMilestoneUpdate(BaseModel):
    """Schema for updating an existing billing milestone.

    All fields are optional — only provided fields are updated.
    is_invoiced is NOT updatable via this schema (use mark_invoiced endpoint).
    """

    name: str | None = Field(default=None, min_length=1, max_length=200)
    percentage: Decimal | None = Field(default=None, gt=0, le=100, decimal_places=2)
    description: str | None = None
    sort_order: int | None = Field(default=None, ge=0)


class BillingMilestoneResponse(BaseResponseSchema):
    """Response schema for a billing milestone."""

    company_id: uuid.UUID
    trade_scope_id: uuid.UUID
    name: str
    percentage: Decimal
    description: str | None
    is_invoiced: bool
    sort_order: int

    @classmethod
    def from_model(cls, milestone: object) -> "BillingMilestoneResponse":
        """Build response from ORM instance using model_validate."""
        return cls.model_validate(milestone)
