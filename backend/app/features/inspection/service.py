"""Services for the GC Inspection Workflow.

Provides:
- InspectionService    — inspect (approve/reject) a task, re-block successors on rejection
- SiteWalkFlagService  — create and convert flags
- PunchListService     — create, list, and update punch list items

All services inherit TenantScopedService per CLAUDE.md OOP Architecture rules.
No standalone service functions — all logic in class methods.
No db.commit() — get_db handles the transaction lifecycle.
"""

from __future__ import annotations

import asyncio
import logging
import uuid

from fastapi import HTTPException, status
from sqlalchemy import select

from app.core.base_service import TenantScopedService
from app.features.inspection.models import PunchListItem, SiteWalkFlag, TaskInspection
from app.features.inspection.repository import (
    PunchListRepository,
    SiteWalkFlagRepository,
    TaskInspectionRepository,
)
from app.features.projects.models import Task, TaskDependency

logger = logging.getLogger(__name__)


class InspectionService(TenantScopedService[TaskInspection]):
    """Business logic for GC task inspection (approve/reject).

    inspect_task:
    1. Load the task — 404 if not found or soft-deleted.
    2. Guard: task.status must be 'complete' (422 otherwise).
    3. Create TaskInspection record.
    4. On rejection:
       a. Set task.status = 'rejected'.
       b. Flush.
       c. Re-block successor tasks via reblock_successors().
       d. Fire-and-forget FCM rejection notification.
    5. Flush and return the inspection record.
    """

    repository_class = TaskInspectionRepository

    async def inspect_task(
        self,
        task_id: uuid.UUID,
        decision: str,
        checklist_results: list,
        rejection_reason: str | None,
        rejection_comment: str | None,
        rejection_photo_url: str | None,
        inspector_id: uuid.UUID,
    ) -> TaskInspection:
        """Create an inspection record and update task status on rejection."""
        company_id = self._require_tenant_id()

        # 1. Load task — 404 if not found or soft-deleted
        task = await self.db.get(Task, task_id)
        if task is None or task.deleted_at is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Task not found",
            )

        # 2. Guard: task must be complete before it can be inspected
        if task.status != "complete":
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Task status must be 'complete' to inspect — current status: {task.status}",
            )

        # 3. Create TaskInspection record
        inspection = TaskInspection(
            company_id=company_id,
            task_id=task_id,
            inspector_id=inspector_id,
            decision=decision,
            checklist_results=checklist_results,
            rejection_reason=rejection_reason,
            rejection_comment=rejection_comment,
            rejection_photo_url=rejection_photo_url,
        )
        self.db.add(inspection)
        await self.db.flush()

        # 4. On rejection: update task status + re-block successors + FCM
        if decision == "rejected":
            task.status = "rejected"
            await self.db.flush()

            # Re-block successors that were unblocked when the task was completed
            await self.reblock_successors(task_id)

            # Fire-and-forget FCM notification to contractor (task.assigned_to)
            if task.assigned_to is not None:
                try:
                    from app.features.notifications.service import NotificationService

                    notification_svc = NotificationService(self.db)
                    asyncio.create_task(
                        notification_svc.send_task_rejection_notification(
                            task_id=task_id,
                            task_title=task.title,
                            rejection_reason=rejection_reason or "No reason provided",
                            contractor_id=task.assigned_to,
                        )
                    )
                except Exception:
                    logger.exception(
                        "Failed to schedule FCM rejection notification for task %s", task_id
                    )

        # 5. Refresh and return the inspection record
        await self.db.refresh(inspection)
        return inspection

    async def reblock_successors(self, task_id: uuid.UUID) -> None:
        """Re-block successor tasks when their predecessor is rejected.

        Queries task_dependencies where predecessor_id == task_id.
        For each FS/SS/SE successor, calls DependencyService._recompute_blocked_status()
        to re-evaluate whether the successor should be blocked.

        Per RESEARCH.md Pitfall 6: successors must be re-blocked when a predecessor
        is rejected, because they were previously unblocked by the completion.
        """
        from app.features.projects.service import DependencyService

        stmt = (
            select(TaskDependency)
            .where(TaskDependency.predecessor_task_id == task_id)
            .where(TaskDependency.deleted_at.is_(None))
        )
        result = await self.db.execute(stmt)
        edges = result.scalars().all()

        if not edges:
            return

        dep_svc = DependencyService(self.db)
        for edge in edges:
            # Only FS/SS/SE dependency types block successors (FF does not)
            if edge.dependency_type in ("FS", "SS", "SE"):
                await dep_svc._recompute_blocked_status(edge.successor_task_id)

    async def get_inspections_for_task(self, task_id: uuid.UUID) -> list[TaskInspection]:
        """List all inspection records for a task (full audit trail), newest first."""
        repo = TaskInspectionRepository(self.db)
        return await repo.list_by_task(task_id)


