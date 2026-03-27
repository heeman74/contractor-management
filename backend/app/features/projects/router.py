"""REST API router for the v3.0 project data model.

Registers sub-routers under /api/v1:
  /projects        — Project CRUD
  /trade-catalog   — TradeCatalog CRUD
  /trade-scopes    — TradeScope CRUD with auto-advance trigger
  /tasks           — Task CRUD with sort_order auto-assignment
  /contractors     — Contractor specialty matching (returns matching contractors first)

All endpoints require authentication via Depends(get_current_user).
All DB access uses Depends(get_db) for automatic transaction lifecycle.

CLAUDE.md rules:
- Router functions are thin — delegate to service layer
- CurrentUser is the real CurrentUser object (user_id, company_id, roles attributes)
- No standalone functions — all logic in service layer
"""

from __future__ import annotations

import logging
import uuid
from pathlib import Path
from typing import Annotated

import aiofiles
from fastapi import APIRouter, Depends, Form, HTTPException, Query, UploadFile, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user
from app.features.projects.schemas import (
    ConflictRecord,
    ProjectCreate,
    ProjectResponse,
    ProjectUpdate,
    ProjectZoneCreate,
    ProjectZoneResponse,
    TaskAttachmentResponse,
    TaskAttachmentUpdate,
    TaskCreate,
    TaskDependencyCreate,
    TaskDependencyResponse,
    TaskNoteCreate,
    TaskNoteResponse,
    TaskResponse,
    TaskUpdate,
    TradeCatalogCreate,
    TradeCatalogResponse,
    TradeCatalogUpdate,
    TradeScopeCreate,
    TradeScopeResponse,
    TradeScopeUpdate,
)
from app.features.projects.service import (
    ConflictService,
    DependencyService,
    ProjectService,
    ProjectZoneService,
    TaskNoteService,
    TaskService,
    TradeCatalogService,
    TradeScopeService,
)

logger = logging.getLogger(__name__)

router = APIRouter()

# ---------------------------------------------------------------------------
# Projects router
# ---------------------------------------------------------------------------
projects_router = APIRouter(prefix="/projects", tags=["projects"])


