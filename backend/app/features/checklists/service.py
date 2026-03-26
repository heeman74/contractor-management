"""ChecklistService — AI daily checklist generation and retrieval.

Generates structured JSON daily task checklists per contractor using Claude API
(non-streaming), stores them via repository, and fires FCM push notifications.

Design notes:
- Non-streaming Claude API call (messages.create, not messages.stream) — used for batch jobs
- Module-level AsyncAnthropic client reads ANTHROPIC_API_KEY from environment
- Each contractor's generation is wrapped in try/except — errors logged, continue to next
- asyncio.sleep(0.5) between Claude API calls per contractor to respect rate limits
- FCM push fires via asyncio.create_task (fire-and-forget — never blocks checklist generation)
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
import uuid
from datetime import date
from typing import Any

from anthropic import AsyncAnthropic
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.base_service import TenantScopedService
from app.features.checklists.models import DailyChecklist
from app.features.checklists.prompts.checklist_system import CHECKLIST_SYSTEM_PROMPT
from app.features.checklists.repository import ChecklistRepository
from app.features.projects.models import Project, Task, TradeScope

logger = logging.getLogger(__name__)

_CLAUDE_MODEL = "claude-sonnet-4-6"
_MAX_TOKENS = 2048

# Module-level Anthropic client — reads ANTHROPIC_API_KEY from environment
_anthropic_client = AsyncAnthropic()

# Task statuses that mean "done" — skip these when building checklist
_DONE_STATUSES = frozenset({"complete", "cancelled"})

# Strip markdown code fences if Claude wraps JSON despite instructions
_JSON_FENCE_PATTERN = re.compile(r"```(?:json)?\s*(.*?)```", re.DOTALL)


def _strip_fences(text: str) -> str:
    """Remove markdown code fences from AI response text if present."""
    match = _JSON_FENCE_PATTERN.search(text)
    if match:
        return match.group(1).strip()
    return text.strip()


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

        Queries all active projects with trade scopes and tasks (single query with
        eager loads — N+1 safe). For each trade scope with an assigned contractor and
        eligible tasks, calls Claude to generate a structured checklist JSON.

        Returns the number of checklists successfully generated.

        Design:
        - selectinload for all relationships — no lazy loads
        - asyncio.sleep(0.5) between contractors to avoid Claude rate limits
        - Each contractor's generation wrapped in try/except — log and continue on error
        - FCM push via asyncio.create_task (fire-and-forget)
        """
        from app.features.notifications.service import NotificationService

        # Single query: all active projects for this company with full hierarchy
        stmt = (
            select(Project)
            .where(
                Project.company_id == company_id,
                Project.status.in_(["planning", "active"]),
                Project.deleted_at.is_(None),
            )
            .options(
                selectinload(Project.trade_scopes).selectinload(TradeScope.tasks),
            )
        )
        result = await self.db.execute(stmt)
        projects = list(result.scalars().all())

        notification_svc = NotificationService(self.db)
        generated_count = 0
        first = True

        for project in projects:
            for scope in project.trade_scopes:
                if scope.contractor_id is None:
                    continue  # No contractor assigned — skip

                # Filter eligible tasks
                eligible_tasks = [
                    t
                    for t in scope.tasks
                    if t.status not in _DONE_STATUSES
                    and t.deleted_at is None
                    and (t.start_date is None or t.start_date <= target_date)
                ]

                if not eligible_tasks:
                    continue

                # Rate-limit: sleep between contractors (not before first)
                if not first:
                    await asyncio.sleep(0.5)
                first = False

                try:
                    checklist = await self._generate_for_scope(
                        company_id=company_id,
                        project=project,
                        scope=scope,
                        tasks=eligible_tasks,
                        target_date=target_date,
                    )
                    generated_count += 1

                    # Fire FCM push — fire-and-forget (never block checklist generation)
                    asyncio.create_task(
                        notification_svc.send_checklist_notification(
                            contractor_id=scope.contractor_id,
                            summary_text=checklist.summary_text,
                            checklist_id=checklist.id,
                        )
                    )
                except Exception:
                    logger.exception(
                        "generate_daily_checklists: failed for contractor %s scope %s "
                        "project %s — continuing",
                        scope.contractor_id,
                        scope.id,
                        project.id,
                    )

        logger.info(
            "generate_daily_checklists: generated %d checklists for company %s date %s",
            generated_count,
            company_id,
            target_date,
        )
        return generated_count

    async def _generate_for_scope(
        self,
        company_id: uuid.UUID,
        project: Project,
        scope: TradeScope,
        tasks: list[Task],
        target_date: date,
    ) -> DailyChecklist:
        """Generate and store a single checklist for a trade scope's contractor.

        Builds user_content with project/trade context, calls Claude, parses JSON,
        builds summary_text, and upserts via repository.
        """
        user_content = self._build_user_content(project, scope, tasks, target_date)

        response = await _anthropic_client.messages.create(
            model=_CLAUDE_MODEL,
            max_tokens=_MAX_TOKENS,
            system=CHECKLIST_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": user_content}],
        )

        raw_text = response.content[0].text
        cleaned = _strip_fences(raw_text)

        try:
            checklist_data = json.loads(cleaned)
        except json.JSONDecodeError:
            logger.warning(
                "_generate_for_scope: Claude returned invalid JSON for scope %s — "
                "using empty checklist. Raw: %s...",
                scope.id,
                cleaned[:200],
            )
            checklist_data = {"tasks": []}

        task_items: list[dict[str, Any]] = checklist_data.get("tasks", [])

        # Build plain-English summary for FCM notification
        top_titles = [t.get("title", "Task") for t in task_items[:3]]
        summary_text = self._build_summary(len(task_items), top_titles)

        # Upsert via repository (idempotent — safe to re-run)
        return await self.repository.upsert_checklist(
            company_id=company_id,
            contractor_id=scope.contractor_id,  # type: ignore[arg-type]
            project_id=project.id,
            trade_scope_id=scope.id,
            checklist_date=target_date,
            checklist_json=checklist_data,
            summary_text=summary_text,
        )

    def _build_user_content(
        self,
        project: Project,
        scope: TradeScope,
        tasks: list[Task],
        target_date: date,
    ) -> str:
        """Build the user message content for Claude's checklist generation."""
        lines = [
            f"Project: {project.name}",
            f"Trade: {scope.trade_name}",
            f"Date: {target_date.isoformat()}",
            "",
            "Tasks to include in today's checklist:",
        ]

        for task in tasks:
            due_str = f" (due {task.due_date.isoformat()})" if task.due_date else ""
            status_str = f" [{task.status}]" if task.status != "not_started" else ""
            priority_str = f" priority={task.priority}"
            dep_status = "blocked" if task.status == "blocked" else "clear"
            lines.append(
                f"- task_id={task.id} | {task.title}{due_str}{status_str}{priority_str} "
                f"| dep={dep_status}"
            )
            if task.materials_needed:
                materials = [
                    m.get("name", str(m)) if isinstance(m, dict) else str(m)
                    for m in task.materials_needed
                ]
                lines.append(f"  materials: {', '.join(materials)}")

        if project.description:
            lines.extend(["", f"Project notes: {project.description}"])

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
