"""ChatService — business logic for the real-time chat feature.

Inherits TenantScopedService[ChatThread]. Provides:
  - Thread creation (scope threads auto-created when contractor assigned)
  - Message send with client-UUID deduplication (ON CONFLICT DO NOTHING)
  - Read receipt upsert with seq ordering (only advances, never regresses)
  - Thread listing for a specific user (membership-filtered)
  - Mute toggle for a membership

Per CLAUDE.md rules:
  - Do NOT call db.commit() — get_db dependency handles commit/rollback
  - Use db.flush() to get server-generated values (seq) before returning
  - All relationships use lazy="raise" — always eager-load in repository queries
  - Standalone functions are NOT allowed — use class methods
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_service import TenantScopedService
from app.features.chat.models import (
    ChatMembership,
    ChatMessage,
    ChatReadReceipt,
    ChatThread,
)
from app.features.chat.repository import ChatMessageRepository, ChatThreadRepository


class ChatService(TenantScopedService[ChatThread]):
    """Service for chat threads, messages, memberships, and read receipts."""

    repository_class = ChatThreadRepository

    def __init__(self, db: AsyncSession) -> None:
        super().__init__(db)
        self.thread_repo: ChatThreadRepository = self.repository  # type: ignore[assignment]
        self.message_repo = ChatMessageRepository(db)

    # ------------------------------------------------------------------
    # Thread creation
    # ------------------------------------------------------------------

    async def create_scope_thread(
        self,
        project_id: uuid.UUID,
        trade_scope_id: uuid.UUID,
        trade_name: str,
        contractor_id: uuid.UUID,
        gc_user_id: uuid.UUID,
        company_id: uuid.UUID,
    ) -> ChatThread:
        """Create a scope-level thread for a trade + GC pair (idempotent).

        If a thread already exists for this (project, trade_scope), return it.
        Otherwise create the thread and add two memberships: GC + contractor.

        Args:
            project_id: The project this trade scope belongs to.
            trade_scope_id: The specific trade scope (e.g. Plumbing scope).
            trade_name: Display name for the thread (e.g. "Plumbing").
            contractor_id: The trade contractor user_id to add as member.
            gc_user_id: The GC (company admin) user_id to add as member.
            company_id: The owning company (used to set company_id on new rows).
        """
        # Idempotency: return existing thread if already created
        existing = await self.thread_repo.find_scope_thread(project_id, trade_scope_id)
        if existing is not None:
            return existing

        thread = ChatThread(
            company_id=company_id,
            project_id=project_id,
            thread_type="scope",
            trade_scope_id=trade_scope_id,
            name=trade_name,
        )
        self.db.add(thread)
        await self.db.flush()
        await self.db.refresh(thread)

        # Add GC and contractor as members (deduplicate in case same user)
        seen: set[uuid.UUID] = set()
        for member_id in [gc_user_id, contractor_id]:
            if member_id in seen:
                continue
            seen.add(member_id)
            membership = ChatMembership(
                company_id=company_id,
                thread_id=thread.id,
                user_id=member_id,
            )
            self.db.add(membership)

        await self.db.flush()
        return thread

    async def create_project_wide_thread(
        self,
        project_id: uuid.UUID,
        project_name: str,
        member_user_ids: list[uuid.UUID],
        company_id: uuid.UUID,
    ) -> ChatThread:
        """Create a project-wide thread visible to all project members (idempotent).

        If a project_wide thread already exists for this project, return it.
        Otherwise create the thread and add all provided user IDs as members.

        Args:
            project_id: The project this thread belongs to.
            project_name: Display name (e.g. "Project-Wide" or project.name).
            member_user_ids: List of user UUIDs to add as members.
            company_id: The owning company.
        """
        existing = await self.thread_repo.find_project_wide_thread(project_id)
        if existing is not None:
            return existing

        thread = ChatThread(
            company_id=company_id,
            project_id=project_id,
            thread_type="project_wide",
            trade_scope_id=None,
            name=project_name,
        )
        self.db.add(thread)
        await self.db.flush()
        await self.db.refresh(thread)

        for user_id in member_user_ids:
            membership = ChatMembership(
                company_id=company_id,
                thread_id=thread.id,
                user_id=user_id,
            )
            self.db.add(membership)

        await self.db.flush()
        return thread

    # ------------------------------------------------------------------
    # Membership management
    # ------------------------------------------------------------------

    async def ensure_membership(
        self,
        thread_id: uuid.UUID,
        user_id: uuid.UUID,
        company_id: uuid.UUID,
    ) -> ChatMembership:
        """Add user to thread if not already a member (idempotent auto-join).

        Called when a new contractor is assigned to a trade scope after the
        scope thread was already created.

        Returns the existing or newly created membership.
        """
        existing = await self.thread_repo.find_membership(thread_id, user_id)
        if existing is not None:
            return existing

        membership = ChatMembership(
            company_id=company_id,
            thread_id=thread_id,
            user_id=user_id,
        )
        self.db.add(membership)
        await self.db.flush()
        await self.db.refresh(membership)
        return membership

    async def toggle_mute(
        self,
        thread_id: uuid.UUID,
        user_id: uuid.UUID,
        muted: bool,
    ) -> ChatMembership | None:
        """Update the muted flag on a user's membership in a thread.

        Returns the updated membership, or None if the user is not a member.
        """
        membership = await self.thread_repo.find_membership(thread_id, user_id)
        if membership is None:
            return None
        membership.muted = muted
        await self.db.flush()
        await self.db.refresh(membership)
        return membership

    # ------------------------------------------------------------------
    # Message operations
    # ------------------------------------------------------------------

    async def send_message(
        self,
        thread_id: uuid.UUID,
        sender_id: uuid.UUID,
        company_id: uuid.UUID,
        message_id: uuid.UUID,
        content: str | None = None,
        attachment_url: str | None = None,
        attachment_type: str | None = None,
        annotation_data: str | None = None,
        mentions: list[uuid.UUID] | None = None,
        mention_all: bool = False,
    ) -> ChatMessage | None:
        """Insert a message using ON CONFLICT DO NOTHING for client-UUID deduplication.

        The client generates the UUID (message_id) before sending. If the same
        UUID arrives twice (retry), the second insert is silently ignored and
        None is returned (caller should re-fetch the existing message if needed).

        seq is assigned by the DB via nextval('chat_message_seq') — no app-side
        sequence management needed. db.flush() is called after insert so the
        caller can access the generated seq.

        Args:
            thread_id: Target thread UUID.
            sender_id: User UUID of the message author.
            company_id: Owning company UUID (required by RLS).
            message_id: Client-generated UUID (idempotency key).
            content: Message text. Nullable for attachment-only messages.
            attachment_url: File path for uploaded attachment.
            attachment_type: One of 'photo', 'pdf', 'annotated_photo'.
            annotation_data: JSON string for annotated photo overlays.
            mentions: List of mentioned user UUIDs.
            mention_all: True if sender used @everyone.

        Returns:
            The inserted ChatMessage, or None if message_id already exists.
        """
        stmt = (
            pg_insert(ChatMessage)
            .values(
                id=message_id,
                company_id=company_id,
                thread_id=thread_id,
                sender_id=sender_id,
                content=content,
                attachment_url=attachment_url,
                attachment_type=attachment_type,
                annotation_data=annotation_data,
                mentions=[str(uid) for uid in (mentions or [])],
                mention_all=mention_all,
            )
            .on_conflict_do_nothing(index_elements=["id"])
            .returning(ChatMessage)
        )
        result = await self.db.execute(stmt)
        message = result.scalars().first()

        if message is not None:
            # Update thread's updated_at so list_by_project ordering works
            thread = await self.db.get(ChatThread, thread_id)
            if thread is not None:
                thread.updated_at = datetime.now(UTC)
                await self.db.flush()

        return message

    async def get_messages(
        self,
        thread_id: uuid.UUID,
        before_seq: int | None = None,
        limit: int = 50,
    ) -> list[ChatMessage]:
        """Retrieve messages for a thread with cursor pagination.

        Args:
            thread_id: The thread to fetch messages from.
            before_seq: Fetch messages older than this seq (for pagination).
            limit: Max messages to return.
        """
        return await self.message_repo.list_by_thread(
            thread_id=thread_id,
            before_seq=before_seq,
            limit=limit,
        )

    # ------------------------------------------------------------------
    # Thread listing
    # ------------------------------------------------------------------

    async def list_threads_for_user(
        self,
        project_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> list[ChatThread]:
        """List threads within a project that the given user is a member of.

        Returns threads ordered by updated_at DESC (most recently active first).
        Memberships are eager-loaded for member_count computation.
        """
        return await self.thread_repo.list_threads_for_user(project_id, user_id)

    # ------------------------------------------------------------------
    # Read receipts
    # ------------------------------------------------------------------

    async def mark_read(
        self,
        thread_id: uuid.UUID,
        user_id: uuid.UUID,
        company_id: uuid.UUID,
        seq: int,
    ) -> ChatReadReceipt:
        """Upsert read receipt, only advancing the position (never regressing).

        Uses INSERT ... ON CONFLICT DO UPDATE with a WHERE clause to ensure
        last_read_seq can only increase. This prevents a race where an older
        packet arriving late would overwrite a newer read position.

        Args:
            thread_id: The thread being marked as read.
            user_id: The user marking messages as read.
            company_id: Owning company UUID (required for RLS on insert).
            seq: The highest message seq the user has confirmed reading.
        """
        stmt = (
            pg_insert(ChatReadReceipt)
            .values(
                company_id=company_id,
                thread_id=thread_id,
                user_id=user_id,
                last_read_seq=seq,
                read_at=datetime.now(UTC),
            )
            .on_conflict_do_update(
                index_elements=["thread_id", "user_id"],
                set_={
                    "last_read_seq": seq,
                    "read_at": datetime.now(UTC),
                    "updated_at": datetime.now(UTC),
                },
                where=ChatReadReceipt.last_read_seq < seq,
            )
            .returning(ChatReadReceipt)
        )
        result = await self.db.execute(stmt)
        receipt = result.scalars().first()

        if receipt is None:
            # Conflict happened but WHERE prevented update (seq not advancing)
            # Return the existing receipt
            from sqlalchemy import select

            existing = await self.db.execute(
                select(ChatReadReceipt).where(
                    ChatReadReceipt.thread_id == thread_id,
                    ChatReadReceipt.user_id == user_id,
                )
            )
            receipt = existing.scalars().first()

        await self.db.flush()
        return receipt  # type: ignore[return-value]

    async def get_read_receipts(self, thread_id: uuid.UUID) -> list[ChatReadReceipt]:
        """List all read receipts for a thread (for "seen by" display).

        Returns all users' last read positions in the thread.
        No eager loading needed — ChatReadReceipt has no relationships.
        """
        from sqlalchemy import select

        stmt = select(ChatReadReceipt).where(ChatReadReceipt.thread_id == thread_id)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())
