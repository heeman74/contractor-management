"""Base service classes for business logic layer.

All new services MUST inherit from BaseService (non-tenant) or
TenantScopedService (tenant-scoped with tenant ID enforcement).
"""

import uuid

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_repository import BaseRepository
from app.core.database import Base
from app.core.tenant import get_current_tenant_id


class BaseService[T: Base]:
    """Base service providing standard CRUD via a repository."""

    repository_class: type[BaseRepository[T]]

    def __init__(self, db: AsyncSession) -> None:
        self.db = db
        self.repository = self.repository_class(db)

    async def get(self, entity_id: uuid.UUID) -> T | None:
        """Retrieve an entity by ID."""
        return await self.repository.get_by_id(entity_id)

    async def list(self) -> list[T]:
        """List all entities (RLS filters automatically)."""
        return await self.repository.list_all()

    async def update(self, entity_id: uuid.UUID, data: dict) -> T | None:
        """Partial update an entity."""
        return await self.repository.update(entity_id, data)


class TenantScopedService[T: Base](BaseService[T]):
    """Service for tenant-scoped entities with tenant ID enforcement."""

    def _require_tenant_id(self) -> uuid.UUID:
        """Get current tenant ID or raise 400 if not set."""
        tenant_id = get_current_tenant_id()
        if tenant_id is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="X-Company-Id header is required",
            )
        return tenant_id
