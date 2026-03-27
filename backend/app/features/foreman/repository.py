"""Repositories for the foreman role feature.

All repositories inherit TenantScopedRepository for RLS-aware CRUD.
Eager loading configured via selectinload/joinedload per CLAUDE.md rules.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime

from sqlalchemy import func, select
from sqlalchemy.orm import joinedload

from app.core.base_repository import TenantScopedRepository
from app.features.foreman.models import ProjectAssignment, ProjectStatusUpdate


class ProjectAssignmentRepository(TenantScopedRepository[ProjectAssignment]):
    """Repository for ProjectAssignment entities with eager loading."""

    model = ProjectAssignment
    # eager_load_options set in _get_eager_options() to avoid import-time mapper resolution
    eager_load_options: list = []

    @staticmethod
    def _get_eager_options():
        return [
            joinedload(ProjectAssignment.project),
            joinedload(ProjectAssignment.user),
        ]

    async def get_by_id(self, entity_id: uuid.UUID) -> ProjectAssignment | None:
        """Retrieve by ID with eager-loaded project and user."""
        result = await self.db.execute(
            select(ProjectAssignment)
            .where(ProjectAssignment.id == entity_id)
            .options(*self._get_eager_options())
        )
        return result.scalars().first()

    async def assign(
        self,
        company_id: uuid.UUID,
        project_id: uuid.UUID,
        user_id: uuid.UUID,
        role: str = "foreman",
    ) -> ProjectAssignment:
        """Create a project assignment, handling upsert for soft-deleted records.

        If a soft-deleted assignment exists for the same (company, project, user, role),
        restore it by clearing deleted_at. Otherwise create a new one.
        """
        # Check for existing soft-deleted assignment
        stmt = (
            select(ProjectAssignment)
            .where(ProjectAssignment.company_id == company_id)
            .where(ProjectAssignment.project_id == project_id)
            .where(ProjectAssignment.user_id == user_id)
            .where(ProjectAssignment.role == role)
            .where(ProjectAssignment.deleted_at.is_not(None))
        )
        result = await self.db.execute(stmt)
        existing = result.scalars().first()

        if existing is not None:
            existing.deleted_at = None
            existing.assigned_at = datetime.now(UTC)
            await self.db.flush()
            await self.db.refresh(existing)
            return existing

        assignment = ProjectAssignment(
            company_id=company_id,
            project_id=project_id,
            user_id=user_id,
            role=role,
        )
        self.db.add(assignment)
        await self.db.flush()
        await self.db.refresh(assignment)
        return assignment

    async def unassign(self, assignment_id: uuid.UUID) -> bool:
        """Soft-delete a project assignment."""
        return await self.soft_delete(assignment_id)

    async def get_by_project(self, project_id: uuid.UUID) -> list[ProjectAssignment]:
        """List all active assignments for a project with eager-loaded relations."""
        stmt = (
            select(ProjectAssignment)
            .where(ProjectAssignment.project_id == project_id)
            .where(ProjectAssignment.deleted_at.is_(None))
            .options(
                joinedload(ProjectAssignment.project),
                joinedload(ProjectAssignment.user),
            )
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_by_user(self, user_id: uuid.UUID) -> list[ProjectAssignment]:
        """List all active assignments for a user with eager-loaded relations."""
        stmt = (
            select(ProjectAssignment)
            .where(ProjectAssignment.user_id == user_id)
            .where(ProjectAssignment.deleted_at.is_(None))
            .options(
                joinedload(ProjectAssignment.project),
                joinedload(ProjectAssignment.user),
            )
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_project_ids_for_user(self, user_id: uuid.UUID) -> list[uuid.UUID]:
        """Return just the project IDs assigned to a user (for filtering)."""
        stmt = (
            select(ProjectAssignment.project_id)
            .where(ProjectAssignment.user_id == user_id)
            .where(ProjectAssignment.deleted_at.is_(None))
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())


class StatusUpdateRepository(TenantScopedRepository[ProjectStatusUpdate]):
    """Repository for ProjectStatusUpdate entities with eager loading."""

    model = ProjectStatusUpdate
    # eager_load_options set in _get_eager_options() to avoid import-time mapper resolution
    eager_load_options: list = []

    @staticmethod
    def _get_eager_options():
        return [joinedload(ProjectStatusUpdate.author)]

    async def create_update(self, entity: ProjectStatusUpdate) -> ProjectStatusUpdate:
        """Create a status update and return it with eager-loaded author."""
        self.db.add(entity)
        await self.db.flush()
        # Re-fetch with eager loading
        stmt = (
            select(ProjectStatusUpdate)
            .where(ProjectStatusUpdate.id == entity.id)
            .options(joinedload(ProjectStatusUpdate.author))
        )
        result = await self.db.execute(stmt)
        return result.scalars().first()  # type: ignore[return-value]

    async def get_by_project(
        self,
        project_id: uuid.UUID,
        limit: int = 20,
        offset: int = 0,
    ) -> tuple[list[ProjectStatusUpdate], int]:
        """Paginated list of status updates for a project, newest first.

        Returns (items, total_count).
        """
        # Count total
        count_stmt = (
            select(func.count())
            .select_from(ProjectStatusUpdate)
            .where(ProjectStatusUpdate.project_id == project_id)
            .where(ProjectStatusUpdate.deleted_at.is_(None))
        )
        count_result = await self.db.execute(count_stmt)
        total = count_result.scalar_one()

        # Fetch page
        stmt = (
            select(ProjectStatusUpdate)
            .where(ProjectStatusUpdate.project_id == project_id)
            .where(ProjectStatusUpdate.deleted_at.is_(None))
            .options(joinedload(ProjectStatusUpdate.author))
            .order_by(ProjectStatusUpdate.report_date.desc(), ProjectStatusUpdate.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        result = await self.db.execute(stmt)
        items = list(result.scalars().all())
        return items, total

    async def get_by_date(
        self, project_id: uuid.UUID, report_date: date
    ) -> list[ProjectStatusUpdate]:
        """Get status updates for a specific project and date."""
        stmt = (
            select(ProjectStatusUpdate)
            .where(ProjectStatusUpdate.project_id == project_id)
            .where(ProjectStatusUpdate.report_date == report_date)
            .where(ProjectStatusUpdate.deleted_at.is_(None))
            .options(joinedload(ProjectStatusUpdate.author))
            .order_by(ProjectStatusUpdate.created_at.desc())
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_latest_by_project(self, project_id: uuid.UUID) -> ProjectStatusUpdate | None:
        """Get the most recent status update for a project."""
        stmt = (
            select(ProjectStatusUpdate)
            .where(ProjectStatusUpdate.project_id == project_id)
            .where(ProjectStatusUpdate.deleted_at.is_(None))
            .options(joinedload(ProjectStatusUpdate.author))
            .order_by(ProjectStatusUpdate.report_date.desc(), ProjectStatusUpdate.created_at.desc())
            .limit(1)
        )
        result = await self.db.execute(stmt)
        return result.scalars().first()
