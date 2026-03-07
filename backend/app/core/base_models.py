"""Base ORM models with shared columns extracted as mixins.

All new models MUST inherit from BaseEntityModel (non-tenant) or
TenantScopedModel (tenant-scoped with company_id FK).
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class TimestampMixin:
    """Mixin providing created_at, updated_at, deleted_at columns."""

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class BaseEntityModel(Base, TimestampMixin):
    """Abstract base for all entities: UUID primary key + version + timestamps."""

    __abstract__ = True

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid(),
    )
    version: Mapped[int] = mapped_column(Integer, nullable=False, server_default="1")


class TenantScopedModel(BaseEntityModel):
    """Abstract base for tenant-scoped entities: adds company_id FK."""

    __abstract__ = True

    company_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("companies.id"),
        nullable=False,
    )
