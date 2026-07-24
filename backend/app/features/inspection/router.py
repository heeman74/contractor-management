"""REST API router for the GC Inspection Workflow.

7 endpoints:
  POST   /tasks/{task_id}/inspect                  — GC approves or rejects a task
  POST   /projects/{project_id}/flags              — Create a site walk flag
  GET    /projects/{project_id}/flags              — List flags for a project
  PATCH  /flags/{flag_id}/convert                  — Convert flag to punch list item
  POST   /projects/{project_id}/punch-items        — Create a punch list item directly
  GET    /trade-scopes/{scope_id}/punch-items      — List punch items for a scope
  PATCH  /punch-items/{item_id}                    — Update a punch list item

All endpoints require Depends(get_current_user).
The inspect endpoint additionally enforces GC/admin role.

Router functions are thin — all business logic is delegated to the service layer.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user, require_permission
from app.features.inspection.schemas import (
    ConvertFlagRequest,
    CreatePunchListItemRequest,
    CreateSiteWalkFlagRequest,
    InspectTaskRequest,
    PunchListItemResponse,
    SiteWalkFlagResponse,
    TaskInspectionResponse,
    UpdatePunchListItemRequest,
)
from app.features.inspection.service import (
    InspectionService,
    PunchListService,
    SiteWalkFlagService,
)

inspection_router = APIRouter(tags=["inspection"])


# ---------------------------------------------------------------------------
# Task inspection
# ---------------------------------------------------------------------------


@inspection_router.post(
    "/tasks/{task_id}/inspect",
    response_model=TaskInspectionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def inspect_task(
    task_id: uuid.UUID,
    body: InspectTaskRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TaskInspectionResponse:
    """GC approves or rejects a completed task.

    - decision='approved': creates a TaskInspection record; task status unchanged.
    - decision='rejected': creates a TaskInspection record, sets task.status='rejected',
      re-blocks successor tasks, and fires a FCM rejection notification (fire-and-forget).

    Requires the inspections.manage permission.
    """
    await require_permission("inspections.perform")(current_user, db)
    svc = InspectionService(db)
    inspection = await svc.inspect_task(
        task_id=task_id,
        decision=body.decision,
        checklist_results=body.checklist_results,
        rejection_reason=body.rejection_reason,
        rejection_comment=body.rejection_comment,
        rejection_photo_url=body.rejection_photo_url,
        inspector_id=current_user.user_id,
    )
    return TaskInspectionResponse.model_validate(inspection)


@inspection_router.get(
    "/tasks/{task_id}/inspections",
    response_model=list[TaskInspectionResponse],
)
async def list_task_inspections(
    task_id: uuid.UUID,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> list[TaskInspectionResponse]:
    """List all inspection records for a task (audit trail), newest first."""
    svc = InspectionService(db)
    inspections = await svc.get_inspections_for_task(task_id)
    return [TaskInspectionResponse.model_validate(i) for i in inspections]


# ---------------------------------------------------------------------------
# Site walk flags
# ---------------------------------------------------------------------------


@inspection_router.post(
    "/projects/{project_id}/flags",
    response_model=SiteWalkFlagResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_flag(
    project_id: uuid.UUID,
    body: CreateSiteWalkFlagRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SiteWalkFlagResponse:
    """Create a site walk flag on a project."""
    svc = SiteWalkFlagService(db)
    flag = await svc.create_flag(
        project_id=project_id,
        flagged_by=current_user.user_id,
        description=body.description,
        severity=body.severity,
        location_label=body.location_label,
        photo_url=body.photo_url,
        annotation_data=body.annotation_data,
    )
    return SiteWalkFlagResponse.model_validate(flag)


@inspection_router.get(
    "/projects/{project_id}/flags",
    response_model=list[SiteWalkFlagResponse],
)
async def list_flags(
    project_id: uuid.UUID,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> list[SiteWalkFlagResponse]:
    """List all flags for a project."""
    svc = SiteWalkFlagService(db)
    flags = await svc.list_flags_for_project(project_id)
    return [SiteWalkFlagResponse.model_validate(f) for f in flags]


@inspection_router.patch(
    "/flags/{flag_id}/convert",
    response_model=PunchListItemResponse,
)
async def convert_flag(
    flag_id: uuid.UUID,
    body: ConvertFlagRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> PunchListItemResponse:
    """Convert a site walk flag into a punch list item."""
    svc = SiteWalkFlagService(db)
    punch_item = await svc.convert_to_punch_item(
        flag_id=flag_id,
        trade_scope_id=body.trade_scope_id,
        priority=body.priority,
        assigned_to=body.assigned_to,
        due_date=body.due_date,
        created_by=current_user.user_id,
    )
    return PunchListItemResponse.model_validate(punch_item)


# ---------------------------------------------------------------------------
# Punch list items
# ---------------------------------------------------------------------------


@inspection_router.post(
    "/projects/{project_id}/punch-items",
    response_model=PunchListItemResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_punch_item(
    project_id: uuid.UUID,
    body: CreatePunchListItemRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> PunchListItemResponse:
    """Create a punch list item directly (without a flag)."""
    svc = PunchListService(db)
    item = await svc.create_item(
        project_id=project_id,
        trade_scope_id=body.trade_scope_id,
        created_by=current_user.user_id,
        description=body.description,
        priority=body.priority,
        assigned_to=body.assigned_to,
        photo_url=body.photo_url,
        annotation_data=body.annotation_data,
        due_date=body.due_date,
    )
    return PunchListItemResponse.model_validate(item)


@inspection_router.get(
    "/trade-scopes/{scope_id}/punch-items",
    response_model=list[PunchListItemResponse],
)
async def list_punch_items_for_scope(
    scope_id: uuid.UUID,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> list[PunchListItemResponse]:
    """List all punch list items for a trade scope."""
    svc = PunchListService(db)
    items = await svc.list_items_for_scope(scope_id)
    return [PunchListItemResponse.model_validate(i) for i in items]


@inspection_router.patch(
    "/punch-items/{item_id}",
    response_model=PunchListItemResponse,
)
async def update_punch_item(
    item_id: uuid.UUID,
    body: UpdatePunchListItemRequest,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> PunchListItemResponse:
    """Update a punch list item (status, description, priority, assigned_to, due_date)."""
    svc = PunchListService(db)
    item = await svc.update_item(
        item_id,
        **body.model_dump(exclude_none=True),
    )
    return PunchListItemResponse.model_validate(item)
