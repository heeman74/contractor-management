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

_DEFAULT_NOT_FOUND_DETAIL = "Resource not found"


def entity_or_404[E](entity: E | None, detail: str = _DEFAULT_NOT_FOUND_DETAIL) -> E:
    """Return the entity, or raise HTTP 404 when it is None.

    Fetch-agnostic: use it after any lookup (repository.get_by_id, db.get,
    or a specialized eager-loading query) to collapse the None-check + raise.
    """
    if entity is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=detail)
    return entity


def active_entity_or_404[E](entity: E | None, detail: str = _DEFAULT_NOT_FOUND_DETAIL) -> E:
    """Like entity_or_404, but also treats a soft-deleted entity (deleted_at set) as absent."""
    if entity is None or getattr(entity, "deleted_at", None) is not None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=detail)
    return entity


class BaseService[T: Base]:
    """Base service providing standard CRUD via a repository."""

    repository_class: type[BaseRepository[T]]

    def __init__(self, db: AsyncSession) -> None:
        self.db = db
        self.repository = self.repository_class(db)

    async def get(self, entity_id: uuid.UUID) -> T | None:
        """Retrieve an entity by ID."""
        return await self.repository.get_by_id(entity_id)

    async def get_or_404(self, entity_id: uuid.UUID, *, detail: str | None = None) -> T:
        """Retrieve an entity by ID or raise HTTP 404."""
        return entity_or_404(
            await self.repository.get_by_id(entity_id),
            detail or _DEFAULT_NOT_FOUND_DETAIL,
        )

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
