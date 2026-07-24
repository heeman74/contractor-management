"""Shared Job-domain service helpers.

`JobEventsMixin` provides the status-history and client-notification behavior that
several services (invoices, quotes, and the job service itself) need when acting on
a Job. It lives in the jobs feature because it operates on the Job entity.

The mixin expects the host class to expose ``self.db: AsyncSession`` — satisfied by
any subclass of ``BaseService``.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging_config import get_logger
from app.features.jobs.models import Job
from app.features.notifications.service import NotificationService

logger = get_logger(__name__)


class JobEventsMixin:
    """Status-history append + fire-and-forget client notification for Job-based services."""

    db: AsyncSession

    async def _append_job_status_event(
        self,
        job_id: uuid.UUID,
        event_type: str,
        user_id: uuid.UUID | None = None,
    ) -> None:
        """Append a {type, user_id, timestamp} event to a job's status_history.

        Replaces the JSONB list entirely (never mutates in-place — Pitfall 3).
        No-op if the job no longer exists.
        """
        job = await self.db.get(Job, job_id)
        if job is None:
            return
        event = {
            "type": event_type,
            "user_id": str(user_id) if user_id else None,
            "timestamp": datetime.now(UTC).isoformat(),
        }
        job.status_history = [*(job.status_history or []), event]
        await self.db.flush()

    async def _notify_client(self, job: Job, event: str) -> None:
        """Send a fire-and-forget client notification for a loaded job; never raises."""
        if job.client_id is None:
            return
        try:
            notif_svc = NotificationService(self.db)
            await notif_svc.send_job_notification(
                user_id=job.client_id,
                job_description=job.description,
                event=event,
                job_id=job.id,
            )
        except Exception:
            logger.exception("Failed to send %s notification for job %s", event, job.id)

    async def _notify_job_client(self, job_id: uuid.UUID | None, event: str) -> None:
        """Load a job by id and notify its client; no-op when the job is missing."""
        if job_id is None:
            return
        job = await self.db.get(Job, job_id)
        if job is None:
            return
        await self._notify_client(job, event)
