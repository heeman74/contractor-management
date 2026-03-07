"""Base repository classes for generic async CRUD operations.

All new repositories MUST inherit from BaseRepository (non-tenant) or
TenantScopedRepository (tenant-scoped with eager loading support).
"""

import uuid
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import Base


class BaseRepository[T: Base]:
    """Generic async repository with common CRUD operations."""

    model: type[T]

    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def get_by_id(self, entity_id: uuid.UUID) -> T | None:
        """Retrieve a single entity by primary key."""
        return await self.db.get(self.model, entity_id)

    async def list_all(self) -> list[T]:
        """Retrieve all entities (RLS filters to current tenant automatically)."""
        result = await self.db.execute(select(self.model))
        return list(result.scalars().all())

    async def create(self, entity: T) -> T:
        """Add and flush an entity, returning it with server-generated fields."""
        self.db.add(entity)
        await self.db.flush()
        await self.db.refresh(entity)
        return entity

    async def update(self, entity_id: uuid.UUID, data: dict) -> T | None:
        """Partial update: apply only the provided fields."""
        entity = await self.db.get(self.model, entity_id)
        if entity is None:
            return None
        for field, value in data.items():
            setattr(entity, field, value)
        await self.db.flush()
        await self.db.refresh(entity)
        return entity

    async def soft_delete(self, entity_id: uuid.UUID) -> bool:
        """Set deleted_at on an entity. Returns False if not found."""
        entity = await self.db.get(self.model, entity_id)
        if entity is None:
            return False
        entity.deleted_at = datetime.now(UTC)  # type: ignore[attr-defined]
        await self.db.flush()
        return True

    async def upsert_idempotent(self, entity_id: uuid.UUID, values: dict) -> T:
        """INSERT ON CONFLICT DO NOTHING — for sync retry deduplication."""
        stmt = (
            insert(self.model)
            .values(id=entity_id, **values)
            .on_conflict_do_nothing(index_elements=["id"])
        )
        await self.db.execute(stmt)
        return await self.db.get(self.model, entity_id)  # type: ignore[return-value]


class TenantScopedRepository[T: Base](BaseRepository[T]):
    """Repository for tenant-scoped entities with eager loading support."""

    eager_load_options: list = []

    async def get_by_id(self, entity_id: uuid.UUID) -> T | None:
        """Retrieve by ID with eager-loaded relationships."""
        if self.eager_load_options:
            result = await self.db.execute(
                select(self.model)
                .where(self.model.id == entity_id)  # type: ignore[attr-defined]
                .options(*self.eager_load_options)
            )
            return result.scalars().first()
        return await self.db.get(self.model, entity_id)

    async def list_all(self) -> list[T]:
        """List all with eager-loaded relationships."""
        stmt = select(self.model)
        if self.eager_load_options:
            stmt = stmt.options(*self.eager_load_options)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())
