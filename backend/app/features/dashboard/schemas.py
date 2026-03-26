"""Pydantic schemas for dashboard API responses."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Any

from pydantic import BaseModel

from app.core.base_schemas import TenantResponseSchema


class AlertResponse(TenantResponseSchema):
    """Full dashboard alert response."""

    project_id: uuid.UUID
    trade_scope_id: uuid.UUID | None = None
    severity: str
    alert_type: str
    days_behind: int | None = None
    impact_text: str
    remediation_text: str | None = None
    affected_scope_ids: list[Any] = []
    is_read: bool
    rescheduling_payload: dict | None = None
    rescheduling_accepted: bool | None = None


class TradeStatusBadge(BaseModel):
    """Per-trade status summary within a project status card.

    status:
    - 'blocked': at least one task has status='blocked'
    - 'at_risk': at least one task is past its due_date and not complete
    - 'on_track': all tasks within schedule
    """

    trade_scope_id: uuid.UUID
    trade_name: str
    status: str  # 'on_track' | 'at_risk' | 'blocked'
    completion_pct: float
    task_count: int
    completed_count: int


class ProjectStatusCard(BaseModel):
    """Aggregated project status for the GC dashboard overview.

    Provides all the data needed to render a project card with per-trade badges
    and an alert count badge without additional API calls.
    """

    project_id: uuid.UUID
    project_name: str
    status: str
    overall_completion_pct: float
    trade_statuses: list[TradeStatusBadge]
    active_alert_count: int


class TradeTaskDetail(BaseModel):
    """Full task detail within a trade scope drill-down view.

    dependency_status: 'clear' | 'blocked' | 'waiting'
    """

    task_id: uuid.UUID
    title: str
    status: str
    assignee_name: str | None = None
    start_date: date | None = None
    due_date: date | None = None
    dependency_status: str = "clear"


class TradeTimelineScope(BaseModel):
    """A single trade scope entry in the project Gantt/timeline view."""

    trade_scope_id: uuid.UUID
    trade_name: str
    contractor_id: uuid.UUID | None = None
    start_date: date | None = None
    end_date: date | None = None
    progress_pct: float
    task_count: int
    completed_count: int


class DependencyLink(BaseModel):
    """Cross-scope dependency link for Gantt visualization."""

    from_scope_id: uuid.UUID
    to_scope_id: uuid.UUID
    dependency_type: str = "FS"


class TradeTimelineResponse(BaseModel):
    """Full project timeline data for Gantt chart rendering."""

    project_id: uuid.UUID
    project_name: str
    scopes: list[TradeTimelineScope]
    dependency_links: list[DependencyLink]
