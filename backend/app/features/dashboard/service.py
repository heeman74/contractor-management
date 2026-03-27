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
- Bounded concurrency on AI calls via gather_with_concurrency
- Each scope's alert generation wrapped in try/except — errors logged, continue
- No db.commit() — caller (cron job or get_db) handles transaction lifecycle
- DB session is released before Claude API calls to avoid holding connections
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, timezone
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import selectinload

from app.core.ai_utils import (
    ACTIVE_PROJECT_STATUSES,
    DASHBOARD_PROJECT_STATUSES,
    DONE_STATUSES,
    call_claude_json,
    gather_with_concurrency,
)
from app.core.base_service import TenantScopedService
from app.core.logging_config import get_logger
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

logger = get_logger(__name__)

# Schedule slip detection thresholds
MIN_SLIP_DAYS_THRESHOLD = 1
ALERT_DEDUP_HOURS = 24


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
        to avoid N+1 per-project count queries.

        Returns list of ProjectStatusCard — each card is fully self-contained.
        """
        today = datetime.now(timezone.utc).date()

        stmt = (
            select(Project)
            .where(
                Project.company_id == company_id,
                Project.status.in_(DASHBOARD_PROJECT_STATUSES),
                Project.deleted_at.is_(None),
            )
            .options(
                selectinload(Project.trade_scopes).selectinload(TradeScope.tasks),
            )
        )
        result = await self.db.execute(stmt)
        projects = list(result.scalars().all())

        # Batch-fetch alert counts for all projects in one GROUP BY query
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

                badge, scope_total, scope_completed = self._build_trade_badge(scope, today)
                trade_statuses.append(badge)
                total_tasks += scope_total
                completed_tasks += scope_completed

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

    @staticmethod
    def _build_trade_badge(
        scope: TradeScope, today: date
    ) -> tuple[TradeStatusBadge, int, int]:
        """Build a TradeStatusBadge for a single scope.

        Returns (badge, total_task_count, completed_task_count) so the caller
        can accumulate project-level totals.
        """
        scope_tasks = [t for t in scope.tasks if t.deleted_at is None]
        scope_total = len(scope_tasks)
        scope_completed = sum(1 for t in scope_tasks if t.status == "complete")

        scope_completion = (
            round(scope_completed / scope_total * 100, 1) if scope_total > 0 else 0.0
        )
        scope_status = _compute_trade_status(scope_tasks, today)

        badge = TradeStatusBadge(
            trade_scope_id=scope.id,
            trade_name=scope.trade_name,
            status=scope_status,
            completion_pct=scope_completion,
            task_count=scope_total,
            completed_count=scope_completed,
        )
        return badge, scope_total, scope_completed

    # -------------------------------------------------------------------------
    # Trade task drill-down
    # -------------------------------------------------------------------------

    async def get_trade_tasks(
        self,
        trade_scope_id: uuid.UUID,
        project_id: uuid.UUID | None = None,
    ) -> list[TradeTaskDetail]:
        """Return all tasks for a trade scope with dependency and assignee info.

        Used for the GC drill-down view when a trade badge is tapped.
        If project_id is provided, validates that the scope belongs to the project.
        """
        stmt = (
            select(TradeScope)
            .where(
                TradeScope.id == trade_scope_id,
                TradeScope.deleted_at.is_(None),
            )
            .options(selectinload(TradeScope.tasks))
        )
        if project_id is not None:
            stmt = stmt.where(TradeScope.project_id == project_id)

        result = await self.db.execute(stmt)
        scope = result.scalars().first()

        if scope is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Trade scope not found for this project",
            )

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

        # Filter dependencies to only those involving tasks in this project
        dep_links: list[DependencyLink] = []

        if task_ids:
            dep_stmt = select(TaskDependency).where(
                TaskDependency.deleted_at.is_(None),
                (
                    TaskDependency.predecessor_task_id.in_(task_ids)
                    | TaskDependency.successor_task_id.in_(task_ids)
                ),
            )
            dep_result = await self.db.execute(dep_stmt)
            all_deps = list(dep_result.scalars().all())
            dep_links = self._build_dependency_links(all_deps, task_ids, task_scope_map)

        return TradeTimelineResponse(
            project_id=project.id,
            project_name=project.name,
            scopes=scope_entries,
            dependency_links=dep_links,
        )

    @staticmethod
    def _build_dependency_links(
        dependencies: list[TaskDependency],
        task_ids: list[uuid.UUID],
        task_scope_map: dict[uuid.UUID, uuid.UUID],
    ) -> list[DependencyLink]:
        """Build deduplicated cross-scope dependency links from raw TaskDependency rows.

        Only includes links where predecessor and successor belong to different scopes.
        """
        dep_links: list[DependencyLink] = []
        seen_links: set[tuple[uuid.UUID, uuid.UUID]] = set()

        for dep in dependencies:
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

        return dep_links

    # -------------------------------------------------------------------------
    # Schedule slip detection
    # -------------------------------------------------------------------------

    async def detect_schedule_slips(
        self,
        company_id: uuid.UUID,
        target_date: date,
    ) -> int:
        """Detect schedule slips across all active projects and generate AI alerts.

        Orchestrates: find slip candidates, call Claude for each, persist alerts.

        Returns the number of alerts generated.
        """
        slip_items, existing_alert_keys = await self._find_slip_candidates(company_id, target_date)

        # Filter out items that already have recent alerts
        filtered_items = [
            item
            for item in slip_items
            if (item["project_id"], item["scope_id"], "schedule_slip") not in existing_alert_keys
        ]

        ai_results = await gather_with_concurrency(filtered_items, self._call_claude_for_slip)

        generated_count = await self._persist_alerts(filtered_items, ai_results)

        logger.info(
            "detect_schedule_slips: generated %d alerts for company %s date %s",
            generated_count,
            company_id,
            target_date,
        )
        return generated_count

    async def _find_slip_candidates(
        self,
        company_id: uuid.UUID,
        target_date: date,
    ) -> tuple[list[dict[str, Any]], set[tuple[uuid.UUID, uuid.UUID | None, str]]]:
        """Query active projects and extract trade scopes with overdue tasks.

        Also pre-fetches recent alerts for deduplication via the repository.

        Returns (slip_items, existing_alert_keys).
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

        existing_alert_keys = await self.repository.get_recent_alert_keys(
            company_id, hours=ALERT_DEDUP_HOURS
        )

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
                if max_days <= MIN_SLIP_DAYS_THRESHOLD:
                    continue

                scope_days_behind[scope.id] = max_days
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

        return slip_items, existing_alert_keys

    async def _persist_alerts(
        self,
        items: list[dict[str, Any]],
        results: list[dict[str, Any] | None],
    ) -> int:
        """Write AI-generated alerts to the database. Returns the count of alerts created."""
        generated_count = 0

        for item, ai_result in zip(items, results, strict=False):
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

        return generated_count

    async def _call_claude_for_slip(self, item: dict[str, Any]) -> dict[str, Any]:
        """Call Claude API for a single schedule slip analysis.

        Takes plain dict data (no ORM objects), returns parsed alert data dict.
        """
        user_content = self._build_slip_content_from_dict(item)
        days_behind = item["days_behind"]

        fallback = {
            "impact_text": f"{item['trade_name']} is {days_behind} days behind schedule.",
            "remediation_text": "Review overdue tasks and update the schedule.",
            "severity": "warning" if days_behind <= 7 else "critical",
            "rescheduling_suggestions": [],
        }

        alert_data = await call_claude_json(
            system_prompt=ALERT_SYSTEM_PROMPT,
            user_content=user_content,
            fallback=fallback,
            scope_id=item["scope_id"],
        )

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

        Simple heuristic: scopes with higher sort_order likely depend on lower
        sort_order scopes, so they may be affected by the slip.
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

        Batch-fetches all tasks in a single query instead of per-suggestion db.get().
        """
        alert = await self.repository.get_by_id(alert_id)
        if alert is None:
            return None

        payload = alert.rescheduling_payload
        if payload and "suggestions" in payload:
            suggestions = payload["suggestions"]
            task_ids, valid_suggestions = self._parse_suggestion_task_ids(
                suggestions, alert_id
            )

            if valid_suggestions:
                # Single query to fetch all tasks, filtered to the alert's project
                task_stmt = select(Task).where(
                    Task.id.in_(task_ids),
                    Task.trade_scope_id.in_(
                        select(TradeScope.id).where(TradeScope.project_id == alert.project_id)
                    ),
                )
                task_result = await self.db.execute(task_stmt)
                tasks_by_id: dict[uuid.UUID, Task] = {t.id: t for t in task_result.scalars().all()}

                self._apply_date_changes(tasks_by_id, valid_suggestions, alert_id)
                await self.db.flush()

        return await self.repository.accept_rescheduling(alert_id)

    @staticmethod
    def _parse_suggestion_task_ids(
        suggestions: list[dict[str, Any]],
        alert_id: uuid.UUID,
    ) -> tuple[set[uuid.UUID], list[tuple[uuid.UUID, dict[str, Any]]]]:
        """Parse task IDs from rescheduling suggestions.

        Returns (task_ids, valid_suggestions) where valid_suggestions is a list
        of (task_uuid, suggestion_dict) pairs with successfully parsed UUIDs.
        """
        task_ids: set[uuid.UUID] = set()
        valid_suggestions: list[tuple[uuid.UUID, dict[str, Any]]] = []

        for suggestion in suggestions:
            task_id_str = suggestion.get("task_id")
            if not task_id_str:
                continue
            try:
                task_uuid = uuid.UUID(task_id_str)
                valid_suggestions.append((task_uuid, suggestion))
                task_ids.add(task_uuid)
            except ValueError:
                logger.warning(
                    "accept_rescheduling: invalid task_id '%s' in alert %s",
                    task_id_str,
                    alert_id,
                )

        return task_ids, valid_suggestions

    @staticmethod
    def _apply_date_changes(
        tasks_by_id: dict[uuid.UUID, Task],
        valid_suggestions: list[tuple[uuid.UUID, dict[str, Any]]],
        alert_id: uuid.UUID,
    ) -> None:
        """Apply start_date and due_date changes from suggestions to task objects.

        Mutates the Task objects in-place. Logs warnings for missing tasks
        or invalid date strings.
        """
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

    async def get_alerts(
        self,
        project_id: uuid.UUID | None = None,
    ) -> list[DashboardAlert]:
        """Return alerts for the current tenant, optionally filtered by project."""
        if project_id is not None:
            return await self.repository.get_for_project(project_id)
        return await self.repository.get_unread_for_company()
