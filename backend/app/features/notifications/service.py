"""NotificationService — FCM push notification dispatch and device token management.

Inherits from BaseService[DeviceToken] (user-scoped, NOT tenant-scoped per CLAUDE.md
OOP rules). Device tokens belong to individual users across all tenants.

FCM dispatch design:
- Firebase app is initialized lazily (guard: not firebase_admin._apps) to avoid
  duplicate app errors in multi-worker environments.
- Credentials come from GOOGLE_APPLICATION_CREDENTIALS env var (standard Firebase
  service account convention). If unset, FCM is skipped with a warning — enables
  dev/test environments without Firebase credentials.
- Fire-and-forget failure handling: FCM errors are logged but do NOT block or
  raise exceptions. Job operations must never be affected by notification failures.
- UnregisteredError: token is cleaned up automatically to prevent stale token
  accumulation.
"""

from __future__ import annotations

import logging
import os
import uuid
from typing import Any

from app.core.base_service import BaseService
from app.features.notifications.models import DeviceToken
from app.features.notifications.repository import NotificationRepository

logger = logging.getLogger(__name__)


def _get_firebase_app() -> Any | None:
    """Return initialized Firebase app, or None if credentials are unavailable.

    Guards against:
    1. Missing GOOGLE_APPLICATION_CREDENTIALS env var (dev/test environments).
    2. Double-initialization (multiple workers sharing the same process).

    Returns None to signal graceful degradation — callers skip FCM silently.
    """
    cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if not cred_path:
        logger.warning(
            "GOOGLE_APPLICATION_CREDENTIALS not set — FCM notifications disabled. "
            "Set this env var to a Firebase service account JSON path to enable push."
        )
        return None

    try:
        import firebase_admin
        from firebase_admin import credentials

        if not firebase_admin._apps:  # noqa: SLF001  # firebase_admin public API check
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)

        return firebase_admin.get_app()
    except Exception:  # noqa: BLE001
        logger.exception("Failed to initialize Firebase app")
        return None


