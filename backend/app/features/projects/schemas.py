"""Pydantic schemas for the v3.0 project data model.

Covers: Project, TradeCatalog, TradeScope, Task, TaskAttachment, UserTradeSpecialty.

Design notes:
- All response schemas inherit TenantResponseSchema (id, company_id, version, timestamps)
  per CLAUDE.md OOP Architecture rules.
- Create/Update schemas follow the same pattern as jobs/schemas.py.
- Status enums use StrEnum for type-safe comparisons and OpenAPI generation.
- Decimal fields (estimated_hours, estimated_cost) use Python Decimal for precision.
"""

from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, Field

from app.core.base_schemas import TenantResponseSchema

# ---------------------------------------------------------------------------
# Status Enums
# ---------------------------------------------------------------------------


class ProjectStatus(StrEnum):
    """Valid values for Project.status state machine."""

    draft = "draft"
    planning = "planning"
    active = "active"
    on_hold = "on_hold"
    complete = "complete"
    archived = "archived"


class TradeScopeStatus(StrEnum):
    """Valid values for TradeScope.status."""

    not_started = "not_started"
    in_progress = "in_progress"
    complete = "complete"
    approved = "approved"


class TaskStatus(StrEnum):
    """Valid values for Task.status."""

    not_started = "not_started"
    in_progress = "in_progress"
    complete = "complete"
    blocked = "blocked"


class TaskPriority(StrEnum):
    """Valid values for Task.priority."""

    low = "low"
    medium = "medium"
    high = "high"
    urgent = "urgent"


class AttachmentType(StrEnum):
    """Valid values for TaskAttachment.attachment_type."""

    photo = "photo"
    video = "video"
    document = "document"


# ---------------------------------------------------------------------------
# Project schemas
# ---------------------------------------------------------------------------


class ProjectCreate(BaseModel):
    """Schema for creating a new project."""

    name: str = Field(min_length=1, max_length=200)
    description: str | None = None
    address: str | None = None
    client_id: uuid.UUID | None = None
    target_start_date: date | None = None
    target_end_date: date | None = None


class ProjectUpdate(BaseModel):
    """Schema for updating an existing project (all fields optional for PATCH semantics)."""

    name: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    address: str | None = None
    client_id: uuid.UUID | None = None
    target_start_date: date | None = None
    target_end_date: date | None = None
    status: str | None = None


class ProjectResponse(TenantResponseSchema):
    """Response schema for Project entities."""

    name: str
    description: str | None = None
    address: str | None = None
    client_id: uuid.UUID | None = None
    target_start_date: date | None = None
    target_end_date: date | None = None
    status: str
    status_history: list[Any] = []


# ---------------------------------------------------------------------------
# TradeCatalog schemas
# ---------------------------------------------------------------------------


class TradeCatalogCreate(BaseModel):
    """Schema for creating a new trade catalog entry."""

    name: str = Field(min_length=1, max_length=100)
    color: str = "#9E9E9E"


class TradeCatalogUpdate(BaseModel):
    """Schema for updating a trade catalog entry."""

    name: str | None = Field(default=None, min_length=1, max_length=100)
    color: str | None = None


class TradeCatalogResponse(TenantResponseSchema):
    """Response schema for TradeCatalog entities."""

    name: str
    color: str


# ---------------------------------------------------------------------------
# TradeScope schemas
# ---------------------------------------------------------------------------


class TradeScopeCreate(BaseModel):
    """Schema for creating a new trade scope on a project."""

    project_id: uuid.UUID
    trade_catalog_id: uuid.UUID | None = None
    trade_name: str = Field(min_length=1)
    trade_color: str = "#9E9E9E"
    contractor_id: uuid.UUID | None = None


class TradeScopeUpdate(BaseModel):
    """Schema for updating a trade scope (all fields optional for PATCH semantics)."""

    trade_name: str | None = None
    trade_color: str | None = None
    contractor_id: uuid.UUID | None = None
    status: str | None = None
    status_override: bool | None = None
    sort_order: int | None = None


class TradeScopeResponse(TenantResponseSchema):
    """Response schema for TradeScope entities."""

    project_id: uuid.UUID
    trade_catalog_id: uuid.UUID | None = None
    trade_name: str
    trade_color: str
    contractor_id: uuid.UUID | None = None
    status: str
    status_override: bool
    sort_order: int


# ---------------------------------------------------------------------------
# Task schemas
# ---------------------------------------------------------------------------


class TaskCreate(BaseModel):
    """Schema for creating a new task within a trade scope."""

    trade_scope_id: uuid.UUID
    title: str = Field(min_length=1, max_length=300)
    description: str | None = None
    priority: str = "medium"
    estimated_hours: Decimal | None = None
    estimated_cost: Decimal | None = None
    due_date: date | None = None
    photo_required: bool = False
    assigned_to: uuid.UUID | None = None
    materials_needed: list[dict[str, Any]] = []
    depends_on: list[str] = []


class TaskUpdate(BaseModel):
    """Schema for updating a task (all fields optional for PATCH semantics)."""

    title: str | None = Field(default=None, min_length=1, max_length=300)
    description: str | None = None
    status: str | None = None
    priority: str | None = None
    estimated_hours: Decimal | None = None
    estimated_cost: Decimal | None = None
    due_date: date | None = None
    photo_required: bool | None = None
    assigned_to: uuid.UUID | None = None
    materials_needed: list[dict[str, Any]] | None = None
    depends_on: list[str] | None = None
    sort_order: int | None = None


class TaskResponse(TenantResponseSchema):
    """Response schema for Task entities."""

    trade_scope_id: uuid.UUID
    title: str
    description: str | None = None
    status: str
    sort_order: int
    priority: str
    estimated_hours: Decimal | None = None
    estimated_cost: Decimal | None = None
    due_date: date | None = None
    photo_required: bool
    assigned_to: uuid.UUID | None = None
    materials_needed: list[Any] = []
    depends_on: list[Any] = []


# ---------------------------------------------------------------------------
# TaskAttachment schemas
# ---------------------------------------------------------------------------


class TaskAttachmentCreate(BaseModel):
    """Schema for creating a new task attachment."""

    task_id: uuid.UUID
    attachment_type: str
    remote_url: str | None = None
    local_path: str | None = None
    caption: str | None = None


class TaskAttachmentUpdate(BaseModel):
    """Schema for updating a task attachment."""

    caption: str | None = None
    sort_order: int | None = None


class TaskAttachmentResponse(TenantResponseSchema):
    """Response schema for TaskAttachment entities."""

    task_id: uuid.UUID
    attachment_type: str
    remote_url: str | None = None
    local_path: str | None = None
    caption: str | None = None
    sort_order: int


# ---------------------------------------------------------------------------
# UserTradeSpecialty schemas
# ---------------------------------------------------------------------------


class UserTradeSpecialtyCreate(BaseModel):
    """Schema for creating a new user trade specialty."""

    user_id: uuid.UUID
    trade_catalog_id: uuid.UUID


class UserTradeSpecialtyResponse(TenantResponseSchema):
    """Response schema for UserTradeSpecialty entities."""

    user_id: uuid.UUID
    trade_catalog_id: uuid.UUID
