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
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.core.base_service import TenantScopedService, active_entity_or_404
from app.features.projects.models import (
    Project,
    ProjectZone,
    Task,
    TaskAttachment,
    TaskDependency,
    TaskNote,
    TradeCatalog,
    TradeScope,
)
from app.features.projects.repository import (
    ProjectRepository,
    ProjectZoneRepository,
    TaskAttachmentRepository,
    TaskDependencyRepository,
    TaskNoteRepository,
    TaskRepository,
    TradeCatalogRepository,
    TradeScopeRepository,
)
from app.features.projects.schemas import (
    ProjectCreate,
    ProjectStatus,
    ProjectZoneCreate,
    TaskCreate,
    TaskDependencyCreate,
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

        project = await self.get_or_404(project_id, detail=f"Project {project_id} not found")

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

    async def recompute_successor_statuses(self, task_id: uuid.UUID) -> None:
        """When a task is completed, unblock its successors if all their predecessors are complete.

        Called from the update_task endpoint when status changes to 'complete'.
        Loads all edges where task_id is a predecessor, then recomputes each successor.
        """
        dep_svc = DependencyService(self.db)
        # Get all edges where this task is a predecessor
        stmt = (
            select(TaskDependency)
            .where(TaskDependency.predecessor_task_id == task_id)
            .where(TaskDependency.deleted_at.is_(None))
        )
        result = await self.db.execute(stmt)
        edges = result.scalars().all()
        for edge in edges:
            await dep_svc._recompute_blocked_status(edge.successor_task_id)

    async def count_attachments_by_type(self, task_id: uuid.UUID, attachment_type: str) -> int:
        """Count non-deleted task attachments of a specific type for a task."""
        from sqlalchemy import func

        result = await self.db.execute(
            select(func.count())
            .select_from(TaskAttachment)
            .where(TaskAttachment.task_id == task_id)
            .where(TaskAttachment.attachment_type == attachment_type)
            .where(TaskAttachment.deleted_at.is_(None))
        )
        return result.scalar_one()

    async def create_attachment(
        self,
        task_id: uuid.UUID,
        attachment_type: str,
        remote_url: str | None,
        caption: str | None,
        sort_order: int,
        annotation_data: dict | None,
        company_id: uuid.UUID,
    ) -> TaskAttachment:
        """Create a TaskAttachment record after enforcing per-type count limits.

        Limits:
        - photo: max 10 per task
        - document: max 5 per task
        - video: max 10 per task (no separate limit defined — reuse photo limit)

        Raises:
            HTTPException 400: if attachment count limit exceeded.
        """
        attachment_limits = {"photo": 10, "document": 5, "video": 10}
        limit = attachment_limits.get(attachment_type)
        if limit is not None:
            current_count = await self.count_attachments_by_type(task_id, attachment_type)
            if current_count >= limit:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        f"Attachment limit exceeded: max {limit} {attachment_type} attachments "
                        f"per task. Current count: {current_count}."
                    ),
                )

        attachment = TaskAttachment(
            company_id=company_id,
            task_id=task_id,
            attachment_type=attachment_type,
            remote_url=remote_url,
            caption=caption,
            sort_order=sort_order,
            annotation_data=annotation_data,
        )
        repo = TaskAttachmentRepository(self.db)
        return await repo.create(attachment)


class TaskNoteService(TenantScopedService[TaskNote]):
    """Business logic for TaskNote entities.

    Notes are ordered newest-first (created_at DESC) when listed.
    author_id is taken from the authenticated user (not from request body).
    """

    repository_class = TaskNoteRepository

    async def create_note(
        self,
        task_id: uuid.UUID,
        body: str,
        author_id: uuid.UUID,
    ) -> TaskNote:
        """Create a task note.

        Verifies the task exists (404 if not), then creates the note.

        Args:
            task_id:   UUID of the task to attach the note to.
            body:      Note text content (min 1 char enforced at schema level).
            author_id: UUID of the user writing the note.

        Returns:
            Newly created TaskNote.

        Raises:
            HTTPException 404: if the task does not exist.
        """
        company_id = self._require_tenant_id()

        # Verify task exists (RLS will also enforce tenant scoping)
        active_entity_or_404(await self.db.get(Task, task_id), f"Task {task_id} not found")

        note = TaskNote(
            company_id=company_id,
            task_id=task_id,
            author_id=author_id,
            body=body,
        )
        repo = TaskNoteRepository(self.db)
        return await repo.create(note)

    async def list_by_task(self, task_id: uuid.UUID) -> list[TaskNote]:
        """List non-deleted notes for a task, ordered newest first (created_at DESC)."""
        repo = TaskNoteRepository(self.db)
        return await repo.list_by_task(task_id)


