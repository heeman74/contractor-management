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
from dataclasses import dataclass

from sqlalchemy import String, case, func, or_, select
from sqlalchemy.orm import selectinload

from app.core.base_repository import BaseRepository, TenantScopedRepository
from app.features.projects.models import (
    Project,
    ProjectZone,
    Task,
    TaskAttachment,
    TaskDependency,
    TaskNote,
    TradeCatalog,
    TradeScope,
    UserTradeSpecialty,
)
from app.features.users.models import User, UserRole

_CONTRACTOR_ROLE = "contractor"


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


# Common construction trades every new company starts with. Seeded at
# registration and available on demand for existing companies; each remains
# individually editable and removable afterward.
DEFAULT_TRADES: tuple[tuple[str, str], ...] = (
    ("Electrical", "#F59E0B"),
    ("Plumbing", "#3B82F6"),
    ("HVAC", "#10B981"),
    ("Framing", "#A16207"),
    ("Drywall", "#9CA3AF"),
    ("Painting", "#EC4899"),
    ("Flooring", "#8B5CF6"),
    ("Roofing", "#EF4444"),
    ("Concrete", "#6B7280"),
    ("Masonry", "#78716C"),
    ("Insulation", "#F97316"),
    ("Tiling", "#14B8A6"),
    ("Carpentry", "#B45309"),
    ("Landscaping", "#22C55E"),
    ("Demolition", "#57534E"),
)


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

    async def find_by_name(self, company_id: uuid.UUID, name: str) -> TradeCatalog | None:
        """Return the entry with this exact name (including soft-deleted), if any.

        Matches the (company_id, name) uniqueness so create can detect a conflict
        or revive a previously removed trade instead of hitting a DB error.
        """
        result = await self.db.execute(
            select(TradeCatalog).where(
                TradeCatalog.company_id == company_id,
                TradeCatalog.name == name,
            )
        )
        return result.scalars().first()

    async def seed_defaults(self, company_id: uuid.UUID) -> int:
        """Insert the default trades this company is missing; return how many.

        Idempotent: an existing name (even a soft-deleted one) is skipped, so a
        trade the user deliberately removed is never resurrected and re-seeding
        never duplicates rows.
        """
        result = await self.db.execute(
            select(TradeCatalog.name).where(TradeCatalog.company_id == company_id)
        )
        existing = {name.casefold() for name in result.scalars().all()}
        created = 0
        for name, color in DEFAULT_TRADES:
            if name.casefold() in existing:
                continue
            self.db.add(TradeCatalog(company_id=company_id, name=name, color=color))
            created += 1
        if created:
            await self.db.flush()
        return created


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


class UserTradeSpecialtyRepository(BaseRepository[UserTradeSpecialty]):
    """Repository for contractor trade specialties (user ↔ trade_catalog join)."""

    model = UserTradeSpecialty

    async def find(
        self, user_id: uuid.UUID, trade_catalog_id: uuid.UUID
    ) -> UserTradeSpecialty | None:
        """Return the specialty linking this user to this trade, if it exists."""
        result = await self.db.execute(
            select(UserTradeSpecialty).where(
                UserTradeSpecialty.user_id == user_id,
                UserTradeSpecialty.trade_catalog_id == trade_catalog_id,
            )
        )
        return result.scalars().first()


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


class TaskNoteRepository(BaseRepository[TaskNote]):
    """Repository for TaskNote entities."""

    model = TaskNote

    async def list_by_task(self, task_id: uuid.UUID) -> list[TaskNote]:
        """List non-deleted notes for a task, newest first."""
        result = await self.db.execute(
            select(TaskNote)
            .where(TaskNote.task_id == task_id)
            .where(TaskNote.deleted_at.is_(None))
            .order_by(TaskNote.created_at.desc())
        )
        return list(result.scalars().all())


class TaskAttachmentRepository(BaseRepository[TaskAttachment]):
    """Repository for TaskAttachment entities."""

    model = TaskAttachment

    async def list_by_task(self, task_id: uuid.UUID) -> list[TaskAttachment]:
        """List non-deleted attachments for a task ordered by sort_order."""
        result = await self.db.execute(
            select(TaskAttachment)
            .where(TaskAttachment.task_id == task_id)
            .where(TaskAttachment.deleted_at.is_(None))
            .order_by(TaskAttachment.sort_order)
        )
        return list(result.scalars().all())


@dataclass(frozen=True)
class ContractorMatch:
    """A contractor row annotated with whether they match a requested specialty."""

    id: uuid.UUID
    name: str
    email: str
    has_specialty_match: bool


class ContractorMatchRepository(BaseRepository[User]):
    """Reads contractors, optionally ranked by trade-specialty match."""

    model = User

    async def list_contractors(
        self,
        trade_catalog_id: uuid.UUID | None = None,
    ) -> list[ContractorMatch]:
        """List company contractors; when trade_catalog_id is given, matches sort first."""
        name_col = (
            func.concat(
                func.coalesce(User.first_name, ""),
                " ",
                func.coalesce(User.last_name, ""),
            )
            .cast(String)
            .label("name")
        )
        match_col = case(
            (UserTradeSpecialty.id.is_not(None), True),
            else_=False,
        ).label("has_specialty_match")

        stmt = (
            select(User.id, name_col, User.email, match_col)
            .join(UserRole, UserRole.user_id == User.id)
            .outerjoin(
                UserTradeSpecialty,
                (UserTradeSpecialty.user_id == User.id)
                & (UserTradeSpecialty.trade_catalog_id == trade_catalog_id),
            )
            .where(UserRole.role == _CONTRACTOR_ROLE)
            .where(User.deleted_at.is_(None))
            .order_by(match_col.desc(), User.email)
        )

        result = await self.db.execute(stmt)
        matched = trade_catalog_id is not None
        return [
            ContractorMatch(
                id=row.id,
                name=row.name.strip() or row.email,
                email=row.email,
                has_specialty_match=bool(row.has_specialty_match) if matched else False,
            )
            for row in result.fetchall()
        ]


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
