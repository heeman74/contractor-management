"""FastAPI router for AI intake and interview SSE streaming endpoints.

Endpoints:
  POST /ai/intake/start    — Start or resume a project intake conversation
  POST /ai/intake/message  — Send a message in an intake conversation (SSE stream)
  POST /ai/intake/complete — Commit AI-generated trade scopes to the DB
  POST /ai/interview/start    — Start an interview for a trade scope
  POST /ai/interview/message  — Send a message in an interview (SSE stream)
  POST /ai/interview/complete — Commit AI-generated tasks to the DB
  GET  /ai/conversations/{conversation_id} — Get conversation with messages

All endpoints require authentication via get_current_user.
SSE streaming endpoints return EventSourceResponse.
Complete endpoints wrap all DB work in the get_db transaction (auto-commit/rollback).
"""

from __future__ import annotations

import io
import os
import uuid
from typing import Annotated, Any

import aiofiles
from fastapi import APIRouter, Depends, Form, HTTPException, UploadFile, status
from fastapi.responses import StreamingResponse
from PIL import Image
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_service import entity_or_404
from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user
from app.features.ai.models import AIImageUpload
from app.features.ai.prompts.tools import INTAKE_TOOLS, INTERVIEW_TOOLS
from app.features.ai.repository import AIConversationRepository, AIMessageRepository
from app.features.ai.schemas import (
    ChatTurnRequest,
    ConversationResponse,
    ImageUploadResponse,
    IntakeCompleteRequest,
    InterviewCompleteRequest,
)
from app.features.ai.service import AIService

router = APIRouter(tags=["ai"])


# ---------------------------------------------------------------------------
# Helper: SSE streaming response
# ---------------------------------------------------------------------------


