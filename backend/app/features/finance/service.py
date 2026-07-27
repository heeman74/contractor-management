"""FinanceService — business logic for the cost-entry domain.

Wraps FinanceRepository; the router stays thin and delegates every operation
here (CLAUDE.md: router functions keep thin — delegate to service layer).

All CLAUDE.md rules apply:
- Inherits TenantScopedService[CostEntry]
- No db.commit() — get_db handles transaction lifecycle
- db.flush() when a generated id is needed before commit
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal

from fastapi import HTTPException, status

from app.core.base_service import TenantScopedService
from app.features.finance.labor_derivation import (
    CENTS,
    ZERO_MONEY,
    LaborTotals,
    WorkSession,
    resolve_rate_row_for_work_date,
    summarize_labor,
)
from app.features.finance.models import CostCategory, CostEntry, CostReceipt, LaborRate
from app.features.finance.repository import FinanceRepository, LaborRateRepository
from app.features.finance.schemas import (
    CategoryTotal,
    CostBreakdownResponse,
    CostEntryCreate,
    CostEntryUpdate,
    LaborCostSummary,
    LaborRateCreate,
)

_LABOR_CATEGORY_NAME = "labor"  # Phase 30 D-10 reserved category — derived labor's target


def _group_rates_by_user(rates: Iterable[LaborRate]) -> dict[uuid.UUID, list[LaborRate]]:
    """Group resolver-ordered rate rows per worker, preserving the ascending sort."""
    grouped: dict[uuid.UUID, list[LaborRate]] = {}
    for rate in rates:
        grouped.setdefault(rate.user_id, []).append(rate)
    return grouped


@dataclass(frozen=True)
class ProjectCostRollup:
    """Everything the project rollup endpoint needs from one service call."""

    entries: list[CostEntry]
    total: Decimal
    categories: list[CategoryTotal]
    labor: LaborTotals
    grand_total: Decimal


def _build_breakdown(
    category_rows: Sequence[tuple[uuid.UUID, str, Decimal]],
    labor: LaborTotals | None,
    *,
    tracked_at_job_level: bool,
) -> CostBreakdownResponse:
    """Assemble a breakdown from GROUP BY rows plus (optionally) derived labor.

    Legacy manual labor-category entries are folded into the derived labor row so
    nothing hides and nothing double-counts (RESEARCH Pitfall 1). With no labor row
    to fold into (trade scopes), they stay visible as an ordinary category row —
    a trade scope derives no labor, so no double-count is possible there.
    """
    labor_total = labor.total if labor is not None else ZERO_MONEY
    categories: list[CategoryTotal] = []
    for category_id, category_name, total in category_rows:
        if labor is not None and category_name == _LABOR_CATEGORY_NAME:
            labor_total += total
            continue
        categories.append(
            CategoryTotal(
                category_id=category_id,
                category_name=category_name,
                total=total.quantize(CENTS),
            )
        )
    grand_total = sum((category.total for category in categories), labor_total)
    labor_summary = (
        LaborCostSummary(
            total=labor_total.quantize(CENTS),
            rated_seconds=labor.rated_seconds,
            unrated_seconds=labor.unrated_seconds,
        )
        if labor is not None
        else None
    )
    return CostBreakdownResponse(
        categories=categories,
        labor=labor_summary,
        labor_tracked_at_job_level=tracked_at_job_level,
        grand_total=grand_total.quantize(CENTS),
    )


def _category_rows_from_entries(
    entries: Iterable[CostEntry],
) -> list[tuple[uuid.UUID, str, Decimal]]:
    """Group already-fetched (category-eager-loaded) entries — zero extra queries."""
    sums: dict[tuple[uuid.UUID, str], Decimal] = {}
    for entry in entries:
        key = (entry.category_id, entry.category.name)
        sums[key] = sums.get(key, ZERO_MONEY) + entry.amount
    return sorted(
        ((category_id, name, total) for (category_id, name), total in sums.items()),
        key=lambda row: row[1],
    )


class FinanceService(TenantScopedService[CostEntry]):
    """Service implementing cost-entry CRUD, category listing, and project rollup."""

    repository_class = FinanceRepository
    repository: FinanceRepository

    async def create_cost_entry(self, data: CostEntryCreate, company_id: uuid.UUID) -> CostEntry:
        """Create a cost entry anchored to a job XOR a trade scope (XOR enforced by schema)."""
        entry = CostEntry(
            company_id=company_id,
            job_id=data.job_id,
            trade_scope_id=data.trade_scope_id,
            category_id=data.category_id,
            amount=data.amount,
            incurred_date=data.incurred_date,
            vendor=data.vendor,
            note=data.note,
        )
        await self.repository.create(entry)
        return await self.repository.get_entry_or_404(entry.id)

    async def list_for_job(self, job_id: uuid.UUID) -> list[CostEntry]:
        """List non-soft-deleted cost entries for a job."""
        return await self.repository.list_for_job(job_id)

    async def list_for_trade_scope(self, trade_scope_id: uuid.UUID) -> list[CostEntry]:
        """List non-soft-deleted cost entries for a trade scope."""
        return await self.repository.list_for_trade_scope(trade_scope_id)

    async def get_entry_or_404(self, entry_id: uuid.UUID) -> CostEntry:
        """Fetch a single cost entry, or raise 404 if missing/soft-deleted."""
        return await self.repository.get_entry_or_404(entry_id)

    async def rollup_for_project(self, project_id: uuid.UUID) -> ProjectCostRollup:
        """Itemized entries + cost-entry total + category totals + derived project labor.

        Category totals are computed in Python from the already-fetched entries (zero
        extra queries); labor adds the two derivation round trips. `total` keeps its
        pre-Phase-32 meaning (cost-entry sum) — mobile parses it strictly.
        """
        entries = await self.repository.rollup_for_project(project_id)
        total = sum((entry.amount for entry in entries), Decimal("0"))
        sessions = await self.repository.completed_work_sessions_for_project(project_id)
        derived = await self._derive_labor(sessions)
        breakdown = _build_breakdown(
            _category_rows_from_entries(entries), derived, tracked_at_job_level=False
        )
        folded_total = breakdown.labor.total if breakdown.labor is not None else derived.total
        return ProjectCostRollup(
            entries=entries,
            total=total,
            categories=breakdown.categories,
            labor=LaborTotals(
                total=folded_total,
                rated_seconds=derived.rated_seconds,
                unrated_seconds=derived.unrated_seconds,
            ),
            grand_total=breakdown.grand_total,
        )

    async def _derive_labor(self, sessions: list[WorkSession]) -> LaborTotals:
        """Cost tracked time in exactly TWO bounded round trips, never one per entry.

        Round trip 1 already happened (the caller's session query). Round trip 2
        fetches every rate for the distinct contractors seen, then summarize_labor
        matches them in Python. CLAUDE.md N+1 rule: no query inside a loop.
        """
        contractor_ids = {session.contractor_id for session in sessions}
        if not contractor_ids:
            return LaborTotals(total=ZERO_MONEY, rated_seconds=0, unrated_seconds=0)
        rates = await LaborRateRepository(self.db).list_rates_for_users(sorted(contractor_ids))
        return summarize_labor(sessions, _group_rates_by_user(rates))

    async def job_cost_breakdown(self, job_id: uuid.UUID) -> CostBreakdownResponse:
        """Category totals + derived labor for a job (3 round trips total)."""
        category_rows = await self.repository.category_totals_for_job(job_id)
        sessions = await self.repository.completed_work_sessions_for_job(job_id)
        labor = await self._derive_labor(sessions)
        return _build_breakdown(category_rows, labor, tracked_at_job_level=False)

    async def trade_scope_cost_breakdown(self, trade_scope_id: uuid.UUID) -> CostBreakdownResponse:
        """Category totals only — labor is job-anchored in v4.0 (D-08), so no labor figure.

        Returns labor=None and labor_tracked_at_job_level=True.
        """
        category_rows = await self.repository.category_totals_for_trade_scope(trade_scope_id)
        return _build_breakdown(category_rows, None, tracked_at_job_level=True)

    async def update_cost_entry(self, entry_id: uuid.UUID, data: CostEntryUpdate) -> CostEntry:
        """Update a cost entry's amount/category/date/vendor/note (anchor is immutable)."""
        entry = await self.repository.get_entry_or_404(entry_id)
        updates = data.model_dump(exclude_unset=True)
        for field, value in updates.items():
            setattr(entry, field, value)
        await self.db.flush()
        return await self.repository.get_entry_or_404(entry_id)

    async def delete_cost_entry(self, entry_id: uuid.UUID) -> None:
        """Soft-delete a cost entry (D-05) — excluded from lists/rollups afterward."""
        await self.repository.soft_delete(entry_id)

    async def list_categories(self) -> list[CostCategory]:
        """List the current tenant's cost categories."""
        return await self.repository.list_categories()

    async def add_receipt(
        self,
        cost_entry_id: uuid.UUID,
        company_id: uuid.UUID,
        remote_url: str,
        caption: str | None,
    ) -> CostReceipt:
        """Create a receipt row attached to a cost entry."""
        receipt = CostReceipt(
            company_id=company_id,
            cost_entry_id=cost_entry_id,
            remote_url=remote_url,
            caption=caption,
        )
        return await self.repository.create(receipt)

    async def list_receipts(self, cost_entry_id: uuid.UUID) -> list[CostReceipt]:
        """List non-soft-deleted receipts for a cost entry."""
        return await self.repository.list_receipts_for_entry(cost_entry_id)

    async def delete_receipt(self, cost_entry_id: uuid.UUID, receipt_id: uuid.UUID) -> None:
        """Soft-delete a receipt, 404ing if it does not belong to the given cost entry."""
        receipt = await self.repository.get_receipt_or_404(receipt_id)
        if receipt.cost_entry_id != cost_entry_id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Receipt not found")
        await self.repository.soft_delete_receipt(receipt_id)


class LaborRateService(TenantScopedService[LaborRate]):
    """Service for append-only labor rates (COST-04) — no update, no delete."""

    repository_class = LaborRateRepository
    repository: LaborRateRepository

    async def create_labor_rate(self, data: LaborRateCreate, company_id: uuid.UUID) -> LaborRate:
        """Append a rate row after confirming the worker belongs to this company."""
        if not await self.repository.user_exists(data.user_id):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
        rate = LaborRate(
            company_id=company_id,
            user_id=data.user_id,
            hourly_cost=data.hourly_cost,
            effective_from=data.effective_from,
        )
        return await self.repository.create(rate)

    async def list_rate_history(self, user_id: uuid.UUID) -> list[LaborRate]:
        """Full history for one worker (newest effective_from first)."""
        return await self.repository.list_history_for_user(user_id)

    async def list_current_rates(self, as_of: date | None = None) -> list[LaborRate]:
        """One currently-effective rate row per worker, for the Team page column.

        Fetches every rate in ONE query and resolves the current row per worker with
        the shared resolve_rate_row_for_work_date helper — the rule lives in exactly
        one place (labor_derivation), never duplicated in SQL. Future-dated rows are
        naturally excluded because their effective_from is greater than as_of.
        """
        today = as_of or datetime.now(UTC).date()
        grouped = _group_rates_by_user(await self.repository.list_all_rates())
        resolved = (
            resolve_rate_row_for_work_date(user_rates, today) for user_rates in grouped.values()
        )
        return [rate for rate in resolved if rate is not None]
