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

import asyncio
import logging
import os
import uuid
from concurrent.futures import ThreadPoolExecutor
from typing import Any

from app.core.base_service import BaseService
from app.features.notifications.models import DeviceToken
from app.features.notifications.repository import NotificationRepository

# Dedicated thread pool for synchronous Firebase Admin SDK calls
# to avoid blocking the async event loop
_fcm_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="fcm")

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

        if not firebase_admin._apps:  # firebase_admin public API check
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)

        return firebase_admin.get_app()
    except Exception:
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
        messaging = self._resolve_messaging(f"notification for user {user_id} event {event}")
        if messaging is None:
            return

        tokens = await self.repository.get_tokens_for_user(user_id)
        if not tokens:
            logger.debug("No device tokens for user %s — skipping notification", user_id)
            return

        title, body = _build_notification_content(job_description, event)
        await self._dispatch_to_tokens(
            tokens,
            title=title,
            body=body,
            data={"job_id": str(job_id), "event": "job_update"},
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
        messaging = self._resolve_messaging(f"task completion digest for task {task_id}")
        if messaging is None:
            return

        try:
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

            all_tokens: list[DeviceToken] = []
            for gc_user in gc_users:
                all_tokens.extend(await self.repository.get_tokens_for_user(gc_user.id))

            await self._dispatch_to_tokens(
                all_tokens,
                title="Task Completed",
                body=f"{completed_by_name} completed '{task_title}' in {trade_scope_name}",
                data={
                    "type": "task_completion_digest",
                    "task_id": str(task_id),
                    "trade_scope_name": trade_scope_name,
                },
                messaging=messaging,
            )
        except Exception:
            # Outer catch: never let notification logic break the task status update
            logger.exception(
                "queue_task_completion_digest failed for task %s — continuing without notification",
                task_id,
            )

    async def send_chat_notification(
        self,
        thread_id: uuid.UUID,
        sender_name: str,
        trade_scope_name: str | None,
        message_preview: str,
        recipient_user_ids: list[uuid.UUID],
        mention_all: bool,
        mentioned_user_ids: list[uuid.UUID],
        muted_user_ids: list[uuid.UUID],
    ) -> None:
        """Dispatch FCM push for a new chat message to offline recipients.

        @mention override: even muted users receive FCM if they are mentioned
        (mention_all overrides mute for everyone; mention_user_ids overrides for
        specific users).

        Per D-14 FCM body format: "{sender_name} ({trade_scope_name}): {preview}"
        If trade_scope_name is None, uses "{sender_name}: {preview}".

        All failures are fire-and-forget — errors are logged but never raised.

        Args:
            thread_id:            UUID of the chat thread (for deep-link data).
            sender_name:          Display name of the message author.
            trade_scope_name:     Trade name for scope threads (e.g. "Plumbing"), or None.
            message_preview:      First 100 chars of message content for notification body.
            recipient_user_ids:   Users to notify (offline, non-sender members).
            mention_all:          True if sender used @everyone — overrides mute for all.
            mentioned_user_ids:   Specific users mentioned — overrides mute for them.
            muted_user_ids:       Users who have muted this thread.
        """
        if not recipient_user_ids:
            return

        messaging = self._resolve_messaging(f"chat notification for thread {thread_id}")
        if messaging is None:
            return

        # Build notification body per D-14
        if trade_scope_name:
            body = f"{sender_name} ({trade_scope_name}): {message_preview[:100]}"
        else:
            body = f"{sender_name}: {message_preview[:100]}"

        data_payload = {"type": "chat_message", "thread_id": str(thread_id)}
        muted_set = {str(uid) for uid in muted_user_ids}
        mentioned_set = {str(uid) for uid in mentioned_user_ids}

        for user_id in recipient_user_ids:
            uid_str = str(user_id)
            # Skip muted users UNLESS they are mentioned or mention_all is set
            if uid_str in muted_set and not mention_all and uid_str not in mentioned_set:
                continue

            tokens = await self.repository.get_tokens_for_user(user_id)
            await self._dispatch_to_tokens(
                tokens,
                title="New Message",
                body=body,
                data=data_payload,
                messaging=messaging,
            )

    async def send_task_rejection_notification(
        self,
        task_id: uuid.UUID,
        task_title: str,
        rejection_reason: str,
        contractor_id: uuid.UUID,
    ) -> None:
        """Fire-and-forget FCM to contractor when their task is rejected by the GC.

        Follows the same fire-and-forget pattern as queue_task_completion_digest:
        - Skips gracefully if GOOGLE_APPLICATION_CREDENTIALS is not set.
        - UnregisteredError: cleans up stale token.
        - Any other error: logged but never raised (never blocks the inspect response).

        Args:
            task_id:          UUID of the rejected task (for deep-link data payload).
            task_title:       Title of the task for the FCM notification body.
            rejection_reason: Short rejection reason for notification body.
            contractor_id:    UUID of the contractor assigned to the task.
        """
        messaging = self._resolve_messaging(f"rejection notification for task {task_id}")
        if messaging is None:
            return
        try:
            tokens = await self.repository.get_tokens_for_user(contractor_id)
            if not tokens:
                logger.debug(
                    "No device tokens for contractor %s — skipping rejection notification",
                    contractor_id,
                )
                return

            await self._dispatch_to_tokens(
                tokens,
                title="Task Rejected",
                body=f"Task '{task_title}' was rejected: {rejection_reason}",
                data={
                    "type": "task_rejection",
                    "task_id": str(task_id),
                    "rejection_reason": rejection_reason,
                },
                messaging=messaging,
            )
        except Exception:
            logger.exception(
                "send_task_rejection_notification failed for task %s — continuing",
                task_id,
            )

    async def send_contract_ready_notification(
        self,
        client_user_id: uuid.UUID,
        contract_id: uuid.UUID,
        magic_link: str,
    ) -> None:
        """Notify the client that a contract is ready to sign (FCM + magic-link).

        Email delivery of the magic link is a TODO — the app has no email provider yet,
        so the link is logged here and pushed via FCM. Never raises.
        """
        # TODO(29-02): send the magic link by email once an email provider is wired.
        logger.info("Contract %s ready to sign — magic link: %s", contract_id, magic_link)
        messaging = self._resolve_messaging(f"contract-ready notification {contract_id}")
        if messaging is None:
            return
        try:
            tokens = await self.repository.get_tokens_for_user(client_user_id)
            if not tokens:
                return
            await self._dispatch_to_tokens(
                tokens,
                title="Contract ready to sign",
                body="Your contractor sent a contract for your signature.",
                data={
                    "type": "contract_ready",
                    "contract_id": str(contract_id),
                    "sign_url": magic_link,
                },
                messaging=messaging,
            )
        except Exception:
            logger.exception("send_contract_ready_notification failed for %s", contract_id)

    async def send_contract_signed_notification(self, contract_id: uuid.UUID) -> None:
        """Best-effort notice that a contract was signed (admin sees it on the dashboard)."""
        # TODO(29-02): FCM/email to the admin once a target admin/email is available.
        logger.info("Contract %s has been signed by the client.", contract_id)

    async def send_checklist_notification(
        self,
        contractor_id: uuid.UUID,
        summary_text: str,
        checklist_id: uuid.UUID,
    ) -> None:
        """Fire-and-forget FCM to contractor with their AI-generated daily checklist.

        Follows the exact fire-and-forget pattern of send_task_rejection_notification:
        - Skips gracefully if GOOGLE_APPLICATION_CREDENTIALS is not set.
        - UnregisteredError: cleans up stale token.
        - Any other error: logged but never raised (never blocks checklist generation).

        Args:
            contractor_id:  UUID of the contractor assigned to this checklist.
            summary_text:   Short text for FCM body ("You have 5 tasks today: ...").
            checklist_id:   UUID of the DailyChecklist record (for deep-link data payload).
        """
        messaging = self._resolve_messaging(
            f"checklist notification for contractor {contractor_id}"
        )
        if messaging is None:
            return
        try:
            tokens = await self.repository.get_tokens_for_user(contractor_id)
            if not tokens:
                logger.debug(
                    "No device tokens for contractor %s — skipping checklist notification",
                    contractor_id,
                )
                return

            await self._dispatch_to_tokens(
                tokens,
                title="Your Daily Checklist is Ready",
                body=summary_text,
                data={"type": "daily_checklist", "checklist_id": str(checklist_id)},
                messaging=messaging,
            )
        except Exception:
            logger.exception(
                "send_checklist_notification failed for contractor %s — continuing",
                contractor_id,
            )

    def _resolve_messaging(self, skip_context: str) -> Any | None:
        """Return the firebase messaging module, or None when FCM is unavailable.

        Combines the Firebase-app credential check and the messaging import that
        every send_* method needs. On unavailability it logs and returns None so
        callers degrade gracefully.
        """
        if _get_firebase_app() is None:
            logger.debug("FCM not configured — skipping %s", skip_context)
            return None
        try:
            from firebase_admin import messaging

            return messaging
        except ImportError:
            logger.exception("firebase_admin.messaging not available — FCM skipped")
            return None

    async def _dispatch_to_tokens(
        self,
        tokens: list[DeviceToken],
        *,
        title: str,
        body: str,
        data: dict[str, str],
        messaging: Any,
    ) -> None:
        """Send the same notification to each device token (fire-and-forget per token)."""
        for token_record in tokens:
            await self._send_to_token(
                token_record, title=title, body=body, data=data, messaging=messaging
            )

    async def _send_to_token(
        self,
        token_record: DeviceToken,
        *,
        title: str,
        body: str,
        data: dict[str, str],
        messaging: Any,
    ) -> None:
        """Send an FCM message to a single device token.

        On success: no action (fire-and-forget).
        On UnregisteredError: delete the stale token from the registry.
        On any other error: log and continue — never raise.
        """
        try:
            message = messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                data=data,
                token=token_record.token,
            )
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(_fcm_executor, messaging.send, message)
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
        except Exception:
            # Any other FCM error — log and continue (fire-and-forget)
            logger.exception(
                "FCM send failed for token %s... user %s",
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
