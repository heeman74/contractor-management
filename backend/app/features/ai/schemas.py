"""Pydantic schemas for AI conversation and chat turn request/response."""

import uuid
from typing import Any, Literal

from pydantic import BaseModel, Field

from app.core.base_schemas import BaseResponseSchema, TenantResponseSchema


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


class ImageUploadResponse(BaseResponseSchema):
    """Response schema for an uploaded AI image."""

    conversation_id: uuid.UUID
    original_filename: str
    media_type: str
    file_size_bytes: int


class IntakeCompleteRequest(BaseModel):
    """Request body for POST /ai/intake/complete."""

    conversation_id: uuid.UUID
    project_name: str = Field(min_length=1, max_length=200)
    project_description: str | None = None
    project_id: uuid.UUID | None = None
    trade_scopes: list[dict[str, Any]] = Field(default_factory=list)


class InterviewCompleteRequest(BaseModel):
    """Request body for POST /ai/interview/complete."""

    conversation_id: uuid.UUID
    tasks: list[dict[str, Any]] = Field(default_factory=list)