@projects_router.post("/", response_model=ProjectResponse, status_code=status.HTTP_201_CREATED)
async def create_project(
    data: ProjectCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> ProjectResponse:
    """Create a new project in draft status."""
    svc = ProjectService(db)
    project = await svc.create(data, user_id=current_user.user_id)
    return ProjectResponse.model_validate(project)


@projects_router.get("/", response_model=list[ProjectResponse])
async def list_projects(
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> list[ProjectResponse]:
    """List all projects for the current company with trade_scopes eager-loaded."""
    from app.features.projects.repository import ProjectRepository

    repo = ProjectRepository(db)
    projects = await repo.list_with_scopes()
    return [ProjectResponse.model_validate(p) for p in projects]


@projects_router.get("/{project_id}", response_model=ProjectResponse)
async def get_project(
    project_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> ProjectResponse:
    """Get a project detail with trade_scopes eager-loaded."""
    svc = ProjectService(db)
    project = await svc.get_with_scopes(project_id)
    if project is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Project {project_id} not found",
        )
    return ProjectResponse.model_validate(project)


@projects_router.patch("/{project_id}", response_model=ProjectResponse)
async def update_project(
    project_id: uuid.UUID,
    data: ProjectUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> ProjectResponse:
    """Update a project. If status is in the data, calls update_status for the transition."""
    svc = ProjectService(db)

    update_data = data.model_dump(exclude_none=True)
    new_status = update_data.pop("status", None)

    # Apply non-status field updates first
    if update_data:
        project = await svc.update(project_id, update_data)
        if project is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Project {project_id} not found",
            )

    # Apply status transition if requested
    if new_status is not None:
        project = await svc.update_status(project_id, new_status, current_user.user_id)

    # If nothing was updated, just return the existing project
    if not update_data and new_status is None:
        project = await svc.repository.get_by_id(project_id)
        if project is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Project {project_id} not found",
            )

    return ProjectResponse.model_validate(project)


@projects_router.delete(
    "/{project_id}", status_code=status.HTTP_204_NO_CONTENT, response_model=None
)
async def delete_project(
    project_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Soft-delete a project."""
    svc = ProjectService(db)
    deleted = await svc.repository.soft_delete(project_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Project {project_id} not found",
        )


@projects_router.get("/{project_id}/quote-summary")
async def project_quote_summary(
    project_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> dict:
    """Return per-trade quote totals and grand total for a project (admin only).

    Returns {project_id, scopes: [{scope_id, trade_name, quote_count, subtotal}], grand_total}.
    """
    if "admin" not in current_user.roles:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin role required")
    from app.features.quotes.service import QuoteService

    svc = QuoteService(db)
    return await svc.aggregate_by_project(project_id)


@projects_router.get("/{project_id}/invoice-summary")
async def project_invoice_summary(
    project_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> dict:
    """Return per-trade invoice totals for a project (admin only).

    Returns {project_id, scopes: [{scope_id, trade_name, invoice_count, total_billed, total_paid, total_outstanding}],
    total_billed, total_paid, total_outstanding}.
    """
    if "admin" not in current_user.roles:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin role required")
    from app.features.invoices.service import InvoiceService

    svc = InvoiceService(db)
    return await svc.aggregate_by_project(project_id)


# ---------------------------------------------------------------------------
# Trade Catalog router
# ---------------------------------------------------------------------------
trade_catalog_router = APIRouter(prefix="/trade-catalog", tags=["trade-catalog"])


@trade_catalog_router.post(
    "/", response_model=TradeCatalogResponse, status_code=status.HTTP_201_CREATED
)
async def create_catalog_entry(
    data: TradeCatalogCreate,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> TradeCatalogResponse:
    """Create a new trade catalog entry."""
    svc = TradeCatalogService(db)
    entry = await svc.create(data)
    return TradeCatalogResponse.model_validate(entry)


@trade_catalog_router.get("/", response_model=list[TradeCatalogResponse])
async def list_catalog(
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> list[TradeCatalogResponse]:
    """List all trade catalog entries for the current company."""
    svc = TradeCatalogService(db)
    entries = await svc.list()
    return [TradeCatalogResponse.model_validate(e) for e in entries]


@trade_catalog_router.patch("/{catalog_id}", response_model=TradeCatalogResponse)
async def update_catalog_entry(
    catalog_id: uuid.UUID,
    data: TradeCatalogUpdate,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> TradeCatalogResponse:
    """Update a trade catalog entry (name and/or color)."""
    svc = TradeCatalogService(db)
    update_data = data.model_dump(exclude_none=True)
    entry = await svc.update(catalog_id, update_data)
    if entry is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"TradeCatalog {catalog_id} not found",
        )
    return TradeCatalogResponse.model_validate(entry)


@trade_catalog_router.delete(
    "/{catalog_id}", status_code=status.HTTP_204_NO_CONTENT, response_model=None
)
async def delete_catalog_entry(
    catalog_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Soft-delete a trade catalog entry."""
    svc = TradeCatalogService(db)
    deleted = await svc.repository.soft_delete(catalog_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"TradeCatalog {catalog_id} not found",
        )


# ---------------------------------------------------------------------------
# Trade Scopes router
# ---------------------------------------------------------------------------
trade_scopes_router = APIRouter(prefix="/trade-scopes", tags=["trade-scopes"])


@trade_scopes_router.post(
    "/", response_model=TradeScopeResponse, status_code=status.HTTP_201_CREATED
)
async def create_trade_scope(
    data: TradeScopeCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> TradeScopeResponse:
    """Create a trade scope. Automatically advances project from draft to planning."""
    svc = TradeScopeService(db)
    scope = await svc.create(data, user_id=current_user.user_id)
    return TradeScopeResponse.model_validate(scope)


@trade_scopes_router.get("/", response_model=list[TradeScopeResponse])
async def list_trade_scopes(
    project_id: uuid.UUID = Query(..., description="Filter by project ID (required)"),
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> list[TradeScopeResponse]:
    """List trade scopes for a project (project_id is required)."""
    svc = TradeScopeService(db)
    scopes = await svc.list_by_project(project_id)
    return [TradeScopeResponse.model_validate(s) for s in scopes]


@trade_scopes_router.patch("/{scope_id}", response_model=TradeScopeResponse)
async def update_trade_scope(
    scope_id: uuid.UUID,
    data: TradeScopeUpdate,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> TradeScopeResponse:
    """Update a trade scope (contractor_id, status, status_override, sort_order, etc.)."""
    svc = TradeScopeService(db)
    update_data = data.model_dump(exclude_none=True)
    scope = await svc.update(scope_id, update_data)
    if scope is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"TradeScope {scope_id} not found",
        )
    return TradeScopeResponse.model_validate(scope)


@trade_scopes_router.delete(
    "/{scope_id}", status_code=status.HTTP_204_NO_CONTENT, response_model=None
)
async def delete_trade_scope(
    scope_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Soft-delete a trade scope."""
    svc = TradeScopeService(db)
    deleted = await svc.repository.soft_delete(scope_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"TradeScope {scope_id} not found",
        )


# ---------------------------------------------------------------------------
# Tasks router
# ---------------------------------------------------------------------------
tasks_router = APIRouter(prefix="/tasks", tags=["tasks"])


@tasks_router.post("/", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
async def create_task(
    data: TaskCreate,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> TaskResponse:
    """Create a task with auto-assigned sort_order."""
    svc = TaskService(db)
    task = await svc.create(data)
    return TaskResponse.model_validate(task)


@tasks_router.get("/", response_model=list[TaskResponse])
async def list_tasks(
    trade_scope_id: uuid.UUID = Query(..., description="Filter by trade scope ID (required)"),
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> list[TaskResponse]:
    """List tasks for a trade scope (trade_scope_id is required)."""
    svc = TaskService(db)
    tasks = await svc.list_by_scope(trade_scope_id)
    return [TaskResponse.model_validate(t) for t in tasks]


@tasks_router.patch("/{task_id}", response_model=TaskResponse)
async def update_task(
    task_id: uuid.UUID,
    data: TaskUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> TaskResponse:
    """Update a task.

    When status changes to 'complete':
    - Automatically recomputes blocked status for all successor tasks.
    - Fires a batch digest notification to all GC/admin users (fire-and-forget per D-16).
      Notification failure never blocks the status update.
    """
    svc = TaskService(db)
    update_data = data.model_dump(exclude_none=True)
    new_status = update_data.get("status")

    # Track the previous status to avoid re-triggering on idempotent PATCHes
    existing_task = await svc.repository.get_by_id(task_id)
    if existing_task is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Task {task_id} not found",
        )
    previous_status = existing_task.status

    task = await svc.update(task_id, update_data)
    if task is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Task {task_id} not found",
        )

    # When task transitions to 'complete' (not already complete), handle side effects
    if new_status == "complete" and previous_status != "complete":
        # Unblock successors that were waiting on this task
        await svc.recompute_successor_statuses(task_id)

        # Fire-and-forget digest notification to GC users (per D-16)
        # Notification failure must never block the task status update
        try:
            from sqlalchemy import select

            from app.features.notifications.service import NotificationService
            from app.features.projects.models import TradeScope

            # Resolve trade_scope.trade_name for the notification body
            scope_result = await db.execute(
                select(TradeScope).where(TradeScope.id == task.trade_scope_id)
            )
            scope = scope_result.scalars().first()
            trade_scope_name = scope.trade_name if scope else "Unknown Trade"

            completed_by_name = str(current_user.user_id)  # fallback — user_id as display name

            notif_svc = NotificationService(db)
            await notif_svc.queue_task_completion_digest(
                task_id=task_id,
                task_title=task.title,
                trade_scope_name=trade_scope_name,
                company_id=current_user.company_id,
                completed_by_name=completed_by_name,
            )
        except Exception:
            # Fire-and-forget: log but never raise
            logger.exception(
                "Digest notification failed for task %s — task update still succeeded", task_id
            )

    return TaskResponse.model_validate(task)


@tasks_router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def delete_task(
    task_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Soft-delete a task."""
    svc = TaskService(db)
    deleted = await svc.repository.soft_delete(task_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Task {task_id} not found",
        )


# ---------------------------------------------------------------------------
# Task notes endpoints
# ---------------------------------------------------------------------------


@tasks_router.post(
    "/{task_id}/notes",
    response_model=TaskNoteResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_task_note(
    task_id: uuid.UUID,
    data: TaskNoteCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> TaskNoteResponse:
    """Create a note on a task. Returns 201 with the created note."""
    svc = TaskNoteService(db)
    note = await svc.create_note(
        task_id=task_id,
        body=data.body,
        author_id=current_user.user_id,
    )
    return TaskNoteResponse.model_validate(note)


@tasks_router.get("/{task_id}/notes", response_model=list[TaskNoteResponse])
async def list_task_notes(
    task_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> list[TaskNoteResponse]:
    """List all notes for a task, newest first."""
    svc = TaskNoteService(db)
    notes = await svc.list_by_task(task_id)
    return [TaskNoteResponse.model_validate(n) for n in notes]


# ---------------------------------------------------------------------------
# Task attachments endpoints
# ---------------------------------------------------------------------------

_ALLOWED_TASK_ATTACHMENT_TYPES = frozenset({"photo", "video", "document"})


@tasks_router.post(
    "/{task_id}/attachments",
    response_model=TaskAttachmentResponse,
    status_code=status.HTTP_201_CREATED,
)
async def upload_task_attachment(
    task_id: uuid.UUID,
    file: UploadFile,
    attachment_type: Annotated[str, Form(description="Type: 'photo', 'video', or 'document'")],
    caption: Annotated[str | None, Form()] = None,
    sort_order: Annotated[int, Form()] = 0,
    annotation_data: Annotated[
        str | None, Form(description="JSON string of annotation overlay data")
    ] = None,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> TaskAttachmentResponse:
    """Upload a file and create a TaskAttachment record.

    Saves file to uploads/task-attachments/{task_id}/{uuid}{ext}.
    Enforces count limits: max 10 photos/videos, max 5 documents per task.
    Returns 201 + TaskAttachmentResponse with remote_url populated.

    Raises:
    - 400 if attachment_type is invalid
    - 400 if no file provided
    - 400 if count limit exceeded
    """
    import json

    # Validate attachment_type
    if attachment_type not in _ALLOWED_TASK_ATTACHMENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Invalid attachment_type '{attachment_type}'. "
                f"Must be one of: {', '.join(sorted(_ALLOWED_TASK_ATTACHMENT_TYPES))}"
            ),
        )

    if not file.filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No file provided.",
        )

    # Parse annotation_data JSON string if provided
    parsed_annotation_data: dict | None = None
    if annotation_data:
        try:
            parsed_annotation_data = json.loads(annotation_data)
        except (json.JSONDecodeError, ValueError) as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="annotation_data must be a valid JSON string",
            ) from exc

    # Save file to disk: uploads/task-attachments/{task_id}/{uuid}{ext}
    original_suffix = Path(file.filename).suffix.lower() or ".bin"
    unique_filename = f"{uuid.uuid4()}{original_suffix}"
    upload_dir = Path("uploads") / "task-attachments" / str(task_id)
    upload_dir.mkdir(parents=True, exist_ok=True)
    dest_path = upload_dir / unique_filename

    content = await file.read()
    if len(content) > 25 * 1024 * 1024:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File too large. Maximum size is 25 MB.",
        )
    async with aiofiles.open(dest_path, "wb") as f:
        await f.write(content)

    # remote_url served by StaticFiles mount at /files/
    remote_url = f"/files/task-attachments/{task_id}/{unique_filename}"

    # Create DB record (enforces count limits)
    svc = TaskService(db)
    attachment = await svc.create_attachment(
        task_id=task_id,
        attachment_type=attachment_type,
        remote_url=remote_url,
        caption=caption,
        sort_order=sort_order,
        annotation_data=parsed_annotation_data,
        company_id=current_user.company_id,
    )
    return TaskAttachmentResponse.model_validate(attachment)


@tasks_router.get("/{task_id}/attachments", response_model=list[TaskAttachmentResponse])
async def list_task_attachments(
    task_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> list[TaskAttachmentResponse]:
    """List all non-deleted attachments for a task, ordered by sort_order."""
    from sqlalchemy import select

    from app.features.projects.models import TaskAttachment

    result = await db.execute(
        select(TaskAttachment)
        .where(TaskAttachment.task_id == task_id)
        .where(TaskAttachment.deleted_at.is_(None))
        .order_by(TaskAttachment.sort_order)
    )
    attachments = result.scalars().all()
    return [TaskAttachmentResponse.model_validate(a) for a in attachments]


@tasks_router.patch(
    "/{task_id}/attachments/{attachment_id}",
    response_model=TaskAttachmentResponse,
)
async def update_task_attachment(
    task_id: uuid.UUID,
    attachment_id: uuid.UUID,
    data: TaskAttachmentUpdate,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> TaskAttachmentResponse:
    """Update a task attachment (caption, sort_order, annotation_data)."""
    from app.features.projects.repository import TaskAttachmentRepository

    repo = TaskAttachmentRepository(db)
    update_data = data.model_dump(exclude_none=True)
    attachment = await repo.update(attachment_id, update_data)
    if attachment is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"TaskAttachment {attachment_id} not found",
        )
    return TaskAttachmentResponse.model_validate(attachment)


@tasks_router.delete(
    "/{task_id}/attachments/{attachment_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
)
async def delete_task_attachment(
    task_id: uuid.UUID,
    attachment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Soft-delete a task attachment."""
    from app.features.projects.repository import TaskAttachmentRepository

    repo = TaskAttachmentRepository(db)
    deleted = await repo.soft_delete(attachment_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"TaskAttachment {attachment_id} not found",
        )


# ---------------------------------------------------------------------------
# Contractor specialty matching endpoint
# ---------------------------------------------------------------------------


class ContractorMatchResponse(BaseModel):
    """Response schema for contractor specialty matching."""

    id: uuid.UUID
    name: str
    email: str
    has_specialty_match: bool

    model_config = {"from_attributes": True}


contractors_router = APIRouter(prefix="/contractors", tags=["contractors"])


@contractors_router.get("/", response_model=list[ContractorMatchResponse])
async def list_contractors_by_specialty(
    trade_catalog_id: uuid.UUID | None = Query(
        default=None, description="Filter and sort by specialty match for this trade catalog entry"
    ),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[ContractorMatchResponse]:
    """List contractors in the current company.

    If trade_catalog_id is provided, contractors with a matching UserTradeSpecialty
    are returned first (has_specialty_match=True), then others (has_specialty_match=False).
    Within each group, sorted by name ascending.
    """
    from sqlalchemy import String, case, func, select

    from app.features.projects.models import UserTradeSpecialty
    from app.features.users.models import User, UserRole

    # Build query: all users with contractor role in current company.
    # LEFT JOIN user_trade_specialties on (user_id, trade_catalog_id) if provided.
    if trade_catalog_id is not None:
        specialty_match_col = case(
            (UserTradeSpecialty.id.is_not(None), True),
            else_=False,
        ).label("has_specialty_match")

        stmt = (
            select(
                User.id,
                func.concat(
                    func.coalesce(User.first_name, ""),
                    " ",
                    func.coalesce(User.last_name, ""),
                )
                .cast(String)
                .label("name"),
                User.email,
                specialty_match_col,
            )
            .join(UserRole, UserRole.user_id == User.id)
            .outerjoin(
                UserTradeSpecialty,
                (UserTradeSpecialty.user_id == User.id)
                & (UserTradeSpecialty.trade_catalog_id == trade_catalog_id),
            )
            .where(UserRole.role == "contractor")
            .where(User.deleted_at.is_(None))
            .order_by(specialty_match_col.desc(), User.email)
        )
    else:
        stmt = (
            select(
                User.id,
                func.concat(
                    func.coalesce(User.first_name, ""),
                    " ",
                    func.coalesce(User.last_name, ""),
                )
                .cast(String)
                .label("name"),
                User.email,
            )
            .join(UserRole, UserRole.user_id == User.id)
            .where(UserRole.role == "contractor")
            .where(User.deleted_at.is_(None))
            .order_by(User.email)
        )

    result = await db.execute(stmt)
    rows = result.fetchall()

    return [
        ContractorMatchResponse(
            id=row.id,
            name=row.name.strip() or row.email,
            email=row.email,
            has_specialty_match=bool(row.has_specialty_match) if trade_catalog_id else False,
        )
        for row in rows
    ]


# ---------------------------------------------------------------------------
# Phase 20: Dependency engine endpoints
# ---------------------------------------------------------------------------

dependencies_router = APIRouter(tags=["dependencies"])


@dependencies_router.post(
    "/tasks/{task_id}/dependencies",
    response_model=TaskDependencyResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_dependency(
    task_id: uuid.UUID,
    data: TaskDependencyCreate,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> TaskDependencyResponse:
    """Create a dependency edge: data.predecessor_task_id -> task_id (successor).

    Returns 422 with cycle path if the new edge would create a cycle.
    """
    svc = DependencyService(db)
    dep = await svc.create_dependency(task_id, data)
    return TaskDependencyResponse.model_validate(dep)


@dependencies_router.get(
    "/tasks/{task_id}/dependencies",
    response_model=list[TaskDependencyResponse],
)
async def list_dependencies(
    task_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> list[TaskDependencyResponse]:
    """List all dependency edges where this task is a predecessor or successor."""
    svc = DependencyService(db)
    deps = await svc.list_by_task(task_id)
    return [TaskDependencyResponse.model_validate(d) for d in deps]


@dependencies_router.delete(
    "/dependencies/{dependency_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
)
async def delete_dependency(
    dependency_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Soft-delete a dependency edge. Recomputes successor's blocked status."""
    svc = DependencyService(db)
    if not await svc.delete_dependency(dependency_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Dependency {dependency_id} not found",
        )


# ---------------------------------------------------------------------------
# Phase 20: Project zones endpoints
# ---------------------------------------------------------------------------

zones_router = APIRouter(tags=["zones"])


@zones_router.post(
    "/projects/{project_id}/zones",
    response_model=ProjectZoneResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_zone(
    project_id: uuid.UUID,
    data: ProjectZoneCreate,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> ProjectZoneResponse:
    """Create a named zone for a project."""
    svc = ProjectZoneService(db)
    zone = await svc.create(project_id, data)
    return ProjectZoneResponse.model_validate(zone)


@zones_router.get(
    "/projects/{project_id}/zones",
    response_model=list[ProjectZoneResponse],
)
async def list_zones(
    project_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> list[ProjectZoneResponse]:
    """List all zones for a project."""
    svc = ProjectZoneService(db)
    zones = await svc.list_by_project(project_id)
    return [ProjectZoneResponse.model_validate(z) for z in zones]


@zones_router.delete(
    "/zones/{zone_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
)
async def delete_zone(
    zone_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Soft-delete a zone."""
    svc = ProjectZoneService(db)
    if not await svc.delete(zone_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Zone {zone_id} not found",
        )


# ---------------------------------------------------------------------------
# Phase 20: Conflict detection endpoint
# ---------------------------------------------------------------------------

conflicts_router = APIRouter(tags=["conflicts"])


@conflicts_router.get(
    "/projects/{project_id}/conflicts",
    response_model=list[ConflictRecord],
)
async def get_conflicts(
    project_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> list[ConflictRecord]:
    """Detect cross-trade zone/date scheduling conflicts for a project."""
    svc = ConflictService(db)
    conflicts = await svc.detect_conflicts(project_id)
    return [ConflictRecord(**c) for c in conflicts]


# ---------------------------------------------------------------------------
# Aggregate router — all project sub-routers under one include
# ---------------------------------------------------------------------------
router.include_router(projects_router)
router.include_router(trade_catalog_router)
router.include_router(trade_scopes_router)
router.include_router(tasks_router)
router.include_router(contractors_router)
router.include_router(dependencies_router)
router.include_router(zones_router)
router.include_router(conflicts_router)
