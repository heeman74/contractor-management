"""SQLAlchemy ORM models for the real-time chat feature.

Four models correspond to tables created in migration 0020_chat:
  - ChatThread       — container for a conversation (per trade scope or project-wide)
  - ChatMessage      — individual message within a thread
  - ChatMembership   — user-to-thread membership (access + mute preference)
  - ChatReadReceipt  — per-user read position within a thread

All CLAUDE.md rules apply:
- Models with FK relationships MUST define relationship() with lazy="raise"
- All models inherit TenantScopedModel (provides id, company_id, version, timestamps)
- Use from __future__ import annotations + TYPE_CHECKING for circular-import safety
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.base_models import TenantScopedModel

if TYPE_CHECKING:
    pass


class ChatThread(TenantScopedModel):
    """A conversation thread scoped to a project.

    thread_type: 'scope' (one per trade scope, GC + that contractor)
                 or 'project_wide' (all project members)
    trade_scope_id: NULL for project_wide threads; FK to trade_scopes for scope threads.
    name: human-readable thread label (e.g. "Plumbing" or "Project-Wide").

    Relationships:
    - memberships: one-to-many — who can access this thread
    - messages: one-to-many — all messages in this thread
    """

    __tablename__ = "chat_threads"

    project_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("projects.id"),
        nullable=False,
    )
    thread_type: Mapped[str] = mapped_column(Text, nullable=False)
    trade_scope_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trade_scopes.id"),
        nullable=True,
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)

    __table_args__ = (
        CheckConstraint(
            "thread_type IN ('scope', 'project_wide')",
            name="chat_threads_type_check",
        ),
    )

    # Relationships — lazy="raise" per CLAUDE.md to catch accidental lazy loads
    memberships: Mapped[list[ChatMembership]] = relationship(
        "ChatMembership",
        back_populates="thread",
        lazy="raise",
    )
    messages: Mapped[list[ChatMessage]] = relationship(
        "ChatMessage",
        back_populates="thread",
        lazy="raise",
    )


class ChatMessage(TenantScopedModel):
    """An individual message within a chat thread.

    id: client-generated UUID used as idempotency key — sender provides UUID,
        server uses ON CONFLICT DO NOTHING to deduplicate retries.
    seq: server-assigned from chat_message_seq — stable monotonic ordering for
         cursor pagination and read receipt tracking. Never gaps.
    content: nullable — attachment-only messages may have no text.
    attachment_type: 'photo', 'pdf', or 'annotated_photo'.
    annotation_data: TEXT (serialized JSON) for annotated photo overlays.
    mentions: JSONB array of user UUIDs mentioned (@user).
    mention_all: true if sender used @everyone.

    Relationships:
    - thread: many-to-one back-reference to ChatThread
    """

    __tablename__ = "chat_messages"

    thread_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("chat_threads.id", ondelete="CASCADE"),
        nullable=False,
    )
    sender_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    content: Mapped[str | None] = mapped_column(Text, nullable=True)
    seq: Mapped[int] = mapped_column(BigInteger, nullable=False)
    attachment_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    attachment_type: Mapped[str | None] = mapped_column(Text, nullable=True)
    annotation_data: Mapped[str | None] = mapped_column(Text, nullable=True)
    mentions: Mapped[list] = mapped_column(JSONB, nullable=False, server_default="'[]'::jsonb")
    mention_all: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")

    __table_args__ = (
        CheckConstraint(
            "attachment_type IN ('photo', 'pdf', 'annotated_photo')",
            name="chat_messages_attachment_type_check",
        ),
    )

    # Relationships — lazy="raise" per CLAUDE.md
    thread: Mapped[ChatThread] = relationship(
        "ChatThread",
        back_populates="messages",
        lazy="raise",
    )


class ChatMembership(TenantScopedModel):
    """Maps a user to a chat thread they are a member of.

    muted: user has silenced push notifications for this thread.
    joined_at: when the user was added to the thread (for audit + display).
    UNIQUE (thread_id, user_id): enforced at DB level; upserted via ensure_membership.

    Relationships:
    - thread: many-to-one back-reference to ChatThread
    """

    __tablename__ = "chat_memberships"

    thread_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("chat_threads.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    muted: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    joined_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default="now()",
    )

    __table_args__ = (
        UniqueConstraint("thread_id", "user_id", name="uq_chat_memberships_thread_user"),
    )

    # Relationships — lazy="raise" per CLAUDE.md
    thread: Mapped[ChatThread] = relationship(
        "ChatThread",
        back_populates="memberships",
        lazy="raise",
    )


class ChatReadReceipt(TenantScopedModel):
    """Records the highest message seq a user has read in a thread.

    last_read_seq: cursor into the message stream — used to compute unread count.
    read_at: timestamp of the last mark_read action.
    UNIQUE (thread_id, user_id): upserted on every mark_read call.

    No relationships defined — read receipts are looked up by thread_id directly.
    """

    __tablename__ = "chat_read_receipts"

    thread_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("chat_threads.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    last_read_seq: Mapped[int] = mapped_column(BigInteger, nullable=False)
    read_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default="now()",
    )

    __table_args__ = (
        UniqueConstraint("thread_id", "user_id", name="uq_chat_read_receipts_thread_user"),
    )
