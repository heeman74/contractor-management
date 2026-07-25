"""AIService — business logic for AI conversation management and Claude API streaming.

Handles:
- Conversation creation and retrieval (intake and interview types)
- Claude API calls with tool use and SSE streaming
- Message persistence (user, assistant, tool result)
- Token usage recording for analytics
- Tool input validation matching TradeScopeCreate / TaskCreate field constraints
- Retry logic with exponential backoff on transient API failures

Claude model: claude-sonnet-4-6 (latest claude-sonnet-4 model)
Max tokens: 4096 per turn
Retry: 3 attempts, 1s/2s/4s delays
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, datetime
from decimal import Decimal
from itertools import pairwise
from typing import Any

import aiofiles
from anthropic import APIError, APITimeoutError, AsyncAnthropic, RateLimitError
from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.ai_utils import call_claude_json
from app.core.base_service import TenantScopedService
from app.core.config import settings
from app.features.ai.models import AIConversation, AIImageUpload, AIMessage, AITokenUsage
from app.features.ai.prompts.intake_system import INTAKE_SYSTEM_PROMPT
from app.features.ai.prompts.interview_system import INTERVIEW_SYSTEM_PROMPT
from app.features.ai.repository import (
    AIConversationRepository,
    AIMessageRepository,
    AITokenUsageRepository,
)
from app.features.ai.schemas import IntakeCompleteRequest, InterviewCompleteRequest
from app.features.projects.models import Task
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

logger = logging.getLogger(__name__)

_CONVERSATION_STATUS_ACTIVE = "active"
_DEFAULT_TRADE_COLOR = "#9E9E9E"

# Starter-task seeding on intake completion (each new scope gets real,
# editable tasks instead of an empty placeholder).
_STARTER_TASKS_PER_SCOPE = 4
_MAX_TASK_TITLE_LEN = 300
_VALID_TASK_PRIORITIES = frozenset({"low", "medium", "high"})
_STARTER_TASKS_SYSTEM_PROMPT = (
    "You are a construction project planner. Given a project and its trade "
    "scopes, produce a short list of concrete, sequential starter tasks for "
    "EACH trade scope. Tasks must be specific and actionable for the described "
    "project. Respond with ONLY JSON, no prose."
)

# Module-level Anthropic client. Prefer the key from settings (.env is the
# single source of truth); when unset, api_key=None lets the SDK fall back to
# the ANTHROPIC_API_KEY environment variable.
_anthropic_client = AsyncAnthropic(api_key=settings.anthropic_api_key)

_CLAUDE_MODEL = "claude-sonnet-4-6"
_MAX_TOKENS = 4096
_RETRY_DELAYS = [1.0, 2.0, 4.0]  # seconds between retry attempts


def _sse(event: str, data: dict[str, Any]) -> str:
    """Format a single SSE event string."""
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


class AIService(TenantScopedService[AIConversation]):
    """Service for AI conversation management and Claude API streaming."""

    repository_class = AIConversationRepository

    def __init__(self, db: AsyncSession) -> None:
        super().__init__(db)
        self._message_repo = AIMessageRepository(db)
        self._usage_repo = AITokenUsageRepository(db)

    # -------------------------------------------------------------------------
    # Conversation management
    # -------------------------------------------------------------------------

    async def get_or_create_conversation(
        self,
        project_id: uuid.UUID | None,
        scope_id: uuid.UUID | None,
        conv_type: str,
        user_id: uuid.UUID,
    ) -> AIConversation:
        """Look up an active conversation or create a new one.

        For 'intake': looks up by project_id + conv_type.
        For 'interview': looks up by scope_id.
        """
        company_id = self._require_tenant_id()

        existing: AIConversation | None = None
        if conv_type == "intake" and project_id is not None:
            existing = await self.repository.get_active_for_project(project_id, conv_type)
        elif conv_type == "interview" and scope_id is not None:
            existing = await self.repository.get_active_for_scope(scope_id)

        if existing is not None:
            return existing

        conv = AIConversation(
            company_id=company_id,
            project_id=project_id,
            scope_id=scope_id,
            user_id=user_id,
            conv_type=conv_type,
            status="active",
        )
        return await self.repository.create(conv)

    async def load_conversation_context(
        self,
        conversation_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> tuple[AIConversation, list[dict[str, Any]], str]:
        """Load conversation + message history + system prompt.

        Returns (conversation, messages_for_api, system_prompt).
        messages_for_api is the Claude API message array.
        """
        conv = await self.repository.get_by_id(conversation_id)
        if conv is None:
            raise ValueError(f"Conversation {conversation_id} not found")

        db_messages = await self._message_repo.list_by_conversation(conversation_id)
        messages = [{"role": msg.role, "content": msg.content_json} for msg in db_messages]

        system_prompt = self._build_system_prompt(conv)
        return conv, messages, system_prompt

    def _build_system_prompt(self, conv: AIConversation) -> str:
        """Format the appropriate system prompt template with runtime context."""
        if conv.conv_type == "intake":
            # Runtime context placeholders — callers can pre-format if needed.
            # Defaults provide graceful no-op when context is not injected.
            return INTAKE_SYSTEM_PROMPT.format(
                trade_catalog="(No trade catalog entries available — use standard trade names)",
                project_context="(No existing project context — this is a new conversation)",
            )
        return INTERVIEW_SYSTEM_PROMPT.format(
            project_description="(Project description not provided)",
            trade_scope="(Trade scope details not provided)",
            all_scopes="(No other scopes on this project)",
        )

    async def build_system_prompt_with_context(
        self,
        conv: AIConversation,
        trade_catalog_text: str = "",
        project_context_text: str = "",
        project_description_text: str = "",
        trade_scope_text: str = "",
        all_scopes_text: str = "",
    ) -> str:
        """Format system prompt with fully-populated runtime context.

        Called by endpoints that have already loaded project/scope data.
        """
        if conv.conv_type == "intake":
            return INTAKE_SYSTEM_PROMPT.format(
                trade_catalog=trade_catalog_text or "(No trade catalog entries)",
                project_context=project_context_text or "(New conversation — no existing context)",
            )
        return INTERVIEW_SYSTEM_PROMPT.format(
            project_description=project_description_text or "(Not provided)",
            trade_scope=trade_scope_text or "(Not provided)",
            all_scopes=all_scopes_text or "(No other scopes)",
        )

    # -------------------------------------------------------------------------
    # Message persistence
    # -------------------------------------------------------------------------

    async def persist_user_message(
        self,
        conversation_id: uuid.UUID,
        content: str | list[dict[str, Any]],
        user_id: uuid.UUID,
    ) -> AIMessage:
        """Persist a user message. String content is wrapped in text block."""
        company_id = self._require_tenant_id()
        seq = await self._message_repo.get_next_sequence(conversation_id)

        if isinstance(content, str):
            content_json: list[dict[str, Any]] = [{"type": "text", "text": content}]
        else:
            content_json = content

        msg = AIMessage(
            company_id=company_id,
            conversation_id=conversation_id,
            role="user",
            content_json=content_json,
            sequence_num=seq,
        )
        return await self._message_repo.create(msg)

    async def persist_assistant_message(
        self,
        conversation_id: uuid.UUID,
        content_blocks: list[dict[str, Any]],
    ) -> AIMessage:
        """Persist an assistant message. content_blocks is the full Claude content array."""
        company_id = self._require_tenant_id()
        seq = await self._message_repo.get_next_sequence(conversation_id)

        msg = AIMessage(
            company_id=company_id,
            conversation_id=conversation_id,
            role="assistant",
            content_json=content_blocks,
            sequence_num=seq,
        )
        return await self._message_repo.create(msg)

    async def persist_tool_result(
        self,
        conversation_id: uuid.UUID,
        tool_use_id: str,
        result: str,
    ) -> AIMessage:
        """Persist a tool result as a user message (Claude API format)."""
        company_id = self._require_tenant_id()
        seq = await self._message_repo.get_next_sequence(conversation_id)

        content_json: list[dict[str, Any]] = [
            {"type": "tool_result", "tool_use_id": tool_use_id, "content": result}
        ]
        msg = AIMessage(
            company_id=company_id,
            conversation_id=conversation_id,
            role="user",
            content_json=content_json,
            sequence_num=seq,
        )
        return await self._message_repo.create(msg)

    async def record_usage(
        self,
        conversation_id: uuid.UUID,
        user_id: uuid.UUID,
        model: str,
        input_tokens: int,
        output_tokens: int,
    ) -> AITokenUsage:
        """Record token usage for analytics."""
        company_id = self._require_tenant_id()
        usage = AITokenUsage(
            company_id=company_id,
            conversation_id=conversation_id,
            user_id=user_id,
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
        )
        return await self._usage_repo.create(usage)

    # -------------------------------------------------------------------------
    # Claude API streaming
    # -------------------------------------------------------------------------

    async def stream_turn(
        self,
        conversation: AIConversation,
        messages: list[dict[str, Any]],
        system_prompt: str,
        tools: list[dict[str, Any]],
    ) -> AsyncGenerator[str, None]:
        """Stream a Claude API turn as SSE events.

        Yields SSE event strings:
          event: token    — {"delta": "<text>"}
          event: tool_call — {"tool": "<name>", "input": {...}, "id": "<id>"}
          event: done     — {"stop_reason": "<reason>"}
          event: error    — {"message": "<user-friendly message>"} on failure

        The generator does NOT persist messages — the caller is responsible for
        persisting the user message before calling and the assistant message after.

        Callers should call stream.get_final_message() to get the full message
        (not available here since we yield before completion). Instead, the
        caller collects content_blocks from the yielded tool_call events and
        text deltas for their own persistence.
        """
        try:
            async for event_str in self._call_with_retry(
                conversation, messages, system_prompt, tools
            ):
                yield event_str
        except Exception as exc:
            logger.exception("Unrecoverable error in stream_turn: %s", exc)
            yield _sse("error", {"message": "Something went wrong. Please try again."})

    async def _call_with_retry(
        self,
        conversation: AIConversation,
        messages: list[dict[str, Any]],
        system_prompt: str,
        tools: list[dict[str, Any]],
    ) -> AsyncGenerator[str, None]:
        """Internal retry wrapper with exponential backoff (3 attempts)."""
        last_exc: Exception | None = None
        for attempt, delay in enumerate([0.0] + _RETRY_DELAYS):
            if delay > 0:
                await asyncio.sleep(delay)
            try:
                async for event_str in self._stream_once(messages, system_prompt, tools):
                    yield event_str
                return  # success — stop retrying
            except (APITimeoutError, RateLimitError) as exc:
                last_exc = exc
                logger.warning(
                    "Claude API transient error (attempt %d/%d): %s",
                    attempt + 1,
                    len(_RETRY_DELAYS) + 1,
                    exc,
                )
            except APIError as exc:
                # Non-retryable API error — raise immediately
                raise exc from exc

        # All retries exhausted
        raise last_exc or RuntimeError("All retry attempts failed")

    async def _stream_once(
        self,
        messages: list[dict[str, Any]],
        system_prompt: str,
        tools: list[dict[str, Any]],
    ) -> AsyncGenerator[str, None]:
        """Single Claude API streaming call. Yields SSE event strings."""
        async with _anthropic_client.messages.stream(
            model=_CLAUDE_MODEL,
            max_tokens=_MAX_TOKENS,
            system=system_prompt,
            tools=tools,
            messages=messages,
        ) as stream:
            async for event in stream:
                event_type = getattr(event, "type", None)

                if event_type == "content_block_delta":
                    delta = getattr(event, "delta", None)
                    if delta is not None and getattr(delta, "type", None) == "text_delta":
                        yield _sse("token", {"delta": delta.text})

            # Stream complete — emit tool calls and done event
            final_msg = await stream.get_final_message()

            for block in final_msg.content:
                if block.type == "tool_use":
                    yield _sse(
                        "tool_call",
                        {"tool": block.name, "input": block.input, "id": block.id},
                    )

            yield _sse("done", {"stop_reason": final_msg.stop_reason})

    # -------------------------------------------------------------------------
    # Tool input validation
    # -------------------------------------------------------------------------

    async def validate_tool_input(
        self, tool_name: str, tool_input: dict[str, Any]
    ) -> dict[str, Any]:
        """Validate and clean tool input against TradeScopeCreate / TaskCreate field constraints.

        Raises ValueError with a descriptive message on invalid input.
        Returns cleaned dict with only validated fields.
        """
        if tool_name == "create_trade_scope":
            return self._validate_create_trade_scope(tool_input)
        if tool_name == "create_task":
            return self._validate_create_task(tool_input)
        if tool_name == "ask_clarifying_question":
            return self._validate_ask_clarifying_question(tool_input)
        raise ValueError(f"Unknown tool: {tool_name}")

    def _validate_create_trade_scope(self, inp: dict[str, Any]) -> dict[str, Any]:
        """Validate create_trade_scope input against TradeScopeCreate constraints."""
        trade_name = inp.get("trade_name")
        if not isinstance(trade_name, str) or not trade_name.strip():
            raise ValueError("create_trade_scope: 'trade_name' must be a non-empty string")

        sort_order = inp.get("sort_order")
        if not isinstance(sort_order, int):
            raise ValueError("create_trade_scope: 'sort_order' must be an integer")

        trade_color = inp.get("trade_color", "#9E9E9E")
        if not isinstance(trade_color, str):
            trade_color = "#9E9E9E"

        return {
            "trade_name": trade_name.strip(),
            "trade_color": trade_color,
            "sort_order": sort_order,
        }

    def _validate_create_task(self, inp: dict[str, Any]) -> dict[str, Any]:
        """Validate create_task input against TaskCreate constraints."""
        title = inp.get("title")
        if not isinstance(title, str) or not title.strip():
            raise ValueError("create_task: 'title' must be a non-empty string")
        if len(title) > 300:
            raise ValueError("create_task: 'title' must be at most 300 characters")

        sort_order = inp.get("sort_order")
        if not isinstance(sort_order, int):
            raise ValueError("create_task: 'sort_order' must be an integer")

        result: dict[str, Any] = {
            "title": title.strip(),
            "sort_order": sort_order,
        }

        description = inp.get("description")
        if description is not None:
            if not isinstance(description, str):
                raise ValueError("create_task: 'description' must be a string")
            result["description"] = description

        priority = inp.get("priority", "medium")
        valid_priorities = {"low", "medium", "high", "urgent"}
        if priority not in valid_priorities:
            raise ValueError(f"create_task: 'priority' must be one of {sorted(valid_priorities)}")
        result["priority"] = priority

        estimated_hours = inp.get("estimated_hours")
        if estimated_hours is not None:
            if not isinstance(estimated_hours, (int, float)):
                raise ValueError("create_task: 'estimated_hours' must be a number")
            if estimated_hours < 0:
                raise ValueError("create_task: 'estimated_hours' must be >= 0")
            result["estimated_hours"] = float(estimated_hours)

        materials_needed = inp.get("materials_needed")
        if materials_needed is not None:
            if not isinstance(materials_needed, list):
                raise ValueError("create_task: 'materials_needed' must be a list")
            cleaned_materials = []
            for i, item in enumerate(materials_needed):
                if not isinstance(item, dict):
                    raise ValueError(f"create_task: 'materials_needed[{i}]' must be an object")
                name = item.get("name")
                if not isinstance(name, str) or not name.strip():
                    raise ValueError(
                        f"create_task: 'materials_needed[{i}].name' must be a non-empty string"
                    )
                cleaned_item: dict[str, Any] = {"name": name.strip()}
                if "quantity" in item:
                    cleaned_item["quantity"] = item["quantity"]
                if "unit" in item:
                    cleaned_item["unit"] = str(item["unit"])
                cleaned_materials.append(cleaned_item)
            result["materials_needed"] = cleaned_materials

        return result

    def _validate_ask_clarifying_question(self, inp: dict[str, Any]) -> dict[str, Any]:
        """Validate ask_clarifying_question input."""
        question = inp.get("question")
        if not isinstance(question, str) or not question.strip():
            raise ValueError("ask_clarifying_question: 'question' must be a non-empty string")
        return {"question": question.strip()}

    # -------------------------------------------------------------------------
    # Image vision support
    # -------------------------------------------------------------------------

    async def build_image_content_block(self, image_ref_id: uuid.UUID) -> dict[str, Any] | None:
        """Look up an uploaded image by ID and return a Claude vision content block.

        Returns None if the image is not found (chat degrades to text-only).
        The file is read from disk and base64-encoded for the Claude API.
        """
        result = await self.db.execute(
            select(AIImageUpload).where(
                AIImageUpload.id == image_ref_id,
                AIImageUpload.deleted_at.is_(None),
            )
        )
        image = result.scalar_one_or_none()
        if image is None:
            return None

        async with aiofiles.open(image.file_path, "rb") as f:
            raw_bytes = await f.read()

        base64_data = base64.b64encode(raw_bytes).decode("utf-8")
        return {
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": image.media_type,
                "data": base64_data,
            },
        }

    # -------------------------------------------------------------------------
    # Conversation lifecycle
    # -------------------------------------------------------------------------

    async def mark_complete(self, conversation_id: uuid.UUID) -> None:
        """Mark a conversation as complete."""
        await self.repository.update(conversation_id, {"status": "complete"})

    async def mark_abandoned(self, conversation_id: uuid.UUID) -> None:
        """Mark a conversation as abandoned."""
        await self.repository.update(conversation_id, {"status": "abandoned"})

    # -------------------------------------------------------------------------
    # Commit flows — persist AI suggestions to the domain
    # -------------------------------------------------------------------------

    async def _require_active_conversation(
        self,
        conversation_id: uuid.UUID,
        *,
        require_scope: bool = False,
    ) -> AIConversation:
        """Load a conversation that must exist and be active; optionally require a scope."""
        conv = await self.repository.get_by_id(conversation_id)
        if conv is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Conversation {conversation_id} not found",
            )
        if conv.status != _CONVERSATION_STATUS_ACTIVE:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Conversation is not active",
            )
        if require_scope and conv.scope_id is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Conversation does not have an associated trade scope",
            )
        return conv

    async def commit_intake(
        self,
        request: IntakeCompleteRequest,
        user_id: uuid.UUID,
    ) -> dict[str, list[str] | str]:
        """Commit AI-suggested trade scopes: create project, scopes, and sequencing edges."""
        await self._require_active_conversation(request.conversation_id)

        project_id = await self._resolve_project_id(request, user_id)
        created_scopes = await self._create_trade_scopes(request.trade_scopes, project_id, user_id)
        anchor_task_ids = await self._seed_scope_tasks(
            created_scopes, request.project_name, request.project_description
        )
        await self._wire_scope_sequencing(anchor_task_ids)

        await self.mark_complete(request.conversation_id)
        return {
            "project_id": str(project_id),
            "trade_scope_ids": [str(scope.id) for scope in created_scopes],
        }

    async def _resolve_project_id(
        self,
        request: IntakeCompleteRequest,
        user_id: uuid.UUID,
    ) -> uuid.UUID:
        """Return the request's project_id, creating a new project when absent."""
        if request.project_id is not None:
            return request.project_id
        project = await ProjectService(self.db).create(
            ProjectCreate(name=request.project_name, description=request.project_description),
            user_id=user_id,
        )
        await self.db.flush()
        return project.id

    async def _create_trade_scopes(
        self,
        trade_scopes: list[dict[str, Any]],
        project_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> list[Any]:
        """Create trade scopes (sorted by sort_order) and return them in creation order."""
        scope_svc = TradeScopeService(self.db)
        created_scopes: list[Any] = []
        for scope_data in sorted(trade_scopes, key=lambda s: s.get("sort_order", 0)):
            scope = await scope_svc.create(
                TradeScopeCreate(
                    project_id=project_id,
                    trade_name=scope_data["trade_name"],
                    trade_color=scope_data.get("trade_color", _DEFAULT_TRADE_COLOR),
                ),
                user_id=user_id,
            )
            await self.db.flush()
            created_scopes.append(scope)
        return created_scopes

    async def _seed_scope_tasks(
        self,
        created_scopes: list[Any],
        project_name: str,
        project_description: str | None,
    ) -> list[uuid.UUID]:
        """Seed each new scope with real, editable starter tasks.

        Uses one Claude call to tailor tasks to the project, with a
        deterministic per-scope fallback so a scope is never left empty.
        Returns the first task id of each scope (in scope order) as the anchor
        for cross-scope dependency sequencing.
        """
        tasks_by_trade = await self._generate_starter_tasks(
            created_scopes, project_name, project_description
        )
        task_svc = TaskService(self.db)
        anchor_task_ids: list[uuid.UUID] = []

        for scope in created_scopes:
            raw_tasks = tasks_by_trade.get(scope.trade_name.strip().lower())
            if not raw_tasks:
                raw_tasks = [self._default_starter_task(scope.trade_name)]

            first_task_id: uuid.UUID | None = None
            for raw_task in raw_tasks:
                created = await task_svc.create(self._build_task_create(scope.id, raw_task))
                await self.db.flush()
                if first_task_id is None:
                    first_task_id = created.id
            if first_task_id is not None:
                anchor_task_ids.append(first_task_id)

        return anchor_task_ids

    async def _generate_starter_tasks(
        self,
        created_scopes: list[Any],
        project_name: str,
        project_description: str | None,
    ) -> dict[str, list[dict[str, Any]]]:
        """Ask Claude for starter tasks per trade → {trade_name_lower: [task, ...]}.

        Never raises: on any AI/parse failure returns an empty mapping so the
        caller substitutes a deterministic default task.
        """
        trade_names = [scope.trade_name for scope in created_scopes]
        user_content = (
            f"Project: {project_name}\n"
            f"Description: {project_description or '(none provided)'}\n\n"
            "Trade scopes:\n"
            + "\n".join(f"- {name}" for name in trade_names)
            + f"\n\nFor each trade scope, produce {_STARTER_TASKS_PER_SCOPE} "
            "sequential starter tasks. Return JSON of the form: "
            '{"scopes": [{"trade_name": "<exact name>", "tasks": '
            '[{"title": "...", "description": "...", '
            '"priority": "low|medium|high", "estimated_hours": <number>}]}]}'
        )
        try:
            data = await call_claude_json(
                _STARTER_TASKS_SYSTEM_PROMPT,
                user_content,
                fallback={"scopes": []},
            )
        except Exception as exc:
            # AI must never block project creation — fall back to defaults.
            logger.warning("Starter-task generation failed; using defaults: %s", exc)
            return {}

        tasks_by_trade: dict[str, list[dict[str, Any]]] = {}
        for entry in data.get("scopes", []):
            if not isinstance(entry, dict):
                continue
            name = entry.get("trade_name")
            tasks = entry.get("tasks")
            if isinstance(name, str) and isinstance(tasks, list):
                tasks_by_trade[name.strip().lower()] = tasks
        return tasks_by_trade

    def _build_task_create(self, scope_id: uuid.UUID, raw_task: dict[str, Any]) -> TaskCreate:
        """Coerce a raw AI task dict into a validated TaskCreate (clamps bad input).

        Ordering is handled by TaskService.create, which auto-assigns sort_order
        by creation order — so tasks are created in the order the AI returned them.
        """
        title = (str(raw_task.get("title") or "").strip() or "Untitled task")[:_MAX_TASK_TITLE_LEN]
        description = raw_task.get("description")
        priority = raw_task.get("priority")
        return TaskCreate(
            trade_scope_id=scope_id,
            title=title,
            description=description if isinstance(description, str) else None,
            priority=priority if priority in _VALID_TASK_PRIORITIES else "medium",
            estimated_hours=self._coerce_hours(raw_task.get("estimated_hours")),
        )

    @staticmethod
    def _coerce_hours(value: Any) -> Decimal | None:
        """Accept only positive numbers as estimated hours; ignore anything else."""
        if isinstance(value, bool):
            return None
        if isinstance(value, (int, float)) and value > 0:
            return Decimal(str(value))
        return None

    @staticmethod
    def _default_starter_task(trade_name: str) -> dict[str, Any]:
        """Deterministic single task so a scope is never empty when AI yields nothing."""
        return {
            "title": f"Plan {trade_name} work",
            "description": (
                f"Review the {trade_name} scope, confirm materials, and schedule the work."
            ),
            "priority": "medium",
        }

    async def _wire_scope_sequencing(self, anchor_task_ids: list[uuid.UUID]) -> None:
        """Link consecutive scopes with FS dependency edges on their first tasks (D-23)."""
        dep_svc = DependencyService(self.db)
        for predecessor_id, successor_id in pairwise(anchor_task_ids):
            await dep_svc.create_dependency(
                successor_id,
                TaskDependencyCreate(predecessor_task_id=predecessor_id),
            )

    async def commit_interview(self, request: InterviewCompleteRequest) -> dict[str, list[str]]:
        """Replace a scope's tasks with the AI-suggested tasks and complete the conversation."""
        conv = await self._require_active_conversation(request.conversation_id, require_scope=True)
        scope_id = conv.scope_id

        await self._soft_delete_scope_tasks(scope_id)
        created_task_ids = await self._create_interview_tasks(scope_id, request.tasks)

        await self.mark_complete(request.conversation_id)
        return {"task_ids": [str(tid) for tid in created_task_ids]}

    async def _soft_delete_scope_tasks(self, scope_id: uuid.UUID) -> None:
        """Soft-delete all live tasks for a scope (D-19 re-interview cleanup)."""
        result = await self.db.execute(
            select(Task).where(Task.trade_scope_id == scope_id, Task.deleted_at.is_(None))
        )
        now = datetime.now(UTC)
        for existing_task in result.scalars().all():
            existing_task.deleted_at = now
        await self.db.flush()

    async def _create_interview_tasks(
        self,
        scope_id: uuid.UUID,
        tasks: list[dict[str, Any]],
    ) -> list[uuid.UUID]:
        """Create tasks from interview data and return their ids in order."""
        task_svc = TaskService(self.db)
        created_task_ids: list[uuid.UUID] = []
        for task_data in tasks:
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
            await self.db.flush()
            created_task_ids.append(task.id)
        return created_task_ids
