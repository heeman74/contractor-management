"""Repositories for the v3.0 project data model.

Provides:
- ProjectRepository — projects with eager-loaded trade_scopes and client
- TradeCatalogRepository — company trade catalog entries
- TradeScopeRepository — trade scopes with eager-loaded tasks and contractor
- TaskRepository — tasks within a trade scope

All CLAUDE.md rules apply:
- All repositories inherit TenantScopedRepository or BaseRepository
- Use selectinload/joinedload — never lazy access in service or route layers
- Filter deleted_at is None explicitly in custom query methods
"""

from __future__ import annotations

import uuid

from sqlalchemy import func, or_, select
from sqlalchemy.orm import selectinload

from app.core.base_repository import BaseRepository, TenantScopedRepository
from app.features.projects.models import (
    Project,
    ProjectZone,
    Task,
    TaskAttachment,
    TaskDependency,
    TradeCatalog,
    TradeScope,
)


class ProjectRepository(TenantScopedRepository[Project]):
    """Repository for Project entities with eager-loaded relationships."""

    model = Project

    async def get_with_scopes(self, project_id: uuid.UUID) -> Project | None:
        """Retrieve a project with trade_scopes and client eager-loaded."""
        result = await self.db.execute(
            select(Project)
            .where(Project.id == project_id)
            .where(Project.deleted_at.is_(None))
            .options(
                selectinload(Project.trade_scopes),
                selectinload(Project.client),
            )
        )
        return result.scalars().first()

    async def list_with_scopes(self) -> list[Project]:
        """List all non-deleted projects with trade_scopes eager-loaded, newest first."""
        result = await self.db.execute(
            select(Project)
            .where(Project.deleted_at.is_(None))
            .options(selectinload(Project.trade_scopes))
            .order_by(Project.created_at.desc())
        )
        return list(result.scalars().all())


class TradeCatalogRepository(BaseRepository[TradeCatalog]):
    """Repository for TradeCatalog entries."""

    model = TradeCatalog

    async def list_by_company(self) -> list[TradeCatalog]:
        """List non-deleted catalog entries ordered by name."""
        result = await self.db.execute(
            select(TradeCatalog)
            .where(TradeCatalog.deleted_at.is_(None))
            .order_by(TradeCatalog.name)
        )
        return list(result.scalars().all())


class TradeScopeRepository(BaseRepository[TradeScope]):
    """Repository for TradeScope entities with eager-loaded relationships."""

    model = TradeScope

    async def list_by_project(self, project_id: uuid.UUID) -> list[TradeScope]:
        """List non-deleted trade scopes for a project with tasks and contractor eager-loaded."""
        result = await self.db.execute(
            select(TradeScope)
            .where(TradeScope.project_id == project_id)
            .where(TradeScope.deleted_at.is_(None))
            .options(
                selectinload(TradeScope.tasks),
                selectinload(TradeScope.contractor),
            )
            .order_by(TradeScope.sort_order)
        )
        return list(result.scalars().all())

    async def count_by_project(self, project_id: uuid.UUID) -> int:
        """Count non-deleted trade scopes for a project."""
        result = await self.db.execute(
            select(func.count())
            .select_from(TradeScope)
            .where(TradeScope.project_id == project_id)
            .where(TradeScope.deleted_at.is_(None))
        )
        return result.scalar_one()


class TaskRepository(BaseRepository[Task]):
    """Repository for Task entities."""

    model = Task

    async def list_by_scope(self, trade_scope_id: uuid.UUID) -> list[Task]:
        """List non-deleted tasks for a trade scope ordered by sort_order."""
        result = await self.db.execute(
            select(Task)
            .where(Task.trade_scope_id == trade_scope_id)
            .where(Task.deleted_at.is_(None))
            .order_by(Task.sort_order)
        )
        return list(result.scalars().all())


class TaskAttachmentRepository(BaseRepository[TaskAttachment]):
    """Repository for TaskAttachment entities."""

    model = TaskAttachment


class TaskDependencyRepository(TenantScopedRepository[TaskDependency]):
    """Repository for TaskDependency edge entities."""

    model = TaskDependency

    async def list_by_project(self, project_id: uuid.UUID) -> list[TaskDependency]:
        """Load ALL dependency edges for a project in a single query (join through Task -> TradeScope)."""
        stmt = (
            select(TaskDependency)
            .join(Task, TaskDependency.predecessor_task_id == Task.id)
            .join(TradeScope, Task.trade_scope_id == TradeScope.id)
            .where(TradeScope.project_id == project_id)
            .where(TaskDependency.deleted_at.is_(None))
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def list_by_task(self, task_id: uuid.UUID) -> list[TaskDependency]:
        """Get all dependencies where task_id is either predecessor or successor."""
        stmt = (
            select(TaskDependency)
            .where(
                or_(
                    TaskDependency.predecessor_task_id == task_id,
                    TaskDependency.successor_task_id == task_id,
                )
            )
            .where(TaskDependency.deleted_at.is_(None))
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())


class ProjectZoneRepository(TenantScopedRepository[ProjectZone]):
    """Repository for ProjectZone entities."""

    model = ProjectZone

    async def list_by_project(self, project_id: uuid.UUID) -> list[ProjectZone]:
        """List non-deleted zones for a project ordered by name."""
        stmt = (
            select(ProjectZone)
            .where(ProjectZone.project_id == project_id)
            .where(ProjectZone.deleted_at.is_(None))
            .order_by(ProjectZone.name)
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())
