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
from app.core.security import CurrentUser, get_current_user
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


def _enrich_assignment(resp: ProjectAssignmentResponse, obj) -> None:
    """Populate denormalized project_name and user_name from eager-loaded relations."""
    with contextlib.suppress(Exception):
        resp.project_name = obj.project.name
        resp.user_name = _format_user_name(obj.user)


def _enrich_status_update(resp: StatusUpdateResponse, obj) -> None:
    """Populate denormalized author_name from eager-loaded author relation."""
    with contextlib.suppress(Exception):
        resp.author_name = _format_user_name(obj.author)


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
    if "admin" not in current_user.roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin role required",
        )

    svc = ForemanService(db)
    assignment = await svc.assign_to_project(data.project_id, data.user_id)

    # Eagerly fetch for response — re-query with joins
    from app.features.foreman.repository import ProjectAssignmentRepository

    repo = ProjectAssignmentRepository(db)
    full = await repo.get_by_id(assignment.id)
    if full is None:
        full = assignment

    resp = ProjectAssignmentResponse.model_validate(full)
    _enrich_assignment(resp, full)
    return resp


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
    if "admin" not in current_user.roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin role required",
        )

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
    if "admin" not in current_user.roles:
        if "contractor" not in current_user.roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Admin or contractor role required",
            )
        # Verify contractor is assigned as foreman to this project
        from app.features.foreman.repository import ProjectAssignmentRepository

        repo = ProjectAssignmentRepository(db)
        assigned_ids = await repo.get_project_ids_for_user(current_user.user_id)
        if project_id not in assigned_ids:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are not assigned to this project",
            )

    svc = ForemanService(db)
    assignments = await svc.get_project_assignments(project_id)
    results = []
    for a in assignments:
        resp = ProjectAssignmentResponse.model_validate(a)
        _enrich_assignment(resp, a)
        results.append(resp)
    return results


@router.get(
    "/assignments/me",
    response_model=list[ProjectAssignmentResponse],
)
async def list_my_assignments(
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[ProjectAssignmentResponse]:
    """List projects assigned to the current user (foreman view)."""
    if "contractor" not in current_user.roles and "admin" not in current_user.roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Contractor or admin role required",
        )

    svc = ForemanService(db)
    assignments = await svc.get_assigned_projects(current_user.user_id)
    results = []
    for a in assignments:
        resp = ProjectAssignmentResponse.model_validate(a)
        _enrich_assignment(resp, a)
        results.append(resp)
    return results


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
    if "contractor" not in current_user.roles and "admin" not in current_user.roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Contractor or admin role required",
        )

    svc = ForemanService(db)
    update = await svc.create_status_update(data, author_id=current_user.user_id)

    resp = StatusUpdateResponse.model_validate(update)
    _enrich_status_update(resp, update)
    return resp


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
    # Check access: admin can see all, contractor only if assigned as foreman
    if "admin" not in current_user.roles:
        if "contractor" not in current_user.roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Admin or contractor role required",
            )
        # Verify contractor is assigned as foreman
        from app.features.foreman.repository import ProjectAssignmentRepository

        repo = ProjectAssignmentRepository(db)
        assigned_ids = await repo.get_project_ids_for_user(current_user.user_id)
        if project_id not in assigned_ids:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are not assigned to this project",
            )

    svc = ForemanService(db)
    items, total = await svc.get_status_updates(project_id, limit=limit, offset=offset)

    update_responses = []
    for item in items:
        resp = StatusUpdateResponse.model_validate(item)
        _enrich_status_update(resp, item)
        update_responses.append(resp)

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

    resp = StatusUpdateResponse.model_validate(update)
    _enrich_status_update(resp, update)
    return resp