class DependencyService(TenantScopedService[TaskDependency]):
    """Business logic for task dependency edges.

    Responsibilities:
    - Create dependency edges with DFS cycle detection
    - Recompute blocked status when edges are created/deleted
    - List edges for a task
    - Delete edges (soft delete)
    """

    repository_class = TaskDependencyRepository

    async def create_dependency(
        self, successor_task_id: uuid.UUID, data: TaskDependencyCreate
    ) -> TaskDependency:
        """Create a dependency edge from predecessor to successor, rejecting cycles.

        Steps:
        1. Verify both tasks exist and belong to the same project.
        2. Load all existing edges for the project.
        3. Build adjacency graph + add proposed edge.
        4. Run DFS cycle detection — raise 422 with cycle path if cycle found.
        5. Persist the new edge.
        6. Recompute successor's blocked status.
        """
        # 1. Verify both tasks exist
        pred_task = await self.db.get(Task, data.predecessor_task_id)
        succ_task = await self.db.get(Task, successor_task_id)
        if not pred_task or not succ_task:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Task not found",
            )

        # Get project_id via trade_scope for each task
        pred_scope = await self.db.get(TradeScope, pred_task.trade_scope_id)
        succ_scope = await self.db.get(TradeScope, succ_task.trade_scope_id)
        if not pred_scope or not succ_scope or pred_scope.project_id != succ_scope.project_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Tasks must belong to the same project",
            )

        # 2. Load all existing edges for this project
        repo = TaskDependencyRepository(self.db)
        existing_edges = await repo.list_by_project(pred_scope.project_id)

        # 3. Build adjacency graph and add proposed edge
        graph: dict[str, list[str]] = {}
        all_nodes: set[str] = set()
        for edge in existing_edges:
            pred = str(edge.predecessor_task_id)
            succ = str(edge.successor_task_id)
            graph.setdefault(pred, []).append(succ)
            all_nodes.update([pred, succ])
        # Add proposed edge
        new_pred = str(data.predecessor_task_id)
        new_succ = str(successor_task_id)
        graph.setdefault(new_pred, []).append(new_succ)
        all_nodes.update([new_pred, new_succ])

        # 4. Run DFS cycle detection
        cycle = self._find_cycle(graph, all_nodes)
        if cycle:
            # Resolve task titles for display
            cycle_names = []
            for task_id_str in cycle:
                task = await self.db.get(Task, uuid.UUID(task_id_str))
                cycle_names.append(task.title if task else task_id_str)
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail={
                    "message": "Dependency creates a cycle",
                    "cycle": cycle_names,
                    "cycle_ids": cycle,
                },
            )

        # 5. Persist the new edge
        company_id = self._require_tenant_id()
        edge = TaskDependency(
            company_id=company_id,
            predecessor_task_id=data.predecessor_task_id,
            successor_task_id=successor_task_id,
            dependency_type=data.dependency_type,
            lag_days=data.lag_days,
        )
        self.db.add(edge)
        await self.db.flush()

        # 6. Recompute blocked status for the successor
        await self._recompute_blocked_status(successor_task_id)

        return edge

    def _find_cycle(self, graph: dict[str, list[str]], all_nodes: set[str]) -> list[str] | None:
        """DFS cycle detection with white/gray/black coloring.

        Returns the cycle path (list of node IDs) if a cycle is found, else None.
        """
        color: dict[str, int] = dict.fromkeys(all_nodes, 0)
        path: list[str] = []

        def dfs(node: str) -> list[str] | None:
            color[node] = 1  # gray = in progress
            path.append(node)
            for neighbor in graph.get(node, []):
                if color.get(neighbor, 0) == 1:
                    # Back edge found — cycle detected
                    cycle_start = path.index(neighbor)
                    return path[cycle_start:] + [neighbor]
                if color.get(neighbor, 0) == 0:
                    result = dfs(neighbor)
                    if result:
                        return result
            color[node] = 2  # black = fully explored
            path.pop()
            return None

        for node in all_nodes:
            if color[node] == 0:
                result = dfs(node)
                if result:
                    return result
        return None

    async def _recompute_blocked_status(self, task_id: uuid.UUID) -> None:
        """Set task.status='blocked' if any FS/SS/SE predecessor is not complete.

        If no such predecessors exist or all are complete, restore status to
        'not_started' (if it was previously blocked). Does not change status
        if the task is already 'complete'.
        """
        stmt = (
            select(TaskDependency)
            .where(TaskDependency.successor_task_id == task_id)
            .where(TaskDependency.deleted_at.is_(None))
        )
        result = await self.db.execute(stmt)
        edges = result.scalars().all()

        is_blocked = False
        for edge in edges:
            predecessor = await self.db.get(Task, edge.predecessor_task_id)
            if (
                predecessor
                and predecessor.status != "complete"
                and edge.dependency_type in ("FS", "SS", "SE")
            ):
                is_blocked = True
                break

        task = await self.db.get(Task, task_id)
        if task and task.status != "complete":
            new_status = (
                "blocked"
                if is_blocked
                else ("not_started" if task.status == "blocked" else task.status)
            )
            if new_status != task.status:
                task.status = new_status
                await self.db.flush()

    async def delete_dependency(self, dependency_id: uuid.UUID) -> bool:
        """Soft-delete a dependency edge and recompute successor's blocked status."""
        repo = TaskDependencyRepository(self.db)
        edge = await repo.get_by_id(dependency_id)
        if not edge:
            return False
        successor_id = edge.successor_task_id
        result = await repo.soft_delete(dependency_id)
        # Recompute after removal
        await self._recompute_blocked_status(successor_id)
        return result

    async def list_by_task(self, task_id: uuid.UUID) -> list[TaskDependency]:
        """List all dependency edges where task_id is predecessor or successor."""
        repo = TaskDependencyRepository(self.db)
        return await repo.list_by_task(task_id)


