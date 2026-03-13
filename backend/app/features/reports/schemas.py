"""Pydantic schemas for the reports and analytics domain.

All schemas are response-only — report data is computed from DB aggregations.
No create/update schemas needed for reports (read-only endpoints).

Dashboard endpoint returns a DashboardResponse combining all 4 metric types.
DateRangeFilter is used as query parameter schema across all report endpoints.
"""

from datetime import date
from decimal import Decimal

from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Query parameter schemas
# ---------------------------------------------------------------------------


class DateRangeFilter(BaseModel):
    """Query parameter schema for filtering reports by date range.

    Both fields are optional — omit for all-time aggregation.
    """

    start_date: date | None = Field(default=None, description="Inclusive start date")
    end_date: date | None = Field(default=None, description="Inclusive end date")


# ---------------------------------------------------------------------------
# Jobs by status
# ---------------------------------------------------------------------------


class JobsByStatusItem(BaseModel):
    """Count of jobs in each status bucket."""

    status: str
    count: int


# ---------------------------------------------------------------------------
# Revenue by month
# ---------------------------------------------------------------------------


class RevenueByMonthItem(BaseModel):
    """Monthly revenue totals split by invoice payment status.

    month: ISO month string (e.g. '2026-03')
    paid:   sum of invoice totals with status='paid'
    unpaid: sum of invoice totals with status='unpaid' or 'partially_paid'
    """

    month: str  # YYYY-MM format
    paid: Decimal = Decimal("0")
    unpaid: Decimal = Decimal("0")


# ---------------------------------------------------------------------------
# Contractor utilisation
# ---------------------------------------------------------------------------


class ContractorUtilizationItem(BaseModel):
    """Booked vs available hours per contractor in the reporting period.

    utilization_percent: booked_hours / available_hours * 100,
      capped at 100 to handle overtime bookings.
    """

    contractor_name: str
    booked_hours: Decimal = Decimal("0")
    available_hours: Decimal = Decimal("0")
    utilization_percent: Decimal = Decimal("0")


# ---------------------------------------------------------------------------
# Quote conversion funnel
# ---------------------------------------------------------------------------


class QuoteConversionItem(BaseModel):
    """Quote funnel: approved vs declined vs pending, plus conversion rate.

    conversion_rate: approved / (approved + declined) * 100
      Returns 0 when no quotes have been resolved.
    """

    approved: int = 0
    declined: int = 0
    pending: int = 0
    conversion_rate: Decimal = Decimal("0")


# ---------------------------------------------------------------------------
# Dashboard aggregate response
# ---------------------------------------------------------------------------


class DashboardResponse(BaseModel):
    """Combined dashboard response with all 4 metric groups.

    All sub-fields default to empty / zero — callers can rely on a
    fully-populated response even when the tenant has no data yet.
    """

    jobs_by_status: list[JobsByStatusItem] = Field(default_factory=list)
    revenue_by_month: list[RevenueByMonthItem] = Field(default_factory=list)
    contractor_utilization: list[ContractorUtilizationItem] = Field(default_factory=list)
    quote_conversion: QuoteConversionItem = Field(default_factory=QuoteConversionItem)
