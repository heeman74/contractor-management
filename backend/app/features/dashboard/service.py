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
- asyncio.Semaphore(5) for bounded concurrency on AI calls
- Each scope's alert generation wrapped in try/except — errors logged, continue
- No db.commit() — caller (cron job or get_db) handles transaction lifecycle
- DB session is released before Claude API calls to avoid holding connections
"""

from __future__ import annotations

import asyncio
import json
import logging
import uuid
from datetime import date
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import selectinload

from app.core.ai_utils import (
    CLAUDE_MAX_TOKENS,
    CLAUDE_MODEL,
    DONE_STATUSES,
    get_anthropic_client,
    strip_fences,
)
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
        if task.status not in DONE_STATUSES and task.due_date and task.due_date < today:
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
        badges per trade scope. Alert counts fetched in a single GROUP BY query
        (SCALE-1: avoids N+1 per-project count queries).

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

        # SCALE-1: Batch-fetch alert counts for all projects in one GROUP BY query
        project_ids = [p.id for p in projects]
        alert_counts: dict[uuid.UUID, int] = {}
        if project_ids:
            alert_stmt = (
                select(DashboardAlert.project_id, func.count())
                .where(
                    DashboardAlert.project_id.in_(project_ids),
                    DashboardAlert.is_read.is_(False),
                    DashboardAlert.deleted_at.is_(None),
                )
                .group_by(DashboardAlert.project_id)
            )
            alert_result = await self.db.execute(alert_stmt)
            for pid, cnt in alert_result.all():
                alert_counts[pid] = cnt

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

            cards.append(
                ProjectStatusCard(
                    project_id=project.id,
                    project_name=project.name,
                    status=project.status,
                    overall_completion_pct=overall_pct,
                    trade_statuses=trade_statuses,
                    active_alert_count=alert_counts.get(project.id, 0),
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
        # Build task_id -> scope_id map from loaded project tasks
        task_scope_map: dict[uuid.UUID, uuid.UUID] = {}
        task_ids: list[uuid.UUID] = []

        for scope in project.trade_scopes:
            if scope.deleted_at is not None:
                continue

            scope_tasks = [t for t in scope.tasks if t.deleted_at is None]
            task_count = len(scope_tasks)
            completed_count = sum(1 for t in scope_tasks if t.status == "complete")

            for task in scope_tasks:
                task_scope_map[task.id] = scope.id
                task_ids.append(task.id)

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

        # BUG-5: Filter dependencies to only those involving tasks in this project
        dep_links: list[DependencyLink] = []

        if task_ids:
            # BUG-2: Use correct field names (predecessor_task_id, successor_task_id)
            dep_stmt = select(TaskDependency).where(
                TaskDependency.deleted_at.is_(None),
                (
                    TaskDependency.predecessor_task_id.in_(task_ids)
                    | TaskDependency.successor_task_id.in_(task_ids)
                ),
            )
            dep_result = await self.db.execute(dep_stmt)
            all_deps = list(dep_result.scalars().all())

            seen_links: set[tuple[uuid.UUID, uuid.UUID]] = set()
            for dep in all_deps:
                # BUG-2: Use correct field names
                from_scope = task_scope_map.get(dep.predecessor_task_id)
                to_scope = task_scope_map.get(dep.successor_task_id)
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

        BP-9: Checks for existing unread alerts before creating duplicates.
        THRU-2: Extracts all DB data first, then makes AI calls.
        SCALE-2: Uses asyncio.Semaphore(5) for bounded concurrency.

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

        # BP-9: Pre-fetch existing unread alerts to avoid duplicates
        existing_alerts_stmt = (
            select(
                DashboardAlert.project_id,
                DashboardAlert.trade_scope_id,
                DashboardAlert.alert_type,
            )
            .where(
                DashboardAlert.company_id == company_id,
                DashboardAlert.is_read.is_(False),
                DashboardAlert.deleted_at.is_(None),
                DashboardAlert.alert_type == "schedule_slip",
            )
        )
        existing_result = await self.db.execute(existing_alerts_stmt)
        existing_alert_keys: set[tuple[uuid.UUID, uuid.UUID | None, str]] = {
            (row[0], row[1], row[2]) for row in existing_result.all()
        }

        # THRU-2: Extract all needed data from DB into plain dicts/lists before AI calls
        slip_items: list[dict[str, Any]] = []

        for project in projects:
            scope_days_behind: dict[uuid.UUID, int] = {}
            scope_overdue_tasks: dict[uuid.UUID, list[dict[str, Any]]] = {}

            for scope in project.trade_scopes:
                if scope.deleted_at is not None:
                    continue

                overdue_tasks = [
                    t
                    for t in scope.tasks
                    if t.status not in DONE_STATUSES
                    and t.deleted_at is None
                    and t.due_date is not None
                    and t.due_date < target_date
                ]

                if not overdue_tasks:
                    continue

                max_days = max((target_date - t.due_date).days for t in overdue_tasks)
                if max_days <= 1:
                    continue

                scope_days_behind[scope.id] = max_days
                # Serialize task data to plain dicts so we don't need the session later
                scope_overdue_tasks[scope.id] = [
                    {
                        "id": str(t.id),
                        "title": t.title,
                        "due_date": t.due_date.isoformat() if t.due_date else None,
                        "status": t.status,
                    }
                    for t in overdue_tasks
                ]

            for scope in project.trade_scopes:
                if scope.id not in scope_days_behind:
                    continue

                # BP-9: Skip if unread alert already exists for this project+scope+type
                alert_key = (project.id, scope.id, "schedule_slip")
                if alert_key in existing_alert_keys:
                    logger.debug(
                        "detect_schedule_slips: skipping duplicate alert for "
                        "project=%s scope=%s",
                        project.id,
                        scope.id,
                    )
                    continue

                days_behind = scope_days_behind[scope.id]
                overdue_task_dicts = scope_overdue_tasks[scope.id]

                affected_scope_ids = self._find_affected_downstream_scopes(
                    scope.id, project.trade_scopes, scope_days_behind
                )

                slip_items.append(
                    {
                        "company_id": company_id,
                        "project_id": project.id,
                        "project_name": project.name,
                        "project_description": project.description,
                        "scope_id": scope.id,
                        "trade_name": scope.trade_name,
                        "overdue_tasks": overdue_task_dicts,
                        "days_behind": days_behind,
                        "affected_scope_ids": affected_scope_ids,
                    }
                )

        # THRU-2/SCALE-2: Make AI calls with bounded concurrency (no DB session needed)
        semaphore = asyncio.Semaphore(5)
        generated_count = 0

        async def _process_slip(item: dict[str, Any]) -> dict[str, Any] | None:
            async with semaphore:
                try:
                    return await self._call_claude_for_slip(item)
                except Exception:
                    logger.exception(
                        "detect_schedule_slips: Claude call failed for scope %s project %s",
                        item["scope_id"],
                        item["project_id"],
                    )
                    return None

        ai_results = await asyncio.gather(*[_process_slip(item) for item in slip_items])

        # Write all results back to DB
        for item, ai_result in zip(slip_items, ai_results):
            if ai_result is None:
                continue

            alert = DashboardAlert(
                company_id=item["company_id"],
                project_id=item["project_id"],
                trade_scope_id=item["scope_id"],
                severity=ai_result["severity"],
                alert_type="schedule_slip",
                days_behind=item["days_behind"],
                impact_text=ai_result["impact_text"],
                remediation_text=ai_result.get("remediation_text"),
                affected_scope_ids=item["affected_scope_ids"],
                is_read=False,
                rescheduling_payload=ai_result.get("rescheduling_payload"),
                rescheduling_accepted=None,
            )

            self.db.add(alert)
            generated_count += 1

        if generated_count > 0:
            await self.db.flush()

        logger.info(
            "detect_schedule_slips: generated %d alerts for company %s date %s",
            generated_count,
            company_id,
            target_date,
        )
        return generated_count

    async def _call_claude_for_slip(self, item: dict[str, Any]) -> dict[str, Any]:
        """Call Claude API for a single schedule slip analysis.

        Takes plain dict data (no ORM objects), returns parsed alert data dict.
        """
        user_content = self._build_slip_content_from_dict(item)

        client = get_anthropic_client()
        response = await client.messages.create(
            model=CLAUDE_MODEL,
            max_tokens=CLAUDE_MAX_TOKENS,
            system=ALERT_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": user_content}],
        )

        raw_text = response.content[0].text
        cleaned = strip_fences(raw_text)

        try:
            alert_data: dict[str, Any] = json.loads(cleaned)
        except json.JSONDecodeError:
            logger.warning(
                "_call_claude_for_slip: Claude returned invalid JSON for scope %s — "
                "using default alert. Raw: %s...",
                item["scope_id"],
                cleaned[:200],
            )
            days_behind = item["days_behind"]
            alert_data = {
                "impact_text": f"{item['trade_name']} is {days_behind} days behind schedule.",
                "remediation_text": "Review overdue tasks and update the schedule.",
                "severity": "warning" if days_behind <= 7 else "critical",
                "rescheduling_suggestions": [],
            }

        severity = alert_data.get("severity", "warning")
        if severity not in ("info", "warning", "critical"):
            severity = "warning"

        rescheduling = alert_data.get("rescheduling_suggestions", [])
        rescheduling_payload = {"suggestions": rescheduling} if rescheduling else None

        return {
            "severity": severity,
            "impact_text": alert_data.get("impact_text", ""),
            "remediation_text": alert_data.get("remediation_text"),
            "rescheduling_payload": rescheduling_payload,
        }

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

    def _build_slip_content_from_dict(self, item: dict[str, Any]) -> str:
        """Build the user message content for Claude from plain dict data."""
        lines = [
            f"Project: {item['project_name']}",
            f"Trade scope: {item['trade_name']}",
            f"Days behind schedule: {item['days_behind']}",
            "",
            "Overdue tasks:",
        ]

        for task in item["overdue_tasks"]:
            due_str = f"(due {task['due_date']})" if task.get("due_date") else ""
            lines.append(f"- task_id={task['id']} | {task['title']} {due_str} [{task['status']}]")

        affected = item.get("affected_scope_ids", [])
        if affected:
            lines.extend(
                [
                    "",
                    f"Downstream scopes potentially affected: {len(affected)} scope(s)",
                ]
            )

        desc = item.get("project_description")
        if desc:
            lines.extend(["", f"Project context: {desc}"])

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

        BUG-3: Batch-fetches all tasks in a single query instead of per-suggestion db.get().
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

            # BUG-3: Collect all valid task IDs first, then batch-fetch
            task_id_map: dict[uuid.UUID, str | None] = {}  # task_uuid -> suggestion index
            valid_suggestions: list[tuple[uuid.UUID, dict]] = []

            for suggestion in suggestions:
                task_id_str = suggestion.get("task_id")
                if not task_id_str:
                    continue
                try:
                    task_uuid = uuid.UUID(task_id_str)
                    valid_suggestions.append((task_uuid, suggestion))
                    task_id_map[task_uuid] = None
                except ValueError:
                    logger.warning(
                        "accept_rescheduling: invalid task_id '%s' in alert %s",
                        task_id_str,
                        alert_id,
                    )

            if valid_suggestions:
                # Single query to fetch all tasks
                task_ids = list(task_id_map.keys())
                task_stmt = select(Task).where(Task.id.in_(task_ids))
                task_result = await self.db.execute(task_stmt)
                tasks_by_id: dict[uuid.UUID, Task] = {
                    t.id: t for t in task_result.scalars().all()
                }

                for task_uuid, suggestion in valid_suggestions:
                    task = tasks_by_id.get(task_uuid)
                    if task is None:
                        logger.warning(
                            "accept_rescheduling: task %s not found for alert %s",
                            task_uuid,
                            alert_id,
                        )
                        continue

                    new_start_str = suggestion.get("new_start_date")
                    new_due_str = suggestion.get("new_due_date")

                    if new_start_str:
                        try:
                            task.start_date = date.fromisoformat(new_start_str)
                        except ValueError:
                            logger.warning(
                                "accept_rescheduling: invalid new_start_date '%s'",
                                new_start_str,
                            )

                    if new_due_str:
                        try:
                            task.due_date = date.fromisoformat(new_due_str)
                        except ValueError:
                            logger.warning(
                                "accept_rescheduling: invalid new_due_date '%s'",
                                new_due_str,
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
