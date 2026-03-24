"""Pydantic schemas for the real-time chat feature.

Response schemas inherit BaseResponseSchema (id, version, created_at, updated_at).
Request schemas are plain BaseModel subclasses (no DB fields needed).

Per CLAUDE.md:
  - All response schemas MUST inherit from BaseResponseSchema
  - Use model_validate() for ORM-to-Pydantic conversion
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.core.base_schemas import BaseResponseSchema, TenantResponseSchema


class ChatMembershipResponse(TenantResponseSchema):
    """Membership record for a user in a thread."""

    thread_id: uuid.UUID
    user_id: uuid.UUID
    muted: bool
    joined_at: datetime


class ChatThreadResponse(TenantResponseSchema):
    """A chat thread with membership count and optional last-message preview.

    last_message: populated by the endpoint layer when available (not from ORM).
    unread_count: computed from read receipts + latest seq (not from ORM).
    member_count: len(memberships) — populated after eager load.
    """

    project_id: uuid.UUID
    thread_type: str
    trade_scope_id: uuid.UUID | None = None
    name: str
    # Populated by endpoint layer after service call
    last_message: ChatMessageResponse | None = None
    unread_count: int = 0
    member_count: int = 0


class ChatMessageResponse(TenantResponseSchema):
    """A single chat message with sender display name.

    sender_name: resolved from user lookup in the endpoint layer (not ORM).
    seq: server-assigned monotonic ordering key.
    """

    thread_id: uuid.UUID
    sender_id: uuid.UUID
    sender_name: str = ""
    content: str | None = None
    seq: int
    attachment_url: str | None = None
    attachment_type: str | None = None
    annotation_data: str | None = None
    mentions: list[uuid.UUID] = Field(default_factory=list)
    mention_all: bool = False


class ChatReadReceiptResponse(BaseResponseSchema):
    """Read position record for a single user in a thread.

    user_name: resolved from user lookup in the endpoint layer.
    """

    thread_id: uuid.UUID
    user_id: uuid.UUID
    user_name: str = ""
    last_read_seq: int
    read_at: datetime


# ---------------------------------------------------------------------------
# Request schemas (input validation)
# ---------------------------------------------------------------------------


class SendMessageRequest(BaseModel):
    """Request body for POST /chat/threads/{thread_id}/messages.

    id: client-generated UUID — used as idempotency key. The client MUST
        generate a fresh UUID for each new message attempt. Retrying with the
        same UUID is safe (ON CONFLICT DO NOTHING on the server side).
    content: message text. At least one of content or attachment_url required.
    """

    model_config = ConfigDict(from_attributes=False)

    id: uuid.UUID
    content: str | None = None
    attachment_url: str | None = None
    attachment_type: str | None = None
    annotation_data: str | None = None
    mentions: list[uuid.UUID] = Field(default_factory=list)
    mention_all: bool = False


class MarkReadRequest(BaseModel):
    """Request body for POST /chat/threads/{thread_id}/read."""

    model_config = ConfigDict(from_attributes=False)

    seq: int


class ToggleMuteRequest(BaseModel):
    """Request body for PATCH /chat/threads/{thread_id}/mute."""

    model_config = ConfigDict(from_attributes=False)

    muted: bool


# Resolve forward reference: ChatThreadResponse.last_message = ChatMessageResponse
ChatThreadResponse.model_rebuild()
