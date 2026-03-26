"""AlertRepository — data access layer for DashboardAlert entities."""

from __future__ import annotations

import uuid

from sqlalchemy import select

from app.core.base_repository import TenantScopedRepository
from app.features.dashboard.models import DashboardAlert


class AlertRepository(TenantScopedRepository[DashboardAlert]):
    """Repository for DashboardAlert CRUD and status operations."""

    model = DashboardAlert

    async def get_unread_for_company(self) -> list[DashboardAlert]:
        """Return unread alerts for the current tenant, ordered by severity then recency.

        RLS automatically scopes to the current company via app.current_company_id.
        Severity ordering: critical (highest) → warning → info.
        """
        stmt = (
            select(DashboardAlert)
            .where(
                DashboardAlert.is_read.is_(False),
                DashboardAlert.deleted_at.is_(None),
            )
            .order_by(
                # Severity descending: critical > warning > info
                DashboardAlert.severity.desc(),
                DashboardAlert.created_at.desc(),
            )
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_for_project(self, project_id: uuid.UUID) -> list[DashboardAlert]:
        """Return all non-deleted alerts for a specific project."""
        stmt = (
            select(DashboardAlert)
            .where(
                DashboardAlert.project_id == project_id,
                DashboardAlert.deleted_at.is_(None),
            )
            .order_by(DashboardAlert.created_at.desc())
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def mark_read(self, alert_id: uuid.UUID) -> DashboardAlert | None:
        """Set is_read=True on the given alert. Returns the updated alert or None."""
        entity = await self.db.get(DashboardAlert, alert_id)
        if entity is None:
            return None
        entity.is_read = True  # type: ignore[assignment]
        await self.db.flush()
        await self.db.refresh(entity)
        return entity

    async def accept_rescheduling(self, alert_id: uuid.UUID) -> DashboardAlert | None:
        """Set rescheduling_accepted=True. Returns the updated alert or None."""
        entity = await self.db.get(DashboardAlert, alert_id)
        if entity is None:
            return None
        entity.rescheduling_accepted = True  # type: ignore[assignment]
        entity.is_read = True  # type: ignore[assignment]
        await self.db.flush()
        await self.db.refresh(entity)
        return entity

    async def dismiss_alert(self, alert_id: uuid.UUID) -> DashboardAlert | None:
        """Set rescheduling_accepted=False (dismissed without applying). Returns updated alert."""
        entity = await self.db.get(DashboardAlert, alert_id)
        if entity is None:
            return None
        entity.rescheduling_accepted = False  # type: ignore[assignment]
        entity.is_read = True  # type: ignore[assignment]
        await self.db.flush()
        await self.db.refresh(entity)
        return entity

    async def count_active_for_project(self, project_id: uuid.UUID) -> int:
        """Count unread alerts for a project (used in ProjectStatusCard)."""
        from sqlalchemy import func, select

        stmt = select(func.count()).where(
            DashboardAlert.project_id == project_id,
            DashboardAlert.is_read.is_(False),
            DashboardAlert.deleted_at.is_(None),
        )
        result = await self.db.execute(stmt)
        count = result.scalar()
        return int(count or 0)
