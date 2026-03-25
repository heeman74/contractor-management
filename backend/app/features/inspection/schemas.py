"""Pydantic schemas for the GC Inspection Workflow.

Request and response schemas for:
- TaskInspection (approve/reject a task)
- SiteWalkFlag (flag an issue during site walk)
- PunchListItem (defect item creation, update, and listing)
- ConvertFlag (convert a flag to a punch list item)

All response schemas inherit TenantResponseSchema per CLAUDE.md OOP Architecture rules.
"""

from __future__ import annotations

import uuid
from datetime import date
from typing import Literal

from pydantic import BaseModel, Field

from app.core.base_schemas import TenantResponseSchema

# ---------------------------------------------------------------------------
# Request schemas
# ---------------------------------------------------------------------------


class InspectTaskRequest(BaseModel):
    """Request body for POST /tasks/{task_id}/inspect."""

    decision: Literal["approved", "rejected"]
    checklist_results: list[dict] = Field(
        default_factory=list,
        description="Array of checklist results: [{item: str, checked: bool}]",
    )
    rejection_reason: str | None = None
    rejection_comment: str | None = None
    rejection_photo_url: str | None = None


class CreateSiteWalkFlagRequest(BaseModel):
    """Request body for POST /projects/{project_id}/flags."""

    description: str = Field(min_length=1)
    severity: Literal["low", "medium", "high"] = "medium"
    location_label: str | None = None
    photo_url: str | None = None
    annotation_data: dict | None = None


class ConvertFlagRequest(BaseModel):
    """Request body for PATCH /flags/{flag_id}/convert."""

    trade_scope_id: uuid.UUID
    priority: Literal["low", "medium", "high", "urgent"] = "medium"
    assigned_to: uuid.UUID | None = None
    due_date: date | None = None


class CreatePunchListItemRequest(BaseModel):
    """Request body for POST /projects/{project_id}/punch-items."""

    trade_scope_id: uuid.UUID
    description: str = Field(min_length=1)
    priority: Literal["low", "medium", "high", "urgent"] = "medium"
    assigned_to: uuid.UUID | None = None
    photo_url: str | None = None
    annotation_data: dict | None = None
    due_date: date | None = None


class UpdatePunchListItemRequest(BaseModel):
    """Request body for PATCH /punch-items/{item_id}."""

    status: Literal["open", "in_progress", "resolved", "verified"] | None = None
    description: str | None = None
    priority: Literal["low", "medium", "high", "urgent"] | None = None
    assigned_to: uuid.UUID | None = None
    due_date: date | None = None


# ---------------------------------------------------------------------------
# Response schemas
# ---------------------------------------------------------------------------


class TaskInspectionResponse(TenantResponseSchema):
    """Response schema for TaskInspection."""

    task_id: uuid.UUID
    inspector_id: uuid.UUID
    decision: str
    checklist_results: list
    rejection_reason: str | None = None
    rejection_comment: str | None = None
    rejection_photo_url: str | None = None


class SiteWalkFlagResponse(TenantResponseSchema):
    """Response schema for SiteWalkFlag."""

    project_id: uuid.UUID
    flagged_by: uuid.UUID
    description: str
    severity: str
    location_label: str | None = None
    photo_url: str | None = None
    annotation_data: dict | None = None
    status: str


class PunchListItemResponse(TenantResponseSchema):
    """Response schema for PunchListItem."""

    project_id: uuid.UUID
    trade_scope_id: uuid.UUID
    created_by: uuid.UUID
    assigned_to: uuid.UUID | None = None
    description: str
    priority: str
    status: str
    photo_url: str | None = None
    annotation_data: dict | None = None
    source_flag_id: uuid.UUID | None = None
    due_date: date | None = None
