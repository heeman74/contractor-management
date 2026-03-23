"""Pydantic schemas for AI conversation and chat turn request/response."""

import uuid
from typing import Literal

from pydantic import BaseModel, Field

from app.core.base_schemas import TenantResponseSchema


class ConversationCreate(BaseModel):
    """Request schema for creating a new AI conversation."""

    project_id: uuid.UUID | None = None
    scope_id: uuid.UUID | None = None
    conv_type: Literal["intake", "interview"]


class ChatTurnRequest(BaseModel):
    """Request schema for a single chat turn (user message)."""

    conversation_id: uuid.UUID
    message: str = Field(min_length=1, max_length=10000)
    image_ref_id: uuid.UUID | None = None


class ConversationResponse(TenantResponseSchema):
    """Response schema for an AI conversation."""

    project_id: uuid.UUID | None
    scope_id: uuid.UUID | None
    user_id: uuid.UUID
    conv_type: str
    status: str


class AIMessageResponse(TenantResponseSchema):
    """Response schema for an AI message."""

    conversation_id: uuid.UUID
    role: str
    content_json: dict
    sequence_num: int
