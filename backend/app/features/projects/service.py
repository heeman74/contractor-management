"""Services for the v3.0 project data model.

Provides:
- ProjectService — project CRUD with semi-automatic status transitions
- TradeScopeService — scope creation with auto-advance of project status
- TaskService — task creation with auto-assigned sort_order
- TradeCatalogService — simple CRUD for trade catalog entries

Status transition rules (semi-automatic):
- Draft -> Planning: when first trade scope is added (automatic)
- Planning -> Active: when first task is started (Phase 20)
- Complete, Archived, On Hold: GC sets manually

All CLAUDE.md rules apply:
- No db.commit() — get_db handles transaction lifecycle
- All services inherit TenantScopedService
- No standalone service functions — class methods only
- Use db.flush() when generated IDs needed before commit
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from fastapi import HTTPException, status

from app.core.base_service import TenantScopedService
from app.features.projects.models import Project, Task, TradeCatalog, TradeScope
from app.features.projects.repository import (
    ProjectRepository,
    TaskRepository,
    TradeCatalogRepository,
    TradeScopeRepository,
)
from app.features.projects.schemas import (
    ProjectCreate,
    ProjectStatus,
    TaskCreate,
    TradeCatalogCreate,
    TradeScopeCreate,
)

# Valid project statuses for manual updates
_VALID_PROJECT_STATUSES: frozenset[str] = frozenset(ProjectStatus)


class ProjectService(TenantScopedService[Project]):
    """Business logic for Project entities."""

    repository_class = ProjectRepository

    async def create(self, data: ProjectCreate, user_id: uuid.UUID | None = None) -> Project:
        """Create a new project in draft status with an initial status history entry.

        Args:
            data: ProjectCreate schema with project fields.
            user_id: ID of the user creating the project (for status_history).

        Returns:
            Newly created Project with id and timestamps populated.
        """
        company_id = self._require_tenant_id()
        now = datetime.now(UTC)
        initial_history_entry = {
            "status": "draft",
            "changed_at": now.isoformat(),
            "changed_by": str(user_id) if user_id else None,
        }

        project = Project(
            company_id=company_id,
            name=data.name,
            description=data.description,
            address=data.address,
            client_id=data.client_id,
            target_start_date=data.target_start_date,
            target_end_date=data.target_end_date,
            status="draft",
            status_history=[initial_history_entry],
        )
        return await self.repository.create(project)

    async def update_status(
        self,
        project_id: uuid.UUID,
        new_status: str,
        user_id: uuid.UUID,
        reason: str | None = None,
    ) -> Project:
        """Update project status and append a status_history entry.

        Args:
            project_id: UUID of the project to update.
            new_status: Target status string — must be a valid ProjectStatus value.
            user_id: User triggering the transition (for audit trail).
            reason: Optional reason string for the status change.

        Returns:
            Updated Project.

        Raises:
            HTTPException 404: if project not found.
            HTTPException 422: if new_status is not a valid status value.
        """
        if new_status not in _VALID_PROJECT_STATUSES:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Invalid project status: {new_status!r}. "
                f"Valid values: {sorted(_VALID_PROJECT_STATUSES)}",
            )

        project = await self.repository.get_by_id(project_id)
        if project is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Project {project_id} not found",
            )

        history_entry: dict = {
            "status": new_status,
            "changed_at": datetime.now(UTC).isoformat(),
            "changed_by": str(user_id),
        }
        if reason:
            history_entry["reason"] = reason

        # Append to existing history (JSONB field — build new list)
        updated_history = list(project.status_history or []) + [history_entry]
        project.status = new_status
        project.status_history = updated_history
        await self.db.flush()
        await self.db.refresh(project)
        return project

    async def get_with_scopes(self, project_id: uuid.UUID) -> Project | None:
        """Retrieve a project with trade_scopes eager-loaded."""
        repo = ProjectRepository(self.db)
        return await repo.get_with_scopes(project_id)


class TradeCatalogService(TenantScopedService[TradeCatalog]):
    """Business logic for TradeCatalog entries."""

    repository_class = TradeCatalogRepository

    async def create(self, data: TradeCatalogCreate) -> TradeCatalog:
        """Create a new trade catalog entry for the current company."""
        company_id = self._require_tenant_id()
        entry = TradeCatalog(
            company_id=company_id,
            name=data.name,
            color=data.color,
        )
        return await self.repository.create(entry)

    async def list(self) -> list[TradeCatalog]:
        """List all catalog entries for the current company, ordered by name."""
        repo = TradeCatalogRepository(self.db)
        return await repo.list_by_company()


class TradeScopeService(TenantScopedService[TradeScope]):
    """Business logic for TradeScope entities.

    Semi-automatic status transition: when the first trade scope is added to a
    draft project, the project automatically advances to 'planning'.
    """

    repository_class = TradeScopeRepository

    async def create(self, data: TradeScopeCreate, user_id: uuid.UUID | None = None) -> TradeScope:
        """Create a trade scope and auto-advance project from draft to planning.

        Steps:
        1. Determine sort_order as (current scope count + 1).
        2. Copy trade_color from TradeCatalog if trade_catalog_id provided and
           no explicit color was given (color defaults to "#9E9E9E" in the schema).
        3. Create the TradeScope and flush to generate its ID.
        4. If project.status == 'draft', advance it to 'planning' with a
           status_history entry.

        Args:
            data: TradeScopeCreate schema with project_id, trade fields, etc.
            user_id: User creating the scope (for auto-advance status history).

        Returns:
            Newly created TradeScope.
        """
        company_id = self._require_tenant_id()

        # Step 1: determine sort_order
        scope_repo = TradeScopeRepository(self.db)
        existing_count = await scope_repo.count_by_project(data.project_id)
        sort_order = existing_count + 1

        # Step 2: copy trade_color from catalog if trade_catalog_id provided
        trade_color = data.trade_color
        if data.trade_catalog_id is not None and data.trade_color == "#9E9E9E":
            from sqlalchemy import select

            from app.features.projects.models import TradeCatalog as TradeCatalogModel

            result = await self.db.execute(
                select(TradeCatalogModel).where(TradeCatalogModel.id == data.trade_catalog_id)
            )
            catalog_entry = result.scalars().first()
            if catalog_entry is not None:
                trade_color = catalog_entry.color

        # Step 3: create the trade scope
        scope = TradeScope(
            company_id=company_id,
            project_id=data.project_id,
            trade_catalog_id=data.trade_catalog_id,
            trade_name=data.trade_name,
            trade_color=trade_color,
            contractor_id=data.contractor_id,
            sort_order=sort_order,
        )
        scope = await self.repository.create(scope)

        # Step 4: auto-advance project draft -> planning on first scope
        project_svc = ProjectService(self.db)
        project = await project_svc.repository.get_by_id(data.project_id)
        if project is not None and project.status == "draft":
            history_entry = {
                "status": "planning",
                "changed_at": datetime.now(UTC).isoformat(),
                "changed_by": str(user_id) if user_id else None,
                "reason": "First trade scope added",
            }
            updated_history = list(project.status_history or []) + [history_entry]
            project.status = "planning"
            project.status_history = updated_history
            await self.db.flush()

        return scope

    async def list_by_project(self, project_id: uuid.UUID) -> list[TradeScope]:
        """List trade scopes for a project with tasks and contractor eager-loaded."""
        repo = TradeScopeRepository(self.db)
        return await repo.list_by_project(project_id)


class TaskService(TenantScopedService[Task]):
    """Business logic for Task entities."""

    repository_class = TaskRepository

    async def create(self, data: TaskCreate) -> Task:
        """Create a task with auto-assigned sort_order.

        sort_order is determined by counting existing non-deleted tasks in the
        same trade_scope, then adding 1.
        """
        company_id = self._require_tenant_id()

        # Auto-assign sort_order
        from sqlalchemy import func, select

        count_result = await self.db.execute(
            select(func.count())
            .select_from(Task)
            .where(Task.trade_scope_id == data.trade_scope_id)
            .where(Task.deleted_at.is_(None))
        )
        existing_count = count_result.scalar_one()
        sort_order = existing_count + 1

        task = Task(
            company_id=company_id,
            trade_scope_id=data.trade_scope_id,
            title=data.title,
            description=data.description,
            priority=data.priority,
            estimated_hours=data.estimated_hours,
            estimated_cost=data.estimated_cost,
            due_date=data.due_date,
            start_date=data.start_date,
            zone_id=data.zone_id,
            photo_required=data.photo_required,
            assigned_to=data.assigned_to,
            materials_needed=data.materials_needed,
            sort_order=sort_order,
        )
        return await self.repository.create(task)

    async def list_by_scope(self, trade_scope_id: uuid.UUID) -> list[Task]:
        """List tasks for a trade scope ordered by sort_order."""
        repo = TaskRepository(self.db)
        return await repo.list_by_scope(trade_scope_id)