class SiteWalkFlagService(TenantScopedService[SiteWalkFlag]):
    """Business logic for site walk flags.

    GC creates flags during a physical site walk to record observed issues.
    Flags can be converted to punch list items for formal tracking.
    """

    repository_class = SiteWalkFlagRepository

    async def create_flag(
        self,
        project_id: uuid.UUID,
        flagged_by: uuid.UUID,
        description: str,
        severity: str,
        location_label: str | None,
        photo_url: str | None,
        annotation_data: dict | None,
    ) -> SiteWalkFlag:
        """Create a site walk flag for a project."""
        company_id = self._require_tenant_id()

        flag = SiteWalkFlag(
            company_id=company_id,
            project_id=project_id,
            flagged_by=flagged_by,
            description=description,
            severity=severity,
            location_label=location_label,
            photo_url=photo_url,
            annotation_data=annotation_data,
            status="open",
        )
        self.db.add(flag)
        await self.db.flush()
        await self.db.refresh(flag)
        return flag

    async def list_flags_for_project(self, project_id: uuid.UUID) -> list[SiteWalkFlag]:
        """List all non-deleted flags for a project."""
        repo = SiteWalkFlagRepository(self.db)
        return await repo.list_by_project(project_id)

    async def convert_to_punch_item(
        self,
        flag_id: uuid.UUID,
        trade_scope_id: uuid.UUID,
        priority: str,
        assigned_to: uuid.UUID | None,
        due_date,
        created_by: uuid.UUID,
    ) -> PunchListItem:
        """Convert a site walk flag to a punch list item.

        1. Load flag — 404 if not found.
        2. Guard: flag.status must be 'open' (422 otherwise).
        3. Create PunchListItem with source_flag_id set and inheriting description/photo/annotation.
        4. Set flag.status = 'converted'.
        5. Flush and return the new PunchListItem.
        """
        company_id = self._require_tenant_id()

        flag = await self.db.get(SiteWalkFlag, flag_id)
        if flag is None or flag.deleted_at is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Flag not found",
            )

        if flag.status != "open":
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Flag must be 'open' to convert — current status: {flag.status}",
            )

        # Create the punch list item inheriting flag data
        punch_item = PunchListItem(
            company_id=company_id,
            project_id=flag.project_id,
            trade_scope_id=trade_scope_id,
            created_by=created_by,
            assigned_to=assigned_to,
            description=flag.description,
            priority=priority,
            status="open",
            photo_url=flag.photo_url,
            annotation_data=flag.annotation_data,
            source_flag_id=flag_id,
            due_date=due_date,
        )
        self.db.add(punch_item)

        # Mark the source flag as converted
        flag.status = "converted"

        await self.db.flush()
        await self.db.refresh(punch_item)
        return punch_item


class PunchListService(TenantScopedService[PunchListItem]):
    """Business logic for punch list items.

    Punch list items represent defects or open issues that must be resolved
    before a trade scope can be formally closed out.
    """

    repository_class = PunchListRepository

    async def create_item(
        self,
        project_id: uuid.UUID,
        trade_scope_id: uuid.UUID,
        created_by: uuid.UUID,
        description: str,
        priority: str,
        assigned_to: uuid.UUID | None,
        photo_url: str | None,
        annotation_data: dict | None,
        due_date,
    ) -> PunchListItem:
        """Create a punch list item for a trade scope."""
        company_id = self._require_tenant_id()

        item = PunchListItem(
            company_id=company_id,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            created_by=created_by,
            assigned_to=assigned_to,
            description=description,
            priority=priority,
            status="open",
            photo_url=photo_url,
            annotation_data=annotation_data,
            due_date=due_date,
        )
        self.db.add(item)
        await self.db.flush()
        await self.db.refresh(item)
        return item

    async def list_items_for_scope(self, trade_scope_id: uuid.UUID) -> list[PunchListItem]:
        """List all non-deleted punch list items for a trade scope."""
        repo = PunchListRepository(self.db)
        return await repo.list_by_scope(trade_scope_id)

    async def list_items_for_project(self, project_id: uuid.UUID) -> list[PunchListItem]:
        """List all non-deleted punch list items for a project."""
        repo = PunchListRepository(self.db)
        return await repo.list_by_project(project_id)

    async def update_item(self, item_id: uuid.UUID, **kwargs) -> PunchListItem:
        """Partial update a punch list item (status, description, priority, assigned_to, due_date)."""
        item = await self.db.get(PunchListItem, item_id)
        if item is None or item.deleted_at is not None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Punch list item not found",
            )

        # Apply only the provided fields (skip None values)
        for field, value in kwargs.items():
            if value is not None:
                setattr(item, field, value)

        await self.db.flush()
        await self.db.refresh(item)
        return item
