"""ChecklistService — AI daily checklist generation and retrieval.

Generates structured JSON daily task checklists per contractor using Claude API
(non-streaming), stores them via repository, and fires FCM push notifications.

Design notes:
- Non-streaming Claude API call (messages.create, not messages.stream) — used for batch jobs
- Lazy singleton AsyncAnthropic client via get_anthropic_client()
- Each contractor's generation is wrapped in try/except — errors logged, continue to next
- Bounded concurrency on Claude API calls via gather_with_concurrency
- FCM push uses only primitive data, not the DB session
- DB data extracted into plain dicts before Claude API calls
"""

from __future__ import annotations

import asyncio
import uuid
from datetime import date
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.ai_utils import (
    ACTIVE_PROJECT_STATUSES,
    DONE_STATUSES,
    call_claude_json,
    gather_with_concurrency,
)
from app.core.base_service import TenantScopedService
from app.core.logging_config import get_logger
from app.features.checklists.models import DailyChecklist
from app.features.checklists.prompts.checklist_system import CHECKLIST_SYSTEM_PROMPT
from app.features.checklists.repository import ChecklistRepository
from app.features.projects.models import Project, TradeScope

logger = get_logger(__name__)


class ChecklistService(TenantScopedService[DailyChecklist]):
    """Service for AI daily checklist generation and retrieval."""

    repository_class = ChecklistRepository

    # Typed reference for IDE completion
    repository: ChecklistRepository

    async def generate_daily_checklists(
        self,
        company_id: uuid.UUID,
        target_date: date,
    ) -> int:
        """Generate AI checklists for all contractors in a company on target_date.

        Orchestrates the full pipeline: query eligible scopes, call Claude for each,
        persist results, and dispatch notifications.

        Returns the number of checklists successfully generated.
        """
        scope_items = await self._query_eligible_scopes(company_id, target_date)

        ai_results = await gather_with_concurrency(scope_items, self._call_claude_for_checklist)

        generated_count, notifications = await self._persist_checklists(scope_items, ai_results)

        self._dispatch_notifications(notifications)

        logger.info(
            "generate_daily_checklists: generated %d checklists for company %s date %s",
            generated_count,
            company_id,
            target_date,
        )
        return generated_count

    async def _query_eligible_scopes(
        self,
        company_id: uuid.UUID,
        target_date: date,
    ) -> list[dict[str, Any]]:
        """Query active projects and extract eligible trade scopes as plain dicts.

        Returns a list of dicts, each containing the data needed for a single
        Claude API call (no ORM objects — safe for use after session release).
        """
        stmt = (
            select(Project)
            .where(
                Project.company_id == company_id,
                Project.status.in_(ACTIVE_PROJECT_STATUSES),
                Project.deleted_at.is_(None),
            )
            .options(
                selectinload(Project.trade_scopes).selectinload(TradeScope.tasks),
            )
        )
        result = await self.db.execute(stmt)
        projects = list(result.scalars().all())

        scope_items: list[dict[str, Any]] = []

        for project in projects:
            for scope in project.trade_scopes:
                if scope.contractor_id is None:
                    continue

                eligible_tasks = [
                    t
                    for t in scope.tasks
                    if t.status not in DONE_STATUSES
                    and t.deleted_at is None
                    and (t.start_date is None or t.start_date <= target_date)
                ]

                if not eligible_tasks:
                    continue

                task_dicts = [
                    {
                        "id": str(t.id),
                        "title": t.title,
                        "due_date": t.due_date.isoformat() if t.due_date else None,
                        "status": t.status,
                        "priority": t.priority,
                        "materials_needed": t.materials_needed,
                    }
                    for t in eligible_tasks
                ]

                scope_items.append(
                    {
                        "company_id": company_id,
                        "project_id": project.id,
                        "project_name": project.name,
                        "project_description": project.description,
                        "scope_id": scope.id,
                        "trade_name": scope.trade_name,
                        "contractor_id": scope.contractor_id,
                        "tasks": task_dicts,
                        "target_date": target_date,
                    }
                )

        return scope_items

    async def _persist_checklists(
        self,
        items: list[dict[str, Any]],
        results: list[dict[str, Any] | None],
    ) -> tuple[int, list[dict[str, Any]]]:
        """Upsert checklists from AI results and collect notification data.

        Returns (generated_count, notifications_to_send).
        """
        generated_count = 0
        notifications: list[dict[str, Any]] = []

        for item, ai_result in zip(items, results, strict=False):
            if ai_result is None:
                continue

            checklist = await self.repository.upsert_checklist(
                company_id=item["company_id"],
                contractor_id=item["contractor_id"],
                project_id=item["project_id"],
                trade_scope_id=item["scope_id"],
                checklist_date=item["target_date"],
                checklist_json=ai_result["checklist_data"],
                summary_text=ai_result["summary_text"],
            )
            generated_count += 1

            notifications.append(
                {
                    "company_id": item["company_id"],
                    "contractor_id": item["contractor_id"],
                    "summary_text": ai_result["summary_text"],
                    "checklist_id": checklist.id,
                }
            )

        return generated_count, notifications

    @staticmethod
    def _dispatch_notifications(notifications: list[dict[str, Any]]) -> None:
        """Fire FCM notifications as background tasks using only primitive data.

        Each notification creates its own DB session via NotificationService.
        Task references are stored in a set to prevent garbage collection.
        """
        background_tasks: set[asyncio.Task[None]] = set()
        for notif in notifications:
            task = asyncio.create_task(
                ChecklistService._send_notification_safe(
                    company_id=notif["company_id"],
                    contractor_id=notif["contractor_id"],
                    summary_text=notif["summary_text"],
                    checklist_id=notif["checklist_id"],
                )
            )
            background_tasks.add(task)
            task.add_done_callback(background_tasks.discard)

    @staticmethod
    async def _send_notification_safe(
        company_id: uuid.UUID,
        contractor_id: uuid.UUID,
        summary_text: str,
        checklist_id: uuid.UUID,
    ) -> None:
        """Fire-and-forget FCM notification using its own DB session.

        Creates a fresh DB session for the notification service instead of reusing
        the request session which may be closed. Sets tenant context so RLS policies
        work in the background task.
        """
        try:
            from app.core.database import async_session_factory
            from app.core.tenant import set_current_tenant_id
            from app.features.notifications.service import NotificationService

            set_current_tenant_id(company_id)
            async with async_session_factory() as db:
                notification_svc = NotificationService(db)
                await notification_svc.send_checklist_notification(
                    contractor_id=contractor_id,
                    summary_text=summary_text,
                    checklist_id=checklist_id,
                )
                await db.commit()
        except Exception:
            logger.exception(
                "send_checklist_notification failed for contractor %s — continuing",
                contractor_id,
            )

    async def _call_claude_for_checklist(self, item: dict[str, Any]) -> dict[str, Any]:
        """Call Claude API for a single checklist generation.

        Takes plain dict data (no ORM objects), returns parsed checklist data.
        """
        user_content = self._build_user_content_from_dict(item)

        checklist_data = await call_claude_json(
            system_prompt=CHECKLIST_SYSTEM_PROMPT,
            user_content=user_content,
            fallback={"tasks": []},
            scope_id=item["scope_id"],
        )

        task_items: list[dict[str, Any]] = checklist_data.get("tasks", [])

        top_titles = [t.get("title", "Task") for t in task_items[:3]]
        summary_text = self._build_summary(len(task_items), top_titles)

        return {
            "checklist_data": checklist_data,
            "summary_text": summary_text,
        }

    def _build_user_content_from_dict(self, item: dict[str, Any]) -> str:
        """Build the user message content for Claude from plain dict data."""
        lines = [
            f"Project: {item['project_name']}",
            f"Trade: {item['trade_name']}",
            f"Date: {item['target_date'].isoformat()}",
            "",
            "Tasks to include in today's checklist:",
        ]

        for task in item["tasks"]:
            due_str = f" (due {task['due_date']})" if task.get("due_date") else ""
            status_str = f" [{task['status']}]" if task["status"] != "not_started" else ""
            priority_str = f" priority={task['priority']}"
            dep_status = (
                "blocked"
                if task["status"] == "blocked"
                else "waiting"
                if task["status"] == "waiting"
                else "clear"
            )
            lines.append(
                f"- task_id={task['id']} | {task['title']}{due_str}{status_str}{priority_str} "
                f"| dep={dep_status}"
            )
            materials = task.get("materials_needed", [])
            if materials:
                material_names = [
                    m.get("name", str(m)) if isinstance(m, dict) else str(m) for m in materials
                ]
                lines.append(f"  materials: {', '.join(material_names)}")

        desc = item.get("project_description")
        if desc:
            lines.extend(["", f"Project notes: {desc}"])

        return "\n".join(lines)

    def _build_summary(self, task_count: int, top_titles: list[str]) -> str:
        """Build a short FCM-ready summary from task count and top titles."""
        if task_count == 0:
            return "No tasks scheduled for today."

        tasks_word = "task" if task_count == 1 else "tasks"
        if not top_titles:
            return f"You have {task_count} {tasks_word} today."

        titles_str = ", ".join(top_titles)
        if task_count > 3:
            return f"You have {task_count} {tasks_word} today: {titles_str}, and more."
        return f"You have {task_count} {tasks_word} today: {titles_str}."

    async def get_today_checklist(
        self,
        contractor_id: uuid.UUID,
        target_date: date,
    ) -> list[DailyChecklist]:
        """Return today's checklists for a contractor (may span multiple trade scopes)."""
        return await self.repository.get_today_for_contractor(contractor_id, target_date)

    async def get_checklist_by_id(self, checklist_id: uuid.UUID) -> DailyChecklist | None:
        """Return a single checklist by ID."""
        return await self.repository.get_by_id(checklist_id)
