"""Pydantic schemas for the foreman role feature.

Request schemas use BaseModel (no id/timestamps — those come from the DB).
Response schemas inherit TenantResponseSchema (id, version, timestamps, company_id).
"""

from __future__ import annotations

import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field

from app.core.base_schemas import TenantResponseSchema

# ---------------------------------------------------------------------------
# Project Assignment schemas
# ---------------------------------------------------------------------------


class ProjectAssignmentCreate(BaseModel):
    """Schema for assigning a foreman to a project."""

    project_id: uuid.UUID
    user_id: uuid.UUID
    role: str = "foreman"


class ProjectAssignmentResponse(TenantResponseSchema):
    """Response schema for a project assignment.

    Includes denormalized project_name and user_name for display.
    """

    project_id: uuid.UUID
    user_id: uuid.UUID
    role: str
    assigned_at: datetime

    # Denormalized fields populated by the service layer
    project_name: str = ""
    user_name: str = ""


# ---------------------------------------------------------------------------
# Status Update schemas
# ---------------------------------------------------------------------------


class StatusUpdateCreate(BaseModel):
    """Schema for creating a daily status update."""

    project_id: uuid.UUID
    status_text: str = Field(..., min_length=1)
    weather_conditions: str | None = None
    workers_on_site: int | None = Field(default=None, ge=0)
    safety_incidents: int = Field(default=0, ge=0)
    blockers: str | None = None
    photos: list[str] = Field(default_factory=list)
    report_date: date | None = None


class StatusUpdateResponse(TenantResponseSchema):
    """Response schema for a project status update.

    Includes denormalized author_name for display.
    """

    project_id: uuid.UUID
    author_id: uuid.UUID
    status_text: str
    weather_conditions: str | None
    workers_on_site: int | None
    safety_incidents: int
    blockers: str | None
    photos: list[str]
    report_date: date

    # Denormalized field populated by the service layer
    author_name: str = ""


class StatusUpdateListResponse(BaseModel):
    """Paginated list of status updates."""

    model_config = ConfigDict(from_attributes=True)

    items: list[StatusUpdateResponse]
    total: int
    limit: int
    offset: int
