"""SQLAlchemy ORM models for AI conversations, messages, and token usage.

Three models for the AI conversation system:
  - AIConversation — a chat session for project intake or contractor interview
  - AIMessage      — a single message (user or assistant) in a conversation
  - AITokenUsage   — token usage record for analytics and cost tracking

All CLAUDE.md rules apply:
- Models with FK relationships MUST define relationship() with lazy="raise"
- All models inherit TenantScopedModel (provides id, company_id, version, timestamps)
- Use from __future__ import annotations + TYPE_CHECKING for circular-import safety
"""

from __future__ import annotations

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, ForeignKey, Integer, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.base_models import TenantScopedModel

if TYPE_CHECKING:
    from app.features.projects.models import Project, TradeScope
    from app.features.users.models import User


class AIConversation(TenantScopedModel):
    """A chat session for project intake or contractor interview.

    conv_type: 'intake' (GC describes project → AI creates trade scopes)
               or 'interview' (AI asks contractor questions → creates tasks)
    status: active → complete or abandoned

    project_id: nullable FK to projects — set for intake conversations
    scope_id: nullable FK to trade_scopes — set for interview conversations
    user_id: the user who created and owns this conversation

    Relationships:
    - messages: one-to-many — all messages in this conversation
    - project: nullable many-to-one FK to projects
    - scope: nullable many-to-one FK to trade_scopes
    """

    __tablename__ = "ai_conversations"

    project_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("projects.id", ondelete="SET NULL"),
        nullable=True,
    )
    scope_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trade_scopes.id", ondelete="SET NULL"),
        nullable=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    conv_type: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="active")

    __table_args__ = (
        CheckConstraint(
            "conv_type IN ('intake','interview')",
            name="ai_conversations_conv_type_check",
        ),
        CheckConstraint(
            "status IN ('active','complete','abandoned')",
            name="ai_conversations_status_check",
        ),
    )

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    messages: Mapped[list[AIMessage]] = relationship(
        "AIMessage",
        back_populates="conversation",
        lazy="raise",
    )
    project: Mapped[Project | None] = relationship(  # type: ignore[name-defined]
        "Project",
        foreign_keys=[project_id],
        lazy="raise",
    )
    scope: Mapped[TradeScope | None] = relationship(  # type: ignore[name-defined]
        "TradeScope",
        foreign_keys=[scope_id],
        lazy="raise",
    )
    user: Mapped[User] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[user_id],
        lazy="raise",
    )


class AIMessage(TenantScopedModel):
    """A single message in an AI conversation.

    role: 'user' or 'assistant'
    content_json: Claude API content array stored verbatim as JSONB.
                  For user messages: [{"type":"text","text":"..."}]
                  For assistant messages: full content array including tool_use blocks
                  For tool results: [{"type":"tool_result","tool_use_id":"...","content":"..."}]
    sequence_num: 0-indexed order within conversation

    UNIQUE(conversation_id, sequence_num): prevents duplicate ordering.

    Relationships:
    - conversation: many-to-one FK to ai_conversations
    """

    __tablename__ = "ai_messages"

    conversation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("ai_conversations.id", ondelete="CASCADE"),
        nullable=False,
    )
    role: Mapped[str] = mapped_column(Text, nullable=False)
    content_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    sequence_num: Mapped[int] = mapped_column(Integer, nullable=False)

    __table_args__ = (
        UniqueConstraint("conversation_id", "sequence_num", name="uq_ai_message_sequence"),
        CheckConstraint(
            "role IN ('user','assistant')",
            name="ai_messages_role_check",
        ),
    )

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    conversation: Mapped[AIConversation] = relationship(
        "AIConversation",
        back_populates="messages",
        lazy="raise",
    )


class AITokenUsage(TenantScopedModel):
    """Token usage record for analytics and cost tracking.

    Records input/output token counts per API call.
    These records are immutable — never soft-deleted.

    conversation_id: FK to ai_conversations (without CASCADE — usage records persist)
    user_id: the user who triggered the API call
    model: the Claude model used (e.g. 'claude-sonnet-4-6')
    input_tokens: prompt + context tokens consumed
    output_tokens: completion tokens generated
    """

    __tablename__ = "ai_token_usage"

    conversation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("ai_conversations.id"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    model: Mapped[str] = mapped_column(Text, nullable=False)
    input_tokens: Mapped[int] = mapped_column(Integer, nullable=False)
    output_tokens: Mapped[int] = mapped_column(Integer, nullable=False)
