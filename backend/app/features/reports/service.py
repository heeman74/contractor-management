"""ReportingService — aggregate query service for the reporting dashboard.

Implements the 4 dashboard metrics:
1. jobs_by_status: COUNT(*) GROUP BY status for jobs in a date range
2. revenue_by_month: SUM of invoice totals split by paid vs unpaid, grouped by month
3. contractor_utilization: booked hours vs available hours per contractor
4. quote_conversion: approved / (approved + declined) conversion rate

Additionally provides:
- get_contractor_stats: limited view for contractor role (own data only)

All queries use aggregate SQLAlchemy expressions to avoid N+1 queries.
No ORM relationship lazy loading — raw aggregate queries only.

CLAUDE.md rules:
- No db.commit() — get_db handles transaction lifecycle
- NEVER query inside a loop — all data fetched in bulk aggregate queries
"""

from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import and_, case, cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.types import Numeric

from app.features.invoices.models import Invoice
from app.features.jobs.models import Job
from app.features.quotes.models import Quote
from app.features.reports.schemas import (
    ContractorUtilizationItem,
    DashboardResponse,
    JobsByStatusItem,
    QuoteConversionItem,
    RevenueByMonthItem,
    UtilizationHeatmapContractor,
    UtilizationHeatmapResponse,
    UtilizationWeekItem,
)
from app.features.scheduling.models import Booking
from app.features.users.models import User
from app.features.users.models import UserRole as UserRoleModel


