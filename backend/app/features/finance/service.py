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
from collections.abc import Iterable
from datetime import UTC, date, datetime
from decimal import Decimal

from fastapi import HTTPException, status

from app.core.base_service import TenantScopedService
from app.features.finance.labor_derivation import resolve_rate_row_for_work_date
from app.features.finance.models import CostCategory, CostEntry, CostReceipt, LaborRate
from app.features.finance.repository import FinanceRepository, LaborRateRepository
from app.features.finance.schemas import CostEntryCreate, CostEntryUpdate, LaborRateCreate


def _group_rates_by_user(rates: Iterable[LaborRate]) -> dict[uuid.UUID, list[LaborRate]]:
    """Group resolver-ordered rate rows per worker, preserving the ascending sort."""
    grouped: dict[uuid.UUID, list[LaborRate]] = {}
    for rate in rates:
        grouped.setdefault(rate.user_id, []).append(rate)
    return grouped


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

    async def rollup_for_project(self, project_id: uuid.UUID) -> tuple[list[CostEntry], Decimal]:
        """Return the itemized entries + Decimal total for a project's cost rollup.

        Single DB round trip (repository.rollup_for_project) — the total is
        summed in Python over the already-fetched itemized list, not a second query.
        """
        entries = await self.repository.rollup_for_project(project_id)
        total = sum((entry.amount for entry in entries), Decimal("0"))
        return entries, total

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
