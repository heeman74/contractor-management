"""AlertRepository — data access layer for DashboardAlert entities."""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import case, func, select

from app.core.base_repository import TenantScopedRepository
from app.features.dashboard.models import DashboardAlert

# CASE expression for correct severity ordering (not alphabetical)
_severity_order = case(
    (DashboardAlert.severity == "critical", 3),
    (DashboardAlert.severity == "warning", 2),
    (DashboardAlert.severity == "info", 1),
    else_=0,
)


class AlertRepository(TenantScopedRepository[DashboardAlert]):
    """Repository for DashboardAlert CRUD and status operations."""

    model = DashboardAlert

    async def get_unread_for_company(self) -> list[DashboardAlert]:
        """Return unread alerts for the current tenant, ordered by severity then recency.

        RLS automatically scopes to the current company via app.current_company_id.
        Severity ordering: critical (highest) -> warning -> info.
        """
        stmt = (
            select(DashboardAlert)
            .where(
                DashboardAlert.is_read.is_(False),
                DashboardAlert.deleted_at.is_(None),
            )
            .order_by(
                _severity_order.desc(),
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

    async def _update_alert_fields(
        self, alert_id: uuid.UUID, **fields: Any
    ) -> DashboardAlert | None:
        """Fetch an alert by ID and apply field updates. Returns updated alert or None."""
        entity = await self.db.get(DashboardAlert, alert_id)
        if entity is None:
            return None
        for key, value in fields.items():
            setattr(entity, key, value)
        await self.db.flush()
        await self.db.refresh(entity)
        return entity

    async def mark_read(self, alert_id: uuid.UUID) -> DashboardAlert | None:
        """Set is_read=True on the given alert. Returns the updated alert or None."""
        return await self._update_alert_fields(alert_id, is_read=True)

    async def accept_rescheduling(self, alert_id: uuid.UUID) -> DashboardAlert | None:
        """Set rescheduling_accepted=True. Returns the updated alert or None."""
        return await self._update_alert_fields(alert_id, rescheduling_accepted=True, is_read=True)

    async def dismiss_alert(self, alert_id: uuid.UUID) -> DashboardAlert | None:
        """Set rescheduling_accepted=False (dismissed without applying). Returns updated alert."""
        return await self._update_alert_fields(alert_id, rescheduling_accepted=False, is_read=True)

    async def count_active_for_project(self, project_id: uuid.UUID) -> int:
        """Count unread alerts for a project (used in ProjectStatusCard)."""
        stmt = select(func.count()).where(
            DashboardAlert.project_id == project_id,
            DashboardAlert.is_read.is_(False),
            DashboardAlert.deleted_at.is_(None),
        )
        result = await self.db.execute(stmt)
        count = result.scalar()
        return int(count or 0)