class NotificationService(BaseService[DeviceToken]):
    """Service for FCM push notification dispatch and device token management.

    Inherits BaseService[DeviceToken]. Constructor takes AsyncSession and
    wires up NotificationRepository via repository_class.
    """

    repository_class = NotificationRepository

    # Typed reference for IDE completion
    repository: NotificationRepository

    async def upsert_token(
        self,
        user_id: uuid.UUID,
        token: str,
        platform: str,
    ) -> None:
        """Register or refresh a device token for the given user.

        If the (user_id, token) pair already exists, updates last_used_at.
        Delegates to NotificationRepository.upsert_token().
        """
        await self.repository.upsert_token(user_id, token, platform)

    async def send_job_notification(
        self,
        user_id: uuid.UUID,
        job_description: str,
        event: str,
        job_id: uuid.UUID,
    ) -> None:
        """Dispatch a FCM push notification to all registered devices for a user.

        Looks up all tokens for user_id, then sends one FCM message per token.
        All failures are fire-and-forget — logged but never re-raised.
        UnregisteredError triggers automatic token cleanup.

        Args:
            user_id:          Target user — all their registered devices receive the push.
            job_description:  Job description for notification body text.
            event:            One of 'scheduled', 'started', 'completed', 'delayed'.
            job_id:           Job UUID for deep-link in notification data payload.
        """
        firebase_app = _get_firebase_app()
        if firebase_app is None:
            # Graceful degradation — FCM not configured in this environment
            logger.debug(
                "FCM not configured — skipping notification for user %s event %s",
                user_id,
                event,
            )
            return

        tokens = await self.repository.get_tokens_for_user(user_id)
        if not tokens:
            logger.debug("No device tokens for user %s — skipping notification", user_id)
            return

        title, body = _build_notification_content(job_description, event)

        try:
            from firebase_admin import messaging
        except ImportError:
            logger.exception("firebase_admin.messaging not available — FCM skipped")
            return

        for device_token in tokens:
            await self._send_to_token(
                token_record=device_token,
                title=title,
                body=body,
                job_id=job_id,
                messaging=messaging,
            )

    async def queue_task_completion_digest(
        self,
        task_id: uuid.UUID,
        task_title: str,
        trade_scope_name: str,
        company_id: uuid.UUID,
        completed_by_name: str,
    ) -> None:
        """Fire-and-forget: notify all GC/admin users in the company when a task is completed.

        Design notes (per D-16):
        - True batch/digest grouping ("Plumbing: 3 tasks today") is a future enhancement.
          For now, each task completion sends one FCM notification per GC device.
        - data payload includes trade_scope_name so mobile clients can group client-side.
        - All failures are fire-and-forget — errors logged but never raised.
        - Gracefully skips if GOOGLE_APPLICATION_CREDENTIALS not set (dev/test environments).

        Args:
            task_id:            UUID of the completed task (included in FCM data payload).
            task_title:         Title of the completed task for notification body text.
            trade_scope_name:   Trade name (e.g. "Electrical", "Plumbing") for grouping.
            company_id:         Tenant company UUID — used to scope the user lookup.
            completed_by_name:  Display name of the user who completed the task.
        """
        firebase_app = _get_firebase_app()
        if firebase_app is None:
            logger.debug(
                "FCM not configured — skipping task completion digest for task %s", task_id
            )
            return

        try:
            from firebase_admin import messaging
            from sqlalchemy import select

            from app.features.users.models import User, UserRole

            # Query all GC/admin users for this company
            stmt = (
                select(User)
                .join(UserRole, UserRole.user_id == User.id)
                .where(UserRole.role.in_(["gc", "admin"]))
                .where(User.company_id == company_id)
                .where(User.deleted_at.is_(None))
            )
            result = await self.db.execute(stmt)
            gc_users = result.scalars().all()

            title = "Task Completed"
            body = f"{completed_by_name} completed '{task_title}' in {trade_scope_name}"
            data_payload = {
                "type": "task_completion_digest",
                "task_id": str(task_id),
                "trade_scope_name": trade_scope_name,
            }

            for gc_user in gc_users:
                tokens = await self.repository.get_tokens_for_user(gc_user.id)
                for device_token in tokens:
                    try:
                        message = messaging.Message(
                            notification=messaging.Notification(title=title, body=body),
                            data=data_payload,
                            token=device_token.token,
                        )
                        messaging.send(message)
                        logger.debug(
                            "Task completion digest FCM sent to GC user %s token %s...",
                            gc_user.id,
                            device_token.token[:12],
                        )
                    except messaging.UnregisteredError:
                        logger.info(
                            "FCM token unregistered — removing token %s... for user %s",
                            device_token.token[:12],
                            gc_user.id,
                        )
                        await self.repository.delete_token(device_token.token)
                    except Exception:  # noqa: BLE001
                        logger.exception(
                            "FCM task digest send failed for token %s... user %s",
                            device_token.token[:12],
                            gc_user.id,
                        )
        except Exception:  # noqa: BLE001
            # Outer catch: never let notification logic break the task status update
            logger.exception(
                "queue_task_completion_digest failed for task %s — continuing without notification",
                task_id,
            )

    async def _send_to_token(
        self,
        *,
        token_record: DeviceToken,
        title: str,
        body: str,
        job_id: uuid.UUID,
        messaging: Any,
    ) -> None:
        """Send FCM message to a single device token.

        On success: no action (fire-and-forget).
        On UnregisteredError: delete the stale token from the registry.
        On any other error: log and continue — never raise.
        """
        try:
            message = messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                data={"job_id": str(job_id), "event": "job_update"},
                token=token_record.token,
            )
            messaging.send(message)
            logger.debug(
                "FCM sent to token %s... for user %s",
                token_record.token[:12],
                token_record.user_id,
            )
        except messaging.UnregisteredError:
            # Token no longer valid — clean up to avoid stale token accumulation
            logger.info(
                "FCM token unregistered — removing token %s... for user %s",
                token_record.token[:12],
                token_record.user_id,
            )
            await self.repository.delete_token(token_record.token)
        except Exception:  # noqa: BLE001
            # Any other FCM error — log and continue (fire-and-forget)
            logger.exception(
                "FCM send failed for token %s... user %s event",
                token_record.token[:12],
                token_record.user_id,
            )


# ---------------------------------------------------------------------------
# Notification content helpers
# ---------------------------------------------------------------------------


def _build_notification_content(job_description: str, event: str) -> tuple[str, str]:
    """Build FCM notification title and body for a job lifecycle event.

    Args:
        job_description: The job's description field for display in notification.
        event:           One of 'scheduled', 'started', 'completed', 'delayed'.

    Returns:
        (title, body) tuple for FCM Notification object.
    """
    if event == "scheduled":
        title = "Job Scheduled"
        body = f"Your job '{job_description}' has been scheduled."
    elif event == "started":
        title = "Work Started"
        body = f"Work has started on your job '{job_description}'."
    elif event == "completed":
        title = "Job Completed"
        body = f"Your job '{job_description}' has been completed."
    elif event == "delayed":
        title = "Job Delayed"
        body = f"Your job '{job_description}' has been delayed. Check the app for updated timing."
    else:
        title = "Job Update"
        body = f"There is an update on your job '{job_description}'."

    return title, body