class ReportingService:
    """Aggregate reporting service. Not a TenantScopedService — uses RLS directly."""

    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    # -------------------------------------------------------------------------
    # Helper: date range WHERE conditions
    # -------------------------------------------------------------------------

    @staticmethod
    def _date_conditions(column, start_date: date | None, end_date: date | None) -> list:
        """Return SQLAlchemy WHERE conditions for an optional date range."""
        conditions = []
        if start_date is not None:
            # Compare date part of timestamp with start_date
            conditions.append(func.date(column) >= start_date)
        if end_date is not None:
            conditions.append(func.date(column) <= end_date)
        return conditions

    # -------------------------------------------------------------------------
    # Metric 1: Jobs by status
    # -------------------------------------------------------------------------

    async def _get_jobs_by_status(
        self,
        start_date: date | None,
        end_date: date | None,
    ) -> list[JobsByStatusItem]:
        """Count non-deleted jobs per status in the date range."""
        conditions = [Job.deleted_at.is_(None)]
        conditions.extend(self._date_conditions(Job.created_at, start_date, end_date))

        result = await self.db.execute(
            select(Job.status, func.count().label("count"))
            .where(*conditions)
            .group_by(Job.status)
            .order_by(Job.status)
        )
        return [JobsByStatusItem(status=row.status, count=row.count) for row in result.all()]

    # -------------------------------------------------------------------------
    # Metric 2: Revenue by month
    # -------------------------------------------------------------------------

    async def _get_revenue_by_month(
        self,
        start_date: date | None,
        end_date: date | None,
    ) -> list[RevenueByMonthItem]:
        """Monthly revenue split by paid vs unpaid, from invoices.

        Revenue is approximated as SUM(line item totals) per invoice.
        This avoids storing a computed total column — consistent with
        from_orm_with_totals() approach in schemas.

        For performance in the aggregate query, we compute a simplified total:
        SUM(quantity * unit_price) — without discount/tax.
        The full total (with discount/tax) is available per-invoice but requires
        joining invoice_line_items in the aggregate.
        """
        from app.features.invoices.models import InvoiceLineItem

        conditions = [Invoice.deleted_at.is_(None)]
        conditions.extend(self._date_conditions(Invoice.issued_at, start_date, end_date))

        month_expr = func.to_char(Invoice.issued_at, "YYYY-MM").label("month")
        paid_total = func.sum(
            case(
                (Invoice.status == "paid", InvoiceLineItem.quantity * InvoiceLineItem.unit_price),
                else_=cast(0, Numeric),
            )
        ).label("paid")
        unpaid_total = func.sum(
            case(
                (Invoice.status != "paid", InvoiceLineItem.quantity * InvoiceLineItem.unit_price),
                else_=cast(0, Numeric),
            )
        ).label("unpaid")

        result = await self.db.execute(
            select(month_expr, paid_total, unpaid_total)
            .join(InvoiceLineItem, InvoiceLineItem.invoice_id == Invoice.id)
            .where(*conditions)
            .group_by(month_expr)
            .order_by(month_expr)
        )

        rows = result.all()
        return [
            RevenueByMonthItem(
                month=row.month,
                paid=Decimal(str(row.paid or 0)).quantize(Decimal("0.01")),
                unpaid=Decimal(str(row.unpaid or 0)).quantize(Decimal("0.01")),
            )
            for row in rows
        ]

    # -------------------------------------------------------------------------
    # Metric 3: Contractor utilization
    # -------------------------------------------------------------------------

    async def _get_contractor_utilization(
        self,
        start_date: date | None,
        end_date: date | None,
    ) -> list[ContractorUtilizationItem]:
        """Booked hours vs available hours per contractor.

        Booked hours: SUM of booking durations (from bookings table).
        Available hours: 8 hours/day * workdays in date range (simplified).
        Utilization: booked_hours / available_hours * 100, capped at 100.
        """
        # Build date range for available hours calculation
        if start_date is not None and end_date is not None:
            delta_days = (end_date - start_date).days + 1
            # Approximate workdays as 5/7 of total days
            workdays = max(1, int(delta_days * 5 / 7))
            available_hours_each = Decimal(str(workdays * 8))
        else:
            # Default: last 30 days ≈ 21 workdays * 8h = 168h
            available_hours_each = Decimal("168")

        # Build booking conditions
        # Booking uses TSTZRANGE (time_range); lower() extracts start timestamp.
        booking_conditions = [Booking.deleted_at.is_(None)]
        if start_date is not None:
            booking_conditions.append(func.date(func.lower(Booking.time_range)) >= start_date)
        if end_date is not None:
            booking_conditions.append(func.date(func.lower(Booking.time_range)) <= end_date)

        # SUM of booking durations per contractor.
        # EXTRACT(EPOCH FROM upper(time_range) - lower(time_range)) gives seconds;
        # divide by 3600 to get hours.
        duration_hours_expr = func.extract(
            "epoch",
            func.upper(Booking.time_range) - func.lower(Booking.time_range),
        ) / cast(3600, Numeric)
        booked_hours_expr = func.coalesce(
            func.sum(duration_hours_expr),
            cast(0, Numeric),
        ).label("booked_hours")

        # COALESCE handles NULL first_name/last_name (nullable columns).
        # Filter to users with contractor role via join on user_roles.
        contractor_name_expr = (
            func.coalesce(User.first_name, "") + " " + func.coalesce(User.last_name, "")
        ).label("contractor_name")
        result = await self.db.execute(
            select(
                User.id.label("contractor_id"),
                contractor_name_expr,
                booked_hours_expr,
            )
            .join(
                UserRoleModel,
                (UserRoleModel.user_id == User.id) & (UserRoleModel.role == "contractor"),
            )
            .join(Booking, Booking.contractor_id == User.id, isouter=True)
            .where(
                User.deleted_at.is_(None),
                UserRoleModel.deleted_at.is_(None),
            )
            .where(*booking_conditions if booking_conditions else [])
            .group_by(User.id, User.first_name, User.last_name)
            .order_by(User.first_name, User.last_name)
        )

        items = []
        for row in result.all():
            booked = Decimal(str(row.booked_hours or 0))
            util_pct = min(
                Decimal("100"),
                (booked / available_hours_each * Decimal("100")).quantize(Decimal("0.01"))
                if available_hours_each > 0
                else Decimal("0"),
            )
            items.append(
                ContractorUtilizationItem(
                    contractor_name=row.contractor_name,
                    booked_hours=booked.quantize(Decimal("0.01")),
                    available_hours=available_hours_each,
                    utilization_percent=util_pct,
                )
            )
        return items

    # -------------------------------------------------------------------------
    # Metric 4: Quote conversion
    # -------------------------------------------------------------------------

    async def _get_quote_conversion(
        self,
        start_date: date | None,
        end_date: date | None,
    ) -> QuoteConversionItem:
        """Quote funnel: approved / declined / pending counts and conversion rate."""
        conditions = [Quote.deleted_at.is_(None)]
        conditions.extend(self._date_conditions(Quote.created_at, start_date, end_date))

        approved_expr = func.count(case((Quote.status == "approved", 1))).label("approved")
        declined_expr = func.count(case((Quote.status == "declined", 1))).label("declined")
        pending_expr = func.count(case((Quote.status.in_(["sent", "viewed"]), 1))).label("pending")

        result = await self.db.execute(
            select(approved_expr, declined_expr, pending_expr).where(*conditions)
        )
        row = result.one()

        approved = row.approved or 0
        declined = row.declined or 0
        pending = row.pending or 0
        resolved = approved + declined
        conversion_rate = (
            (Decimal(str(approved)) / Decimal(str(resolved)) * Decimal("100")).quantize(
                Decimal("0.01")
            )
            if resolved > 0
            else Decimal("0")
        )

        return QuoteConversionItem(
            approved=approved,
            declined=declined,
            pending=pending,
            conversion_rate=conversion_rate,
        )

    # -------------------------------------------------------------------------
    # Public API
    # -------------------------------------------------------------------------

    async def get_dashboard(
        self,
        company_id: uuid.UUID,
        start_date: date | None,
        end_date: date | None,
    ) -> DashboardResponse:
        """Return all 4 dashboard metrics for the given tenant and date range.

        Executes 4 independent aggregate queries. All are automatically
        tenant-scoped via RLS.
        """
        jobs_by_status = await self._get_jobs_by_status(start_date, end_date)
        revenue_by_month = await self._get_revenue_by_month(start_date, end_date)
        contractor_utilization = await self._get_contractor_utilization(start_date, end_date)
        quote_conversion = await self._get_quote_conversion(start_date, end_date)

        return DashboardResponse(
            jobs_by_status=jobs_by_status,
            revenue_by_month=revenue_by_month,
            contractor_utilization=contractor_utilization,
            quote_conversion=quote_conversion,
        )

    async def get_utilization_heatmap(
        self,
        company_id: uuid.UUID,
        start_date: date | None,
        end_date: date | None,
    ) -> UtilizationHeatmapResponse:
        """Per-contractor-per-week utilization heatmap.

        Returns a grid of ISO week columns and contractor rows.
        Contractors with zero bookings in the period still appear with
        zero-filled UtilizationWeekItem entries (from LEFT JOIN).

        Available hours are fixed at 40h/week per contractor.
        Utilization is capped at 100%.

        All aggregate queries avoid N+1 — one query per call.
        RLS automatically scopes to current tenant.
        """
        # --- ISO week expression (e.g. "2026-W10") ---
        iso_week_expr = func.to_char(
            func.date_trunc("week", func.lower(Booking.time_range)),
            'IYYY-"W"IW',
        ).label("iso_week")

        # --- Duration in hours expression ---
        duration_hours_expr = func.extract(
            "epoch",
            func.upper(Booking.time_range) - func.lower(Booking.time_range),
        ) / cast(3600, Numeric)
        booked_hours_expr = func.coalesce(
            func.sum(duration_hours_expr),
            cast(0, Numeric),
        ).label("booked_hours")

        # --- Contractor name expression ---
        contractor_name_expr = (
            func.coalesce(User.first_name, "") + " " + func.coalesce(User.last_name, "")
        ).label("contractor_name")

        # --- Booking date range WHERE conditions (applied to booking join, not user) ---
        booking_date_conditions = [Booking.deleted_at.is_(None)]
        if start_date is not None:
            booking_date_conditions.append(func.date(func.lower(Booking.time_range)) >= start_date)
        if end_date is not None:
            booking_date_conditions.append(func.date(func.lower(Booking.time_range)) <= end_date)

        result = await self.db.execute(
            select(
                User.id.label("contractor_id"),
                contractor_name_expr,
                iso_week_expr,
                booked_hours_expr,
            )
            .join(
                UserRoleModel,
                (UserRoleModel.user_id == User.id) & (UserRoleModel.role == "contractor"),
            )
            .join(
                Booking,
                and_(Booking.contractor_id == User.id, *booking_date_conditions),
                isouter=True,
            )
            .where(
                User.deleted_at.is_(None),
                UserRoleModel.deleted_at.is_(None),
            )
            .group_by(User.id, User.first_name, User.last_name, iso_week_expr)
            .order_by(User.first_name, iso_week_expr)
        )

        rows = result.all()

        # --- Post-process: build contractor dict and collect all ISO weeks ---
        # contractor_id -> {"name": str, "weeks": {iso_week: booked_hours}}
        contractor_map: dict[str, dict] = {}
        all_weeks: set[str] = set()

        for row in rows:
            cid = str(row.contractor_id)
            if cid not in contractor_map:
                contractor_map[cid] = {
                    "name": row.contractor_name,
                    "weeks": {},
                }
            if row.iso_week is not None:
                all_weeks.add(row.iso_week)
                contractor_map[cid]["weeks"][row.iso_week] = Decimal(str(row.booked_hours or 0))

        ordered_weeks = sorted(all_weeks)
        available_hours_per_week = Decimal("40")

        contractors_out: list[UtilizationHeatmapContractor] = []
        for cid, data in contractor_map.items():
            week_items: list[UtilizationWeekItem] = []
            for iso_week in ordered_weeks:
                booked = data["weeks"].get(iso_week, Decimal("0"))
                util_pct = min(
                    Decimal("100"),
                    (booked / available_hours_per_week * Decimal("100")).quantize(Decimal("0.01"))
                    if available_hours_per_week > 0
                    else Decimal("0"),
                )
                week_items.append(
                    UtilizationWeekItem(
                        iso_week=iso_week,
                        booked_hours=booked.quantize(Decimal("0.01")),
                        available_hours=available_hours_per_week,
                        utilization_percent=util_pct,
                    )
                )
            contractors_out.append(
                UtilizationHeatmapContractor(
                    contractor_id=cid,
                    contractor_name=data["name"],
                    weeks=week_items,
                )
            )

        return UtilizationHeatmapResponse(
            weeks=ordered_weeks,
            contractors=contractors_out,
        )

    async def get_contractor_stats(
        self,
        contractor_id: uuid.UUID,
        start_date: date | None,
        end_date: date | None,
    ) -> DashboardResponse:
        """Limited stats view for contractor role: own utilization and job counts.

        No revenue data returned — contractors see only their own workload metrics.
        """
        # Jobs by status — filtered to this contractor's jobs only
        conditions = [
            Job.deleted_at.is_(None),
            Job.contractor_id == contractor_id,
        ]
        conditions.extend(self._date_conditions(Job.created_at, start_date, end_date))

        result = await self.db.execute(
            select(Job.status, func.count().label("count"))
            .where(*conditions)
            .group_by(Job.status)
            .order_by(Job.status)
        )
        jobs_by_status = [
            JobsByStatusItem(status=row.status, count=row.count) for row in result.all()
        ]

        # Utilization — this contractor only
        # Booking uses TSTZRANGE (time_range); lower() extracts start timestamp.
        booking_conditions = [Booking.deleted_at.is_(None), Booking.contractor_id == contractor_id]
        if start_date is not None:
            booking_conditions.append(func.date(func.lower(Booking.time_range)) >= start_date)
        if end_date is not None:
            booking_conditions.append(func.date(func.lower(Booking.time_range)) <= end_date)

        if start_date is not None and end_date is not None:
            delta_days = (end_date - start_date).days + 1
            workdays = max(1, int(delta_days * 5 / 7))
            available_hours = Decimal(str(workdays * 8))
        else:
            available_hours = Decimal("168")

        contractor_duration_hours_expr = func.extract(
            "epoch",
            func.upper(Booking.time_range) - func.lower(Booking.time_range),
        ) / cast(3600, Numeric)
        contractor_name_expr2 = (
            func.coalesce(User.first_name, "") + " " + func.coalesce(User.last_name, "")
        ).label("contractor_name")
        booking_result = await self.db.execute(
            select(
                contractor_name_expr2,
                func.coalesce(
                    func.sum(contractor_duration_hours_expr),
                    cast(0, Numeric),
                ).label("booked_hours"),
            )
            .join(Booking, Booking.contractor_id == User.id, isouter=True)
            .where(User.id == contractor_id, *booking_conditions)
            .group_by(User.id, User.first_name, User.last_name)
        )
        contractor_utilization = []
        for row in booking_result.all():
            booked = Decimal(str(row.booked_hours or 0))
            util_pct = min(
                Decimal("100"),
                (booked / available_hours * Decimal("100")).quantize(Decimal("0.01"))
                if available_hours > 0
                else Decimal("0"),
            )
            contractor_utilization.append(
                ContractorUtilizationItem(
                    contractor_name=row.contractor_name,
                    booked_hours=booked.quantize(Decimal("0.01")),
                    available_hours=available_hours,
                    utilization_percent=util_pct,
                )
            )

        return DashboardResponse(
            jobs_by_status=jobs_by_status,
            revenue_by_month=[],  # No revenue data for contractor role
            contractor_utilization=contractor_utilization,
            quote_conversion=QuoteConversionItem(),
        )
