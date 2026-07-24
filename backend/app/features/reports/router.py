"""Reports API router — REST endpoints for the reporting dashboard.

Endpoints:
  GET /reports/dashboard    — full dashboard metrics (admin only)
  GET /reports/contractor   — contractor's own stats (admin or contractor)

Design notes:
- Plain APIRouter (not CRUDRouter) — read-only aggregate queries.
- start_date / end_date are optional query params (ISO date strings).
- Admin gets all 4 metrics. Contractor gets own utilization and job counts.
- RLS automatically scopes all aggregate queries to the current tenant.
"""

from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user, require_admin, require_roles
from app.features.reports.schemas import DashboardResponse, UtilizationHeatmapResponse
from app.features.reports.service import ReportingService

# isort: split
# Side-effect imports: ensure related mappers registered before aggregate queries.
import app.features.invoices.models
import app.features.quotes.models
import app.features.scheduling.models
import app.features.users.models  # noqa: F401

router = APIRouter(prefix="/reports", tags=["reports"])


@router.get("/dashboard", response_model=DashboardResponse)
async def get_dashboard(
    start_date: date | None = Query(default=None, description="Inclusive start date (YYYY-MM-DD)"),
    end_date: date | None = Query(default=None, description="Inclusive end date (YYYY-MM-DD)"),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> DashboardResponse:
    """Return all 4 dashboard metrics for the current tenant (admin only).

    Metrics:
    1. jobs_by_status: COUNT of non-deleted jobs per status
    2. revenue_by_month: Monthly totals split by paid vs unpaid invoices
    3. contractor_utilization: Booked hours vs available hours per contractor
    4. quote_conversion: Approved / (approved + declined) funnel
    """
    require_admin(current_user)

    svc = ReportingService(db)
    return await svc.get_dashboard(
        company_id=current_user.company_id,
        start_date=start_date,
        end_date=end_date,
    )


@router.get("/utilization-heatmap", response_model=UtilizationHeatmapResponse)
async def get_utilization_heatmap(
    start_date: date | None = Query(default=None, description="Inclusive start date (YYYY-MM-DD)"),
    end_date: date | None = Query(default=None, description="Inclusive end date (YYYY-MM-DD)"),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> UtilizationHeatmapResponse:
    """Return per-contractor-per-week utilization heatmap data (admin only).

    Grid: ISO week column headers + one row per contractor.
    Contractors with zero bookings still appear — zero-filled week items.
    Available hours fixed at 40h/week. Utilization capped at 100%.
    """
    require_admin(current_user)

    svc = ReportingService(db)
    return await svc.get_utilization_heatmap(
        company_id=current_user.company_id,
        start_date=start_date,
        end_date=end_date,
    )


@router.get("/contractor", response_model=DashboardResponse)
async def get_contractor_stats(
    start_date: date | None = Query(default=None, description="Inclusive start date (YYYY-MM-DD)"),
    end_date: date | None = Query(default=None, description="Inclusive end date (YYYY-MM-DD)"),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> DashboardResponse:
    """Return a contractor's own utilization and job count stats.

    Accessible by contractor role. Revenue data is not included.
    Admin may also call this endpoint to view any contractor's stats (uses own ID).
    """
    require_roles(current_user, "contractor", "admin", detail="Contractor or admin role required")

    svc = ReportingService(db)
    return await svc.get_contractor_stats(
        contractor_id=current_user.user_id,
        start_date=start_date,
        end_date=end_date,
    )
