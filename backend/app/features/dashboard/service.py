"""DashboardService — project status aggregation, schedule slip detection, and alert management.

Provides:
- get_project_status_cards: aggregate per-project and per-trade status for GC overview
- get_trade_tasks: full task list for a trade scope drill-down
- get_trade_timeline: Gantt-ready data for a project
- detect_schedule_slips: AI-powered schedule slip detection and alert creation
- accept_rescheduling: apply AI-suggested task date changes
- dismiss_alert / mark_alert_read: alert lifecycle management

Design notes:
- All queries use selectinload — N+1 safe
- Claude API calls are non-streaming (batch alert generation)
- asyncio.sleep(0.5) between Claude calls to respect rate limits
- Each scope's alert generation wrapped in try/except — errors logged, continue
- No db.commit() — caller (cron job or get_db) handles transaction lifecycle
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
from app.features.dashboard.models import DashboardAlert
from app.features.dashboard.prompts.alert_system import ALERT_SYSTEM_PROMPT
from app.features.dashboard.repository import AlertRepository
from app.features.dashboard.schemas import (
    DependencyLink,
    ProjectStatusCard,
    TradeStatusBadge,
    TradeTaskDetail,
    TradeTimelineResponse,
    TradeTimelineScope,
)
from app.features.projects.models import Project, Task, TaskDependency, TradeScope

logger = logging.getLogger(__name__)

_CLAUDE_MODEL = "claude-sonnet-4-6"
_MAX_TOKENS = 2048

_anthropic_client = AsyncAnthropic()

_DONE_STATUSES = frozenset({"complete", "cancelled"})

_JSON_FENCE_PATTERN = re.compile(r"```(?:json)?\s*(.*?)```", re.DOTALL)


def _strip_fences(text: str) -> str:
    """Remove markdown code fences from AI response if present."""
    match = _JSON_FENCE_PATTERN.search(text)
    if match:
        return match.group(1).strip()
    return text.strip()


def _compute_trade_status(tasks: list[Task], today: date) -> str:
    """Compute a trade scope's status badge from its tasks.

    Returns 'blocked', 'at_risk', or 'on_track' (checked in that order).
    - blocked: any task has status='blocked'
    - at_risk: any incomplete task is past its due_date
    - on_track: all tasks within schedule
    """
    for task in tasks:
        if task.status == "blocked":
            return "blocked"

    for task in tasks:
        if task.status not in _DONE_STATUSES and task.due_date and task.due_date < today:
            return "at_risk"

    return "on_track"


class DashboardService(TenantScopedService[DashboardAlert]):
    """Service for GC dashboard project status, timeline, and alert management."""

    repository_class = AlertRepository

    # Typed reference for IDE completion
    repository: AlertRepository

    # -------------------------------------------------------------------------
    # Project status cards
    # -------------------------------------------------------------------------

    async def get_project_status_cards(self, company_id: uuid.UUID) -> list[ProjectStatusCard]:
        """Aggregate per-project and per-trade status for the GC dashboard overview.

        Single query with full hierarchy. Computes completion percentages and status
        badges per trade scope, then queries alert counts per project.

        Returns list of ProjectStatusCard — each card is fully self-contained.
        """
        today = date.today()

        stmt = (
            select(Project)
            .where(
                Project.company_id == company_id,
                Project.status.in_(["planning", "active", "on_hold"]),
                Project.deleted_at.is_(None),
            )
            .options(
                selectinload(Project.trade_scopes).selectinload(TradeScope.tasks),
            )
        )
        result = await self.db.execute(stmt)
        projects = list(result.scalars().all())

        cards: list[ProjectStatusCard] = []
        for project in projects:
            trade_statuses: list[TradeStatusBadge] = []
            total_tasks = 0
            completed_tasks = 0

            for scope in project.trade_scopes:
                if scope.deleted_at is not None:
                    continue

                scope_tasks = [t for t in scope.tasks if t.deleted_at is None]
                scope_total = len(scope_tasks)
                scope_completed = sum(1 for t in scope_tasks if t.status == "complete")

                total_tasks += scope_total
                completed_tasks += scope_completed

                scope_completion = (
                    round(scope_completed / scope_total * 100, 1) if scope_total > 0 else 0.0
                )
                scope_status = _compute_trade_status(scope_tasks, today)

                trade_statuses.append(
                    TradeStatusBadge(
                        trade_scope_id=scope.id,
                        trade_name=scope.trade_name,
                        status=scope_status,
                        completion_pct=scope_completion,
                        task_count=scope_total,
                        completed_count=scope_completed,
                    )
                )

            overall_pct = round(completed_tasks / total_tasks * 100, 1) if total_tasks > 0 else 0.0

            alert_count = await self.repository.count_active_for_project(project.id)

            cards.append(
                ProjectStatusCard(
                    project_id=project.id,
                    project_name=project.name,
                    status=project.status,
                    overall_completion_pct=overall_pct,
                    trade_statuses=trade_statuses,
                    active_alert_count=alert_count,
                )
            )

        return cards

    # -------------------------------------------------------------------------
    # Trade task drill-down
    # -------------------------------------------------------------------------

    async def get_trade_tasks(self, trade_scope_id: uuid.UUID) -> list[TradeTaskDetail]:
        """Return all tasks for a trade scope with dependency and assignee info.

        Used for the GC drill-down view when a trade badge is tapped.
        """
        stmt = (
            select(TradeScope)
            .where(
                TradeScope.id == trade_scope_id,
                TradeScope.deleted_at.is_(None),
            )
            .options(selectinload(TradeScope.tasks))
        )
        result = await self.db.execute(stmt)
        scope = result.scalars().first()

        if scope is None:
            return []

        details: list[TradeTaskDetail] = []
        for task in scope.tasks:
            if task.deleted_at is not None:
                continue

            dep_status = "blocked" if task.status == "blocked" else "clear"

            details.append(
                TradeTaskDetail(
                    task_id=task.id,
                    title=task.title,
                    status=task.status,
                    assignee_name=None,  # Name lookup deferred — use user_id if needed
                    start_date=task.start_date,
                    due_date=task.due_date,
                    dependency_status=dep_status,
                )
            )

        return details

    # -------------------------------------------------------------------------
    # Trade timeline (Gantt data)
    # -------------------------------------------------------------------------

    async def get_trade_timeline(self, project_id: uuid.UUID) -> TradeTimelineResponse:
        """Return Gantt-ready timeline data for a project.

        Computes start/end dates (min/max of task dates per scope) and progress
        percentages. Also fetches cross-scope dependency links.
        """
        # Load project with scopes and tasks
        stmt = (
            select(Project)
            .where(
                Project.id == project_id,
                Project.deleted_at.is_(None),
            )
            .options(
                selectinload(Project.trade_scopes).selectinload(TradeScope.tasks),
            )
        )
        result = await self.db.execute(stmt)
        project = result.scalars().first()

        if project is None:
            return TradeTimelineResponse(
                project_id=project_id,
                project_name="",
                scopes=[],
                dependency_links=[],
            )

        scope_entries: list[TradeTimelineScope] = []
        for scope in project.trade_scopes:
            if scope.deleted_at is not None:
                continue

            scope_tasks = [t for t in scope.tasks if t.deleted_at is None]
            task_count = len(scope_tasks)
            completed_count = sum(1 for t in scope_tasks if t.status == "complete")

            # Compute date range from task dates
            start_dates = [t.start_date for t in scope_tasks if t.start_date]
            end_dates = [t.due_date for t in scope_tasks if t.due_date]

            scope_entries.append(
                TradeTimelineScope(
                    trade_scope_id=scope.id,
                    trade_name=scope.trade_name,
                    contractor_id=scope.contractor_id,
                    start_date=min(start_dates) if start_dates else None,
                    end_date=max(end_dates) if end_dates else None,
                    progress_pct=(
                        round(completed_count / task_count * 100, 1) if task_count > 0 else 0.0
                    ),
                    task_count=task_count,
                    completed_count=completed_count,
                )
            )

        # Fetch cross-scope dependency links (scope-to-scope links via TaskDependency)
        # We look for any task dependency where the two tasks are in different scopes
        scope_ids = [s.trade_scope_id for s in scope_entries]
        dep_links: list[DependencyLink] = []

        if scope_ids:
            dep_stmt = select(TaskDependency).where(
                TaskDependency.deleted_at.is_(None),
            )
            dep_result = await self.db.execute(dep_stmt)
            all_deps = list(dep_result.scalars().all())

            # Build task_id -> scope_id map from loaded project tasks
            task_scope_map: dict[uuid.UUID, uuid.UUID] = {}
            for scope in project.trade_scopes:
                for task in scope.tasks:
                    task_scope_map[task.id] = scope.id

            seen_links: set[tuple[uuid.UUID, uuid.UUID]] = set()
            for dep in all_deps:
                from_scope = task_scope_map.get(dep.task_id)
                to_scope = task_scope_map.get(dep.depends_on_task_id)
                if from_scope and to_scope and from_scope != to_scope:
                    link_key = (from_scope, to_scope)
                    if link_key not in seen_links:
                        seen_links.add(link_key)
                        dep_links.append(
                            DependencyLink(
                                from_scope_id=from_scope,
                                to_scope_id=to_scope,
                                dependency_type=dep.dependency_type,
                            )
                        )

        return TradeTimelineResponse(
            project_id=project.id,
            project_name=project.name,
            scopes=scope_entries,
            dependency_links=dep_links,
        )

    # -------------------------------------------------------------------------
    # Schedule slip detection
    # -------------------------------------------------------------------------

    async def detect_schedule_slips(
        self,
        company_id: uuid.UUID,
        target_date: date,
    ) -> int:
        """Detect schedule slips across all active projects and generate AI alerts.

        For each trade scope where any task is more than 1 day past its due_date,
        calls Claude to generate an impact/remediation alert and stores it in
        dashboard_alerts.

        Returns the number of alerts generated.
        """
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

        generated_count = 0
        first = True

        for project in projects:
            # Build a map of scope_id -> max_days_behind for affected scope analysis
            scope_days_behind: dict[uuid.UUID, int] = {}
            scope_overdue_tasks: dict[uuid.UUID, list[Task]] = {}

            for scope in project.trade_scopes:
                if scope.deleted_at is not None:
                    continue

                overdue_tasks = [
                    t
                    for t in scope.tasks
                    if t.status not in _DONE_STATUSES
                    and t.deleted_at is None
                    and t.due_date is not None
                    and t.due_date < target_date
                ]

                if not overdue_tasks:
                    continue

                max_days = max((target_date - t.due_date).days for t in overdue_tasks)
                if max_days <= 1:
                    continue  # Only 1 day behind — below threshold

                scope_days_behind[scope.id] = max_days
                scope_overdue_tasks[scope.id] = overdue_tasks

            for scope in project.trade_scopes:
                if scope.id not in scope_days_behind:
                    continue

                days_behind = scope_days_behind[scope.id]
                overdue_tasks = scope_overdue_tasks[scope.id]

                # Find affected downstream scopes (scopes that depend on this one)
                affected_scope_ids = self._find_affected_downstream_scopes(
                    scope.id, project.trade_scopes, scope_days_behind
                )

                # Rate limit: sleep between Claude calls (not before first)
                if not first:
                    await asyncio.sleep(0.5)
                first = False

                try:
                    await self._generate_slip_alert(
                        company_id=company_id,
                        project=project,
                        scope=scope,
                        overdue_tasks=overdue_tasks,
                        days_behind=days_behind,
                        affected_scope_ids=affected_scope_ids,
                    )
                    generated_count += 1
                except Exception:
                    logger.exception(
                        "detect_schedule_slips: failed for scope %s project %s — continuing",
                        scope.id,
                        project.id,
                    )

        logger.info(
            "detect_schedule_slips: generated %d alerts for company %s date %s",
            generated_count,
            company_id,
            target_date,
        )
        return generated_count

    def _find_affected_downstream_scopes(
        self,
        slipping_scope_id: uuid.UUID,
        all_scopes: list[TradeScope],
        scope_days_behind: dict[uuid.UUID, int],
    ) -> list[str]:
        """Find scope IDs that may be affected by a slipping scope.

        Simple heuristic: scopes that are also behind schedule are likely downstream.
        Full dependency graph traversal is expensive here; use sort_order as a proxy
        (scopes with higher sort_order likely depend on lower sort_order scopes).
        """
        slipping_scope = next((s for s in all_scopes if s.id == slipping_scope_id), None)
        if slipping_scope is None:
            return []

        affected = []
        for scope in all_scopes:
            if scope.id == slipping_scope_id:
                continue
            if scope.deleted_at is not None:
                continue
            # Scopes that come after the slipping scope (by sort_order) may be affected
            if scope.sort_order > slipping_scope.sort_order:
                affected.append(str(scope.id))

        return affected

    async def _generate_slip_alert(
        self,
        company_id: uuid.UUID,
        project: Project,
        scope: TradeScope,
        overdue_tasks: list[Task],
        days_behind: int,
        affected_scope_ids: list[str],
    ) -> DashboardAlert:
        """Generate AI alert for a schedule slip and store in dashboard_alerts."""
        user_content = self._build_slip_content(
            project, scope, overdue_tasks, days_behind, affected_scope_ids
        )

        response = await _anthropic_client.messages.create(
            model=_CLAUDE_MODEL,
            max_tokens=_MAX_TOKENS,
            system=ALERT_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": user_content}],
        )

        raw_text = response.content[0].text
        cleaned = _strip_fences(raw_text)

        try:
            alert_data: dict[str, Any] = json.loads(cleaned)
        except json.JSONDecodeError:
            logger.warning(
                "_generate_slip_alert: Claude returned invalid JSON for scope %s — "
                "using default alert. Raw: %s...",
                scope.id,
                cleaned[:200],
            )
            alert_data = {
                "impact_text": f"{scope.trade_name} is {days_behind} days behind schedule.",
                "remediation_text": "Review overdue tasks and update the schedule.",
                "severity": "warning" if days_behind <= 7 else "critical",
                "rescheduling_suggestions": [],
            }

        severity = alert_data.get("severity", "warning")
        if severity not in ("info", "warning", "critical"):
            severity = "warning"

        rescheduling = alert_data.get("rescheduling_suggestions", [])
        rescheduling_payload = {"suggestions": rescheduling} if rescheduling else None

        alert = DashboardAlert(
            company_id=company_id,
            project_id=project.id,
            trade_scope_id=scope.id,
            severity=severity,
            alert_type="schedule_slip",
            days_behind=days_behind,
            impact_text=alert_data.get("impact_text", ""),
            remediation_text=alert_data.get("remediation_text"),
            affected_scope_ids=affected_scope_ids,
            is_read=False,
            rescheduling_payload=rescheduling_payload,
            rescheduling_accepted=None,
        )

        self.db.add(alert)
        await self.db.flush()
        await self.db.refresh(alert)
        return alert

    def _build_slip_content(
        self,
        project: Project,
        scope: TradeScope,
        overdue_tasks: list[Task],
        days_behind: int,
        affected_scope_ids: list[str],
    ) -> str:
        """Build the user message content for Claude's schedule slip analysis."""
        lines = [
            f"Project: {project.name}",
            f"Trade scope: {scope.trade_name}",
            f"Days behind schedule: {days_behind}",
            "",
            "Overdue tasks:",
        ]

        for task in overdue_tasks:
            due_str = f"(due {task.due_date.isoformat()})" if task.due_date else ""
            lines.append(f"- task_id={task.id} | {task.title} {due_str} [{task.status}]")

        if affected_scope_ids:
            lines.extend(
                [
                    "",
                    f"Downstream scopes potentially affected: {len(affected_scope_ids)} scope(s)",
                ]
            )

        if project.description:
            lines.extend(["", f"Project context: {project.description}"])

        return "\n".join(lines)

    # -------------------------------------------------------------------------
    # Alert lifecycle management
    # -------------------------------------------------------------------------

    async def mark_alert_read(self, alert_id: uuid.UUID) -> DashboardAlert | None:
        """Mark an alert as read."""
        return await self.repository.mark_read(alert_id)

    async def dismiss_alert(self, alert_id: uuid.UUID) -> DashboardAlert | None:
        """Dismiss an alert without applying rescheduling suggestions."""
        return await self.repository.dismiss_alert(alert_id)

    async def accept_rescheduling(self, alert_id: uuid.UUID) -> DashboardAlert | None:
        """Accept rescheduling suggestions — update task dates and mark alert accepted.

        Loads the alert's rescheduling_payload and applies each suggestion's
        new_start_date / new_due_date to the corresponding task. Marks the alert
        as accepted (rescheduling_accepted=True).
        """
        alert = await self.repository.get_by_id(alert_id)
        if alert is None:
            return None

        payload = alert.rescheduling_payload
        if payload and "suggestions" in payload:
            suggestions = payload["suggestions"]
            for suggestion in suggestions:
                task_id_str = suggestion.get("task_id")
                new_start_str = suggestion.get("new_start_date")
                new_due_str = suggestion.get("new_due_date")

                if not task_id_str:
                    continue

                try:
                    task_id = uuid.UUID(task_id_str)
                except ValueError:
                    logger.warning(
                        "accept_rescheduling: invalid task_id '%s' in alert %s",
                        task_id_str,
                        alert_id,
                    )
                    continue

                from app.features.projects.models import Task

                task = await self.db.get(Task, task_id)
                if task is None:
                    logger.warning(
                        "accept_rescheduling: task %s not found for alert %s",
                        task_id,
                        alert_id,
                    )
                    continue

                if new_start_str:
                    try:
                        task.start_date = date.fromisoformat(new_start_str)
                    except ValueError:
                        logger.warning(
                            "accept_rescheduling: invalid new_start_date '%s'", new_start_str
                        )

                if new_due_str:
                    try:
                        task.due_date = date.fromisoformat(new_due_str)
                    except ValueError:
                        logger.warning(
                            "accept_rescheduling: invalid new_due_date '%s'", new_due_str
                        )

            await self.db.flush()

        return await self.repository.accept_rescheduling(alert_id)

    async def get_alerts(
        self,
        project_id: uuid.UUID | None = None,
    ) -> list[DashboardAlert]:
        """Return alerts for the current tenant, optionally filtered by project."""
        if project_id is not None:
            return await self.repository.get_for_project(project_id)
        return await self.repository.get_unread_for_company()
