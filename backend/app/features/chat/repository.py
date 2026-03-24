"""Repositories for the chat feature.

Two repositories:
  - ChatThreadRepository  — thread-level queries (by project, with memberships)
  - ChatMessageRepository — message-level queries (cursor pagination by seq)

Both inherit TenantScopedRepository for automatic company_id filtering via RLS.
"""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.base_repository import TenantScopedRepository
from app.features.chat.models import ChatMembership, ChatMessage, ChatThread


class ChatThreadRepository(TenantScopedRepository[ChatThread]):
    """Repository for ChatThread with membership and message eager-loading."""

    model = ChatThread

    async def list_by_project(self, project_id: uuid.UUID) -> list[ChatThread]:
        """List all threads for a project, with memberships eager-loaded.

        Ordered by updated_at DESC so the most recently active thread appears first.
        RLS automatically filters to the current tenant.
        """
        stmt = (
            select(ChatThread)
            .where(ChatThread.project_id == project_id)
            .where(ChatThread.deleted_at.is_(None))
            .options(selectinload(ChatThread.memberships))
            .order_by(ChatThread.updated_at.desc())
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_with_memberships(self, thread_id: uuid.UUID) -> ChatThread | None:
        """Retrieve a single thread with memberships eager-loaded."""
        stmt = (
            select(ChatThread)
            .where(ChatThread.id == thread_id)
            .where(ChatThread.deleted_at.is_(None))
            .options(selectinload(ChatThread.memberships))
        )
        result = await self.db.execute(stmt)
        return result.scalars().first()

    async def find_scope_thread(
        self, project_id: uuid.UUID, trade_scope_id: uuid.UUID
    ) -> ChatThread | None:
        """Find an existing scope thread for a given trade scope (for idempotency).

        Returns None if no thread has been created yet for this scope.
        """
        stmt = (
            select(ChatThread)
            .where(ChatThread.project_id == project_id)
            .where(ChatThread.trade_scope_id == trade_scope_id)
            .where(ChatThread.thread_type == "scope")
            .where(ChatThread.deleted_at.is_(None))
        )
        result = await self.db.execute(stmt)
        return result.scalars().first()

    async def find_project_wide_thread(self, project_id: uuid.UUID) -> ChatThread | None:
        """Find the existing project-wide thread for a project (for idempotency)."""
        stmt = (
            select(ChatThread)
            .where(ChatThread.project_id == project_id)
            .where(ChatThread.thread_type == "project_wide")
            .where(ChatThread.deleted_at.is_(None))
        )
        result = await self.db.execute(stmt)
        return result.scalars().first()

    async def find_membership(
        self, thread_id: uuid.UUID, user_id: uuid.UUID
    ) -> ChatMembership | None:
        """Find an existing membership record for a user in a thread."""
        stmt = select(ChatMembership).where(
            ChatMembership.thread_id == thread_id,
            ChatMembership.user_id == user_id,
        )
        result = await self.db.execute(stmt)
        return result.scalars().first()

    async def list_threads_for_user(
        self, project_id: uuid.UUID, user_id: uuid.UUID
    ) -> list[ChatThread]:
        """List threads the user is a member of within a project.

        Uses a JOIN through chat_memberships to filter to only threads
        this user can access. Eager-loads memberships for member count.
        """
        stmt = (
            select(ChatThread)
            .join(
                ChatMembership,
                (ChatMembership.thread_id == ChatThread.id) & (ChatMembership.user_id == user_id),
            )
            .where(ChatThread.project_id == project_id)
            .where(ChatThread.deleted_at.is_(None))
            .options(selectinload(ChatThread.memberships))
            .order_by(ChatThread.updated_at.desc())
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())


class ChatMessageRepository(TenantScopedRepository[ChatMessage]):
    """Repository for ChatMessage with cursor pagination support."""

    model = ChatMessage

    async def list_by_thread(
        self,
        thread_id: uuid.UUID,
        before_seq: int | None = None,
        limit: int = 50,
    ) -> list[ChatMessage]:
        """List messages for a thread, ordered ascending by seq.

        Supports cursor pagination: pass before_seq to fetch messages older than
        that seq value. Results are returned in ascending order (oldest first)
        so the UI can append new messages at the bottom.

        Args:
            thread_id: The thread to fetch messages from.
            before_seq: If provided, fetch only messages with seq < before_seq.
            limit: Maximum number of messages to return (default 50).
        """
        stmt = (
            select(ChatMessage)
            .where(ChatMessage.thread_id == thread_id)
            .where(ChatMessage.deleted_at.is_(None))
        )
        if before_seq is not None:
            stmt = stmt.where(ChatMessage.seq < before_seq)

        # Fetch DESC to get the N most recent, then reverse to return ASC
        stmt = stmt.order_by(ChatMessage.seq.desc()).limit(limit)
        result = await self.db.execute(stmt)
        messages = list(result.scalars().all())
        # Return in ascending order (oldest first) for UI rendering
        return list(reversed(messages))

    async def get_by_uuid(self, message_id: uuid.UUID) -> ChatMessage | None:
        """Fetch a message by its UUID primary key (for dedup verification)."""
        return await self.db.get(ChatMessage, message_id)

    async def get_latest_seq(self, thread_id: uuid.UUID) -> int | None:
        """Return the highest seq in a thread, or None if no messages yet."""
        from sqlalchemy import func

        stmt = select(func.max(ChatMessage.seq)).where(
            ChatMessage.thread_id == thread_id,
            ChatMessage.deleted_at.is_(None),
        )
        result = await self.db.execute(stmt)
        return result.scalar()