class ConflictService:
    """Detect zone-based scheduling conflicts for a project.

    A conflict is two tasks from different trade scopes that share the same
    zone_id and the same due_date. This is the minimum viable conflict
    definition — Phase 21+ can extend to date-range overlap.
    """

    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def detect_conflicts(self, project_id: uuid.UUID) -> list[dict]:
        """Find cross-trade zone/date conflicts for a project.

        Returns a list of dicts with task1/task2 info and the shared zone + date.
        Only cross-trade conflicts are returned (tasks in the same trade scope
        are not flagged — they are under one contractor's control).
        """
        t1 = aliased(Task, name="t1")
        t2 = aliased(Task, name="t2")
        s1 = aliased(TradeScope, name="s1")
        s2 = aliased(TradeScope, name="s2")
        z = aliased(ProjectZone, name="z")

        stmt = (
            select(
                t1.id.label("task1_id"),
                t1.title.label("task1_title"),
                s1.trade_name.label("task1_trade"),
                t2.id.label("task2_id"),
                t2.title.label("task2_title"),
                s2.trade_name.label("task2_trade"),
                z.name.label("zone_name"),
                t1.due_date.label("conflict_date"),
            )
            .select_from(t1)
            .join(s1, t1.trade_scope_id == s1.id)
            .join(z, t1.zone_id == z.id)
            .join(t2, t1.zone_id == t2.zone_id)
            .join(s2, t2.trade_scope_id == s2.id)
            .where(t1.zone_id.is_not(None))
            .where(t1.due_date == t2.due_date)
            .where(t1.due_date.is_not(None))
            .where(s1.project_id == project_id)
            .where(s2.project_id == project_id)
            .where(t1.trade_scope_id != t2.trade_scope_id)
            .where(t1.id < t2.id)  # de-duplicate symmetric pairs
            .where(t1.deleted_at.is_(None))
            .where(t2.deleted_at.is_(None))
        )
        result = await self.db.execute(stmt)
        rows = result.all()
        return [
            {
                "task1_id": str(r.task1_id),
                "task1_title": r.task1_title,
                "task1_trade_name": r.task1_trade,
                "task2_id": str(r.task2_id),
                "task2_title": r.task2_title,
                "task2_trade_name": r.task2_trade,
                "zone_name": r.zone_name,
                "conflict_date": str(r.conflict_date),
            }
            for r in rows
        ]


class ProjectZoneService(TenantScopedService[ProjectZone]):
    """Business logic for ProjectZone entities."""

    repository_class = ProjectZoneRepository

    async def create(self, project_id: uuid.UUID, data: ProjectZoneCreate) -> ProjectZone:
        """Create a named zone for a project.

        Raises 409 if a zone with the same name already exists in this project.
        """
        company_id = self._require_tenant_id()
        zone = ProjectZone(
            company_id=company_id,
            project_id=project_id,
            name=data.name,
        )
        self.db.add(zone)
        try:
            await self.db.flush()
        except IntegrityError as exc:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Zone '{data.name}' already exists in this project",
            ) from exc
        return zone

    async def list_by_project(self, project_id: uuid.UUID) -> list[ProjectZone]:
        """List non-deleted zones for a project ordered by name."""
        repo = ProjectZoneRepository(self.db)
        return await repo.list_by_project(project_id)

    async def delete(self, zone_id: uuid.UUID) -> bool:
        """Soft-delete a zone."""
        repo = ProjectZoneRepository(self.db)
        return await repo.soft_delete(zone_id)