def _sse_response(stream) -> StreamingResponse:
    """Wrap an async generator of SSE event strings in a StreamingResponse."""
    return StreamingResponse(
        stream,
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


# ---------------------------------------------------------------------------
# POST /ai/intake/start
# ---------------------------------------------------------------------------


@router.post(
    "/ai/intake/start",
    status_code=status.HTTP_201_CREATED,
    response_model=ConversationResponse,
)
async def intake_start(
    project_id: uuid.UUID | None = None,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ConversationResponse:
    """Start or resume a project intake conversation.

    If an active intake conversation for this project already exists, returns it
    with 200 (caller can detect re-entry by comparing status_code if needed).
    New conversations return 201.
    """
    service = AIService(db)
    conv = await service.get_or_create_conversation(
        project_id=project_id,
        scope_id=None,
        conv_type="intake",
        user_id=current_user.user_id,
    )
    return ConversationResponse.model_validate(conv)


# ---------------------------------------------------------------------------
# POST /ai/intake/image
# ---------------------------------------------------------------------------


@router.post(
    "/ai/intake/image",
    response_model=ImageUploadResponse,
    status_code=status.HTTP_201_CREATED,
)
async def upload_image(
    file: UploadFile,
    conversation_id: Annotated[uuid.UUID, Form(...)],
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ImageUploadResponse:
    """Upload an image for AI chat context (Claude vision).

    Images are compressed server-side to max 1280x1280 JPEG before storage.
    The returned id is passed as image_ref_id in ChatTurnRequest to include
    the image as a base64 vision block in the Claude API call.
    Non-image files are rejected with 400.
    """
    # Validate content type
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="File must be an image (JPEG, PNG, etc.)")

    # Read and validate size (max 10MB raw)
    file_bytes = await file.read()
    if len(file_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Image must be under 10MB")

    # Compress with Pillow to max 1280x1280 JPEG
    img = Image.open(io.BytesIO(file_bytes))
    img.thumbnail((1280, 1280))
    buf = io.BytesIO()
    # Convert RGBA/P to RGB for JPEG compatibility
    if img.mode in ("RGBA", "P"):
        img = img.convert("RGB")
    img.save(buf, format="JPEG", quality=85)
    compressed_bytes = buf.getvalue()

    # Save to disk
    upload_dir = f"uploads/ai_images/{conversation_id}"
    os.makedirs(upload_dir, exist_ok=True)
    file_id = uuid.uuid4()
    file_path = f"{upload_dir}/{file_id}.jpg"
    async with aiofiles.open(file_path, "wb") as f:
        await f.write(compressed_bytes)

    # Create DB record
    image_record = AIImageUpload(
        conversation_id=conversation_id,
        user_id=current_user.user_id,
        company_id=current_user.company_id,
        file_path=file_path,
        original_filename=file.filename or "upload.jpg",
        media_type="image/jpeg",
        file_size_bytes=len(compressed_bytes),
    )
    db.add(image_record)
    await db.flush()

    return ImageUploadResponse.model_validate(image_record)


# ---------------------------------------------------------------------------
# POST /ai/intake/message
# ---------------------------------------------------------------------------


@router.post("/ai/intake/message")
async def intake_message(
    req: ChatTurnRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> StreamingResponse:
    """Send a user message in an intake conversation and stream the AI response.

    Returns a text/event-stream response with SSE events:
      event: token    — {"delta": "<text>"}
      event: tool_call — {"tool": "<name>", "input": {...}, "id": "<id>"}
      event: done     — {"stop_reason": "<reason>"}
      event: error    — {"message": "<user-friendly message>"} on failure
    """
    service = AIService(db)
    conv, messages, system_prompt = await service.load_conversation_context(
        req.conversation_id, current_user.user_id
    )

    if conv.status != "active":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Conversation is not active",
        )

    # Build user content (text or text+image for Claude vision)
    user_content: str | list = req.message
    if req.image_ref_id:
        image_block = await service.build_image_content_block(req.image_ref_id)
        if image_block:
            user_content = [image_block, {"type": "text", "text": req.message}]

    await service.persist_user_message(req.conversation_id, user_content, current_user.user_id)

    # Add the new user message to the messages list for this turn
    if isinstance(user_content, str):
        api_content: list[dict] = [{"type": "text", "text": user_content}]
    else:
        api_content = user_content  # type: ignore[assignment]
    messages = messages + [{"role": "user", "content": api_content}]

    stream = service.stream_turn(conv, messages, system_prompt, INTAKE_TOOLS)
    return _sse_response(stream)


# ---------------------------------------------------------------------------
# POST /ai/intake/complete
# ---------------------------------------------------------------------------


@router.post("/ai/intake/complete")
async def intake_complete(
    req: IntakeCompleteRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    """Commit AI-suggested trade scopes to the database.

    Creates the project (if project_id is None), creates all trade scopes, creates
    dependency edges for consecutive sorted scopes (D-23), and marks the conversation
    complete. All DB operations run in the get_db transaction — any failure triggers
    a full rollback with no orphan data.
    """
    return await AIService(db).commit_intake(req, current_user.user_id)


# ---------------------------------------------------------------------------
# POST /ai/interview/start
# ---------------------------------------------------------------------------


@router.post(
    "/ai/interview/start",
    status_code=status.HTTP_201_CREATED,
    response_model=ConversationResponse,
)
async def interview_start(
    scope_id: uuid.UUID,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ConversationResponse:
    """Start or resume an interview conversation for a trade scope.

    Verifies the trade scope exists before creating the conversation.
    """
    from sqlalchemy import select

    from app.features.projects.models import TradeScope

    # Verify scope exists and belongs to current tenant
    result = await db.execute(
        select(TradeScope).where(
            TradeScope.id == scope_id,
            TradeScope.deleted_at.is_(None),
        )
    )
    entity_or_404(result.scalars().first(), f"Trade scope {scope_id} not found")

    service = AIService(db)
    conv = await service.get_or_create_conversation(
        project_id=None,
        scope_id=scope_id,
        conv_type="interview",
        user_id=current_user.user_id,
    )
    return ConversationResponse.model_validate(conv)


# ---------------------------------------------------------------------------
# POST /ai/interview/message
# ---------------------------------------------------------------------------


@router.post("/ai/interview/message")
async def interview_message(
    req: ChatTurnRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> StreamingResponse:
    """Send a user message in an interview conversation and stream the AI response.

    Returns a text/event-stream response with the same SSE event format as intake/message.
    """
    service = AIService(db)
    conv, messages, system_prompt = await service.load_conversation_context(
        req.conversation_id, current_user.user_id
    )

    if conv.status != "active":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Conversation is not active",
        )

    # Build user content (text or text+image for Claude vision)
    user_content: str | list = req.message
    if req.image_ref_id:
        image_block = await service.build_image_content_block(req.image_ref_id)
        if image_block:
            user_content = [image_block, {"type": "text", "text": req.message}]

    await service.persist_user_message(req.conversation_id, user_content, current_user.user_id)

    # Add the new user message to the messages list for this turn
    if isinstance(user_content, str):
        api_content: list[dict] = [{"type": "text", "text": user_content}]
    else:
        api_content = user_content  # type: ignore[assignment]
    messages = messages + [{"role": "user", "content": api_content}]

    stream = service.stream_turn(conv, messages, system_prompt, INTERVIEW_TOOLS)
    return _sse_response(stream)


# ---------------------------------------------------------------------------
# POST /ai/interview/complete
# ---------------------------------------------------------------------------


@router.post("/ai/interview/complete")
async def interview_complete(
    req: InterviewCompleteRequest,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    """Commit AI-suggested tasks to the database for a trade scope.

    Soft-deletes any existing tasks for the scope (D-19 re-interview cleanup),
    creates new tasks from the interview, and marks the conversation complete.
    All DB operations run in the get_db transaction — any failure triggers full rollback.
    """
    return await AIService(db).commit_interview(req)


# ---------------------------------------------------------------------------
# GET /ai/conversations/{conversation_id}
# ---------------------------------------------------------------------------


@router.get("/ai/conversations/{conversation_id}")
async def get_conversation(
    conversation_id: uuid.UUID,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    """Get a conversation with all its messages.

    Used for re-entry (resuming a conversation) and transcript viewing.
    """
    conv_repo = AIConversationRepository(db)
    msg_repo = AIMessageRepository(db)

    conv = entity_or_404(
        await conv_repo.get_by_id(conversation_id), f"Conversation {conversation_id} not found"
    )

    messages = await msg_repo.list_by_conversation(conversation_id)

    return {
        "id": str(conv.id),
        "conv_type": conv.conv_type,
        "status": conv.status,
        "project_id": str(conv.project_id) if conv.project_id else None,
        "scope_id": str(conv.scope_id) if conv.scope_id else None,
        "messages": [
            {
                "id": str(msg.id),
                "role": msg.role,
                "content_json": msg.content_json,
                "sequence_num": msg.sequence_num,
            }
            for msg in messages
        ],
    }
