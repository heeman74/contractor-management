"""FinanceRepository — async data access for the cost-entry domain.

Inherits TenantScopedRepository[CostEntry]. All queries are automatically
tenant-scoped via PostgreSQL RLS (SET LOCAL app.current_company_id).

CLAUDE.md N+1 rule: joinedload(CostEntry.category) on every list/get/rollup
query — category is many-to-one, category is lazy="raise" on the model, so an
un-eager-loaded access would fail loudly rather than silently N+1.

Pitfall 3 (31-RESEARCH.md): BaseRepository.list_all() does NOT filter
deleted_at — every custom query method here adds `.where(CostEntry.deleted_at.is_(None))`
explicitly (D-05: soft-deleted entries drop out of lists and rollups).
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import joinedload

from app.core.base_repository import TenantScopedRepository
from app.features.finance.models import CostCategory, CostEntry, CostReceipt
from app.features.jobs.models import Job
from app.features.projects.models import TradeScope


class FinanceRepository(TenantScopedRepository[CostEntry]):
    """Repository for CostEntry entities — eager-loads category by default."""

    model = CostEntry

    async def list_for_job(self, job_id: uuid.UUID) -> list[CostEntry]:
        """Return non-soft-deleted cost entries for a job, newest incurred_date first."""
        result = await self.db.execute(
            select(CostEntry)
            .where(CostEntry.job_id == job_id, CostEntry.deleted_at.is_(None))
            .options(joinedload(CostEntry.category))
            .order_by(CostEntry.incurred_date.desc())
        )
        return list(result.scalars().unique().all())

    async def list_for_trade_scope(self, trade_scope_id: uuid.UUID) -> list[CostEntry]:
        """Return non-soft-deleted cost entries for a trade scope, newest first."""
        result = await self.db.execute(
            select(CostEntry)
            .where(CostEntry.trade_scope_id == trade_scope_id, CostEntry.deleted_at.is_(None))
            .options(joinedload(CostEntry.category))
            .order_by(CostEntry.incurred_date.desc())
        )
        return list(result.scalars().unique().all())

    async def rollup_for_project(self, project_id: uuid.UUID) -> list[CostEntry]:
        """Return every non-soft-deleted cost entry rolling up to a project.

        Per D-02/D-05: trade-scope-anchored costs (trade_scopes.project_id) +
        costs on jobs whose project_id matches, in ONE query (no per-anchor
        loop — CLAUDE.md N+1 rule). The service computes the Decimal total
        from this single itemized list.
        """
        result = await self.db.execute(
            select(CostEntry)
            .outerjoin(TradeScope, CostEntry.trade_scope_id == TradeScope.id)
            .outerjoin(Job, CostEntry.job_id == Job.id)
            .where(
                CostEntry.deleted_at.is_(None),
                (TradeScope.project_id == project_id) | (Job.project_id == project_id),
            )
            .options(joinedload(CostEntry.category))
            .order_by(CostEntry.incurred_date.desc())
        )
        return list(result.scalars().unique().all())

    async def get_entry_or_404(self, entry_id: uuid.UUID) -> CostEntry:
        """Fetch a cost entry by id with category eager-loaded, or raise 404."""
        result = await self.db.execute(
            select(CostEntry)
            .where(CostEntry.id == entry_id, CostEntry.deleted_at.is_(None))
            .options(joinedload(CostEntry.category))
        )
        entry = result.scalars().unique().first()
        if entry is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Cost entry not found"
            )
        return entry

    async def soft_delete(self, entry_id: uuid.UUID) -> None:
        """Set deleted_at on a cost entry so it drops out of lists/rollups."""
        entry = await self.get_entry_or_404(entry_id)
        entry.deleted_at = datetime.now(UTC)
        await self.db.flush()

    async def list_categories(self) -> list[CostCategory]:
        """Return the current tenant's cost categories, alphabetically."""
        result = await self.db.execute(select(CostCategory).order_by(CostCategory.name))
        return list(result.scalars().all())

    async def list_receipts_for_entry(self, cost_entry_id: uuid.UUID) -> list[CostReceipt]:
        """Return non-soft-deleted receipts for a cost entry, newest first."""
        result = await self.db.execute(
            select(CostReceipt)
            .where(CostReceipt.cost_entry_id == cost_entry_id, CostReceipt.deleted_at.is_(None))
            .order_by(CostReceipt.created_at.desc())
        )
        return list(result.scalars().all())

    async def get_receipt_or_404(self, receipt_id: uuid.UUID) -> CostReceipt:
        """Fetch a non-soft-deleted receipt by id, or raise 404."""
        result = await self.db.execute(
            select(CostReceipt).where(
                CostReceipt.id == receipt_id, CostReceipt.deleted_at.is_(None)
            )
        )
        receipt = result.scalars().first()
        if receipt is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Receipt not found")
        return receipt

    async def soft_delete_receipt(self, receipt_id: uuid.UUID) -> None:
        """Set deleted_at on a receipt so it drops out of the receipt list."""
        receipt = await self.get_receipt_or_404(receipt_id)
        receipt.deleted_at = datetime.now(UTC)
        await self.db.flush()
