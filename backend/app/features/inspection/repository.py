"""Repositories for the GC Inspection Workflow.

Provides:
- TaskInspectionRepository — inspection records per task
- SiteWalkFlagRepository   — site walk flags per project
- PunchListRepository      — punch list items per trade scope / project

All inherit TenantScopedRepository for automatic company_id scoping via RLS.
"""

from __future__ import annotations

import uuid

from sqlalchemy import select

from app.core.base_repository import TenantScopedRepository
from app.features.inspection.models import PunchListItem, SiteWalkFlag, TaskInspection


class TaskInspectionRepository(TenantScopedRepository[TaskInspection]):
    """Repository for TaskInspection entities."""

    model = TaskInspection

    async def list_by_task(self, task_id: uuid.UUID) -> list[TaskInspection]:
        """List all non-deleted inspections for a task, newest first (audit trail)."""
        result = await self.db.execute(
            select(TaskInspection)
            .where(TaskInspection.task_id == task_id)
            .where(TaskInspection.deleted_at.is_(None))
            .order_by(TaskInspection.created_at.desc())
        )
        return list(result.scalars().all())


class SiteWalkFlagRepository(TenantScopedRepository[SiteWalkFlag]):
    """Repository for SiteWalkFlag entities."""

    model = SiteWalkFlag

    async def list_by_project(self, project_id: uuid.UUID) -> list[SiteWalkFlag]:
        """List all non-deleted flags for a project, newest first."""
        result = await self.db.execute(
            select(SiteWalkFlag)
            .where(SiteWalkFlag.project_id == project_id)
            .where(SiteWalkFlag.deleted_at.is_(None))
            .order_by(SiteWalkFlag.created_at.desc())
        )
        return list(result.scalars().all())


class PunchListRepository(TenantScopedRepository[PunchListItem]):
    """Repository for PunchListItem entities."""

    model = PunchListItem

    async def list_by_scope(self, trade_scope_id: uuid.UUID) -> list[PunchListItem]:
        """List all non-deleted punch list items for a trade scope, newest first."""
        result = await self.db.execute(
            select(PunchListItem)
            .where(PunchListItem.trade_scope_id == trade_scope_id)
            .where(PunchListItem.deleted_at.is_(None))
            .order_by(PunchListItem.created_at.desc())
        )
        return list(result.scalars().all())

    async def list_by_project(self, project_id: uuid.UUID) -> list[PunchListItem]:
        """List all non-deleted punch list items for a project, newest first."""
        result = await self.db.execute(
            select(PunchListItem)
            .where(PunchListItem.project_id == project_id)
            .where(PunchListItem.deleted_at.is_(None))
            .order_by(PunchListItem.created_at.desc())
        )
        return list(result.scalars().all())
