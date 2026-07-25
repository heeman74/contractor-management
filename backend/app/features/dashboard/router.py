"""Dashboard REST API endpoints.

GET  /api/v1/dashboard                                       — project status cards
GET  /api/v1/dashboard/projects/{project_id}/timeline        — Gantt timeline data
GET  /api/v1/dashboard/projects/{project_id}/trades/{trade_scope_id}/tasks  — trade task list
GET  /api/v1/dashboard/alerts                                — unread alerts (optional ?project_id)
POST /api/v1/dashboard/alerts/{alert_id}/read               — mark alert as read
POST /api/v1/dashboard/alerts/{alert_id}/accept             — accept rescheduling suggestion
POST /api/v1/dashboard/alerts/{alert_id}/dismiss            — dismiss alert without applying

All endpoints require authentication. RLS enforces tenant isolation automatically.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_service import entity_or_404
from app.core.database import get_db
from app.core.security import CurrentUser, effective_permissions, get_current_user
from app.features.dashboard.schemas import (
    AlertResponse,
    ProjectStatusCard,
    TradeTaskDetail,
    TradeTimelineResponse,
)
from app.features.dashboard.service import DashboardService

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("", response_model=list[ProjectStatusCard])
async def get_dashboard(
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[ProjectStatusCard]:
    """Return status cards for all active projects in the current company.

    Each card includes per-trade status badges and an alert count.
    """
    svc = DashboardService(db)
    return await svc.get_project_status_cards(company_id=current_user.company_id)


@router.get(
    "/projects/{project_id}/timeline",
    response_model=TradeTimelineResponse,
)
async def get_project_timeline(
    project_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> TradeTimelineResponse:
    """Return Gantt-ready timeline data for a project.

    Includes per-scope start/end dates, progress, and cross-scope dependency links.
    Returns a response with empty scopes if project not found (RLS enforces tenant scope).
    """
    svc = DashboardService(db)
    return await svc.get_trade_timeline(project_id=project_id)


@router.get(
    "/projects/{project_id}/trades/{trade_scope_id}/tasks",
    response_model=list[TradeTaskDetail],
)
async def get_trade_tasks(
    project_id: uuid.UUID,
    trade_scope_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[TradeTaskDetail]:
    """Return full task list for a trade scope drill-down view.

    Validates that the trade scope belongs to the specified project.
    RLS ensures the trade scope belongs to the current tenant.
    """
    svc = DashboardService(db)
    return await svc.get_trade_tasks(trade_scope_id=trade_scope_id, project_id=project_id)


@router.get("/alerts", response_model=list[AlertResponse])
async def get_alerts(
    project_id: uuid.UUID | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[AlertResponse]:
    """Return alerts for the current company, optionally filtered by project.

    Without ?project_id: returns all unread alerts across the company.
    With ?project_id=...: returns all alerts for that specific project (read + unread).
    """
    svc = DashboardService(db)
    granted = await effective_permissions(current_user, db)
    alerts = await svc.get_alerts(project_id=project_id, has_finance_view="finance.view" in granted)
    return [AlertResponse.model_validate(a) for a in alerts]


@router.post("/alerts/{alert_id}/read", response_model=AlertResponse)
async def mark_alert_read(
    alert_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> AlertResponse:
    """Mark an alert as read."""
    svc = DashboardService(db)
    alert = entity_or_404(await svc.mark_alert_read(alert_id), "Alert not found")
    return AlertResponse.model_validate(alert)


@router.post("/alerts/{alert_id}/accept", response_model=AlertResponse)
async def accept_rescheduling(
    alert_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> AlertResponse:
    """Accept the AI rescheduling suggestion — updates task dates from rescheduling_payload."""
    svc = DashboardService(db)
    alert = entity_or_404(await svc.accept_rescheduling(alert_id), "Alert not found")
    return AlertResponse.model_validate(alert)


@router.post("/alerts/{alert_id}/dismiss", response_model=AlertResponse)
async def dismiss_alert(
    alert_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> AlertResponse:
    """Dismiss an alert without applying rescheduling changes."""
    svc = DashboardService(db)
    alert = entity_or_404(await svc.dismiss_alert(alert_id), "Alert not found")
    return AlertResponse.model_validate(alert)
