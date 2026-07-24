"""Foreman REST API endpoints.

POST   /api/v1/foreman/assignments                     — assign foreman to project (admin only)
DELETE /api/v1/foreman/assignments/{id}                — unassign (admin only)
GET    /api/v1/foreman/assignments/project/{project_id} — list foremen on a project
GET    /api/v1/foreman/assignments/me                  — list my assigned projects (foreman)
POST   /api/v1/foreman/status-updates                  — create status update (assigned foreman)
GET    /api/v1/foreman/status-updates/{project_id}     — list status updates
GET    /api/v1/foreman/status-updates/{project_id}/latest — latest update

All endpoints require authentication via Depends(get_current_user).
"""

from __future__ import annotations

import contextlib
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import (
    ADMIN_ROLES,
    GC_ROLES,
    CurrentUser,
    get_current_user,
    require_permission,
    require_roles,
)
from app.features.foreman.repository import ProjectAssignmentRepository
from app.features.foreman.schemas import (
    ProjectAssignmentCreate,
    ProjectAssignmentResponse,
    StatusUpdateCreate,
    StatusUpdateListResponse,
    StatusUpdateResponse,
)
from app.features.foreman.service import ForemanService

router = APIRouter(prefix="/foreman", tags=["foreman"])


def _format_user_name(user) -> str:
    """Build display name from user first/last name, falling back to email."""
    parts = [user.first_name or "", user.last_name or ""]
    name = " ".join(parts).strip()
    return name or getattr(user, "email", "")


def _assignment_response(obj) -> ProjectAssignmentResponse:
    """Serialize an assignment ORM object, enriching denormalized name fields."""
    resp = ProjectAssignmentResponse.model_validate(obj)
    with contextlib.suppress(Exception):
        resp.project_name = obj.project.name
        resp.user_name = _format_user_name(obj.user)
    return resp


def _status_update_response(obj) -> StatusUpdateResponse:
    """Serialize a status-update ORM object, enriching the author_name field."""
    resp = StatusUpdateResponse.model_validate(obj)
    with contextlib.suppress(Exception):
        resp.author_name = _format_user_name(obj.author)
    return resp


def _require_contractor_or_admin(current_user: CurrentUser) -> None:
    """Raise 403 unless the user has the contractor, owner, or admin role."""
    require_roles(
        current_user, "contractor", *ADMIN_ROLES, detail="Contractor or admin role required"
    )


async def _require_admin_or_assigned_foreman(
    current_user: CurrentUser,
    db: AsyncSession,
    project_id: uuid.UUID,
) -> None:
    """Allow owner/admin/gc; otherwise require a contractor assigned to the project."""
    if any(role in current_user.roles for role in GC_ROLES):
        return
    require_roles(current_user, "contractor", detail="Admin or contractor role required")
    assigned_ids = await ProjectAssignmentRepository(db).get_project_ids_for_user(
        current_user.user_id
    )
    if project_id not in assigned_ids:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not assigned to this project",
        )


# ---------------------------------------------------------------------------
# Assignment endpoints
# ---------------------------------------------------------------------------


@router.post(
    "/assignments",
    response_model=ProjectAssignmentResponse,
    status_code=status.HTTP_201_CREATED,
)
async def assign_foreman(
    data: ProjectAssignmentCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> ProjectAssignmentResponse:
    """Assign a foreman to a project. Admin only."""
    await require_permission("foreman.assign")(current_user, db)

    svc = ForemanService(db)
    assignment = await svc.assign_to_project(data.project_id, data.user_id)

    # Eagerly re-fetch with joins for the enriched response.
    full = await ProjectAssignmentRepository(db).get_by_id(assignment.id) or assignment
    return _assignment_response(full)


@router.delete(
    "/assignments/{assignment_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
)
async def unassign_foreman(
    assignment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Remove a foreman from a project. Admin only."""
    await require_permission("foreman.assign")(current_user, db)

    svc = ForemanService(db)
    await svc.unassign_from_project(assignment_id)


@router.get(
    "/assignments/project/{project_id}",
    response_model=list[ProjectAssignmentResponse],
)
async def list_project_foremen(
    project_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[ProjectAssignmentResponse]:
    """List all foremen assigned to a project. Admin or assigned contractor."""
    await _require_admin_or_assigned_foreman(current_user, db, project_id)

    svc = ForemanService(db)
    assignments = await svc.get_project_assignments(project_id)
    return [_assignment_response(a) for a in assignments]


@router.get(
    "/assignments/me",
    response_model=list[ProjectAssignmentResponse],
)
async def list_my_assignments(
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[ProjectAssignmentResponse]:
    """List projects assigned to the current user (foreman view)."""
    _require_contractor_or_admin(current_user)

    svc = ForemanService(db)
    assignments = await svc.get_assigned_projects(current_user.user_id)
    return [_assignment_response(a) for a in assignments]


# ---------------------------------------------------------------------------
# Status update endpoints
# ---------------------------------------------------------------------------


@router.post(
    "/status-updates",
    response_model=StatusUpdateResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_status_update(
    data: StatusUpdateCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> StatusUpdateResponse:
    """Create a daily status update. Must be an assigned foreman (contractor) for the project."""
    _require_contractor_or_admin(current_user)

    svc = ForemanService(db)
    update = await svc.create_status_update(data, author_id=current_user.user_id)
    return _status_update_response(update)


@router.get(
    "/status-updates/{project_id}",
    response_model=StatusUpdateListResponse,
)
async def list_status_updates(
    project_id: uuid.UUID,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> StatusUpdateListResponse:
    """List status updates for a project. Admin or assigned foreman (contractor)."""
    await _require_admin_or_assigned_foreman(current_user, db, project_id)

    svc = ForemanService(db)
    items, total = await svc.get_status_updates(project_id, limit=limit, offset=offset)
    update_responses = [_status_update_response(item) for item in items]

    return StatusUpdateListResponse(
        items=update_responses,
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get(
    "/status-updates/{project_id}/latest",
    response_model=StatusUpdateResponse | None,
)
async def get_latest_status_update(
    project_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> StatusUpdateResponse | None:
    """Get the most recent status update for a project."""
    svc = ForemanService(db)
    update = await svc.get_latest_status(project_id)
    if update is None:
        return None
    return _status_update_response(update)
