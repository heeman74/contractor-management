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

import uuid
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user
from app.features.ai.prompts.tools import INTAKE_TOOLS, INTERVIEW_TOOLS
from app.features.ai.repository import AIConversationRepository, AIMessageRepository
from app.features.ai.schemas import (
    ChatTurnRequest,
    ConversationResponse,
)
from app.features.ai.service import AIService
from app.features.projects.schemas import (
    ProjectCreate,
    TaskCreate,
    TaskDependencyCreate,
    TradeScopeCreate,
)
from app.features.projects.service import (
    DependencyService,
    ProjectService,
    TaskService,
    TradeScopeService,
)

router = APIRouter(tags=["ai"])


# ---------------------------------------------------------------------------
# Request schemas specific to this router
# ---------------------------------------------------------------------------


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

    await service.persist_user_message(
        req.conversation_id, req.message, current_user.user_id
    )

    # Add the new user message to the messages list for this turn
    messages = messages + [{"role": "user", "content": [{"type": "text", "text": req.message}]}]

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
    service = AIService(db)

    # Verify conversation is active
    conv_repo = AIConversationRepository(db)
    conv = await conv_repo.get_by_id(req.conversation_id)
    if conv is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Conversation {req.conversation_id} not found",
        )
    if conv.status != "active":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Conversation is not active",
        )

    # Create project if not provided
    project_id = req.project_id
    if project_id is None:
        project_svc = ProjectService(db)
        project = await project_svc.create(
            ProjectCreate(name=req.project_name, description=req.project_description),
            user_id=current_user.user_id,
        )
        await db.flush()
        project_id = project.id

    # Sort trade scopes by sort_order then create them
    sorted_scopes = sorted(req.trade_scopes, key=lambda s: s.get("sort_order", 0))
    scope_svc = TradeScopeService(db)
    created_scopes = []
    for scope_data in sorted_scopes:
        scope = await scope_svc.create(
            TradeScopeCreate(
                project_id=project_id,
                trade_name=scope_data["trade_name"],
                trade_color=scope_data.get("trade_color", "#9E9E9E"),
            ),
            user_id=current_user.user_id,
        )
        await db.flush()
        created_scopes.append(scope)

    # Create dependency edges for consecutive trade scopes (D-23).
    # For each consecutive pair (scope[n], scope[n+1]), create a placeholder task
    # per scope and link them with a FS dependency edge. This wires the sequencing
    # into the dependency engine so it can block/unblock tasks when contractors
    # add real work tasks later.
    task_svc = TaskService(db)
    dep_svc = DependencyService(db)
    scope_placeholder_task_ids: dict[uuid.UUID, uuid.UUID] = {}

    for scope in created_scopes:
        placeholder = await task_svc.create(
            TaskCreate(
                trade_scope_id=scope.id,
                title=f"[Scope placeholder] {scope.trade_name}",
                description="Auto-created placeholder for cross-scope dependency sequencing.",
                priority="low",
            )
        )
        await db.flush()
        scope_placeholder_task_ids[scope.id] = placeholder.id

    # Link consecutive scopes: scope[n] placeholder -> scope[n+1] placeholder
    for i in range(len(created_scopes) - 1):
        pred_scope = created_scopes[i]
        succ_scope = created_scopes[i + 1]
        pred_task_id = scope_placeholder_task_ids[pred_scope.id]
        succ_task_id = scope_placeholder_task_ids[succ_scope.id]
        await dep_svc.create_dependency(
            succ_task_id,
            TaskDependencyCreate(predecessor_task_id=pred_task_id),
        )

    # Track created scope IDs in order
    scope_ids = [scope.id for scope in created_scopes]

    # Mark conversation complete
    await service.mark_complete(req.conversation_id)

    return {
        "project_id": str(project_id),
        "trade_scope_ids": [str(sid) for sid in scope_ids],
    }


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
    scope = result.scalars().first()
    if scope is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Trade scope {scope_id} not found",
        )

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

    await service.persist_user_message(
        req.conversation_id, req.message, current_user.user_id
    )

    # Add the new user message to the messages list for this turn
    messages = messages + [{"role": "user", "content": [{"type": "text", "text": req.message}]}]

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
    from datetime import UTC, datetime

    from sqlalchemy import select

    from app.features.projects.models import Task

    service = AIService(db)

    # Verify conversation is active and get the scope_id
    conv_repo = AIConversationRepository(db)
    conv = await conv_repo.get_by_id(req.conversation_id)
    if conv is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Conversation {req.conversation_id} not found",
        )
    if conv.status != "active":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Conversation is not active",
        )
    if conv.scope_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Conversation does not have an associated trade scope",
        )

    scope_id = conv.scope_id

    # Soft-delete existing tasks for this scope (D-19 re-interview cleanup)
    result = await db.execute(
        select(Task).where(
            Task.trade_scope_id == scope_id,
            Task.deleted_at.is_(None),
        )
    )
    existing_tasks = result.scalars().all()
    now = datetime.now(UTC)
    for existing_task in existing_tasks:
        existing_task.deleted_at = now
    await db.flush()

    # Create new tasks from the interview
    task_svc = TaskService(db)
    created_task_ids = []
    for task_data in req.tasks:
        task = await task_svc.create(
            TaskCreate(
                trade_scope_id=scope_id,
                title=task_data["title"],
                description=task_data.get("description"),
                priority=task_data.get("priority", "medium"),
                estimated_hours=task_data.get("estimated_hours"),
                materials_needed=task_data.get("materials_needed", []),
            )
        )
        await db.flush()
        created_task_ids.append(task.id)

    # Mark conversation complete
    await service.mark_complete(req.conversation_id)

    return {"task_ids": [str(tid) for tid in created_task_ids]}


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

    conv = await conv_repo.get_by_id(conversation_id)
    if conv is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Conversation {conversation_id} not found",
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
