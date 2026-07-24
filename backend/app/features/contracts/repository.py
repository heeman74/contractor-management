"""Repositories for contracts and contract-terms templates."""

from __future__ import annotations

import uuid

from sqlalchemy import select

from app.core.base_repository import TenantScopedRepository
from app.features.contracts.models import Contract, ContractTemplate


class ContractTemplateRepository(TenantScopedRepository[ContractTemplate]):
    """Reads/writes the company's contract-terms template (RLS-scoped)."""

    model = ContractTemplate

    async def get_default(self) -> ContractTemplate | None:
        """Return the company's default template, if one exists."""
        result = await self.db.execute(
            select(ContractTemplate)
            .where(ContractTemplate.is_default.is_(True))
            .where(ContractTemplate.deleted_at.is_(None))
        )
        return result.scalars().first()


class ContractRepository(TenantScopedRepository[Contract]):
    """Reads/writes contracts (RLS-scoped)."""

    model = Contract

    async def get_by_quote(self, quote_id: uuid.UUID) -> Contract | None:
        """Return the (latest) non-deleted contract for a quote, if any."""
        result = await self.db.execute(
            select(Contract)
            .where(Contract.quote_id == quote_id)
            .where(Contract.deleted_at.is_(None))
            .order_by(Contract.created_at.desc())
        )
        return result.scalars().first()

    async def get_by_request_id(self, provider_request_id: str) -> Contract | None:
        """Return a contract by its e-sign provider request id (webhook lookup)."""
        result = await self.db.execute(
            select(Contract).where(Contract.provider_request_id == provider_request_id)
        )
        return result.scalars().first()
