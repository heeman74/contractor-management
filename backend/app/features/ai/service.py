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
import json
import logging
import uuid
from collections.abc import AsyncGenerator
from typing import Any

from anthropic import APIError, APITimeoutError, AsyncAnthropic, RateLimitError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_service import TenantScopedService
from app.features.ai.models import AIConversation, AIMessage, AITokenUsage
from app.features.ai.prompts.intake_system import INTAKE_SYSTEM_PROMPT
from app.features.ai.prompts.interview_system import INTERVIEW_SYSTEM_PROMPT
from app.features.ai.repository import (
    AIConversationRepository,
    AIMessageRepository,
    AITokenUsageRepository,
)

logger = logging.getLogger(__name__)

# Module-level Anthropic client — reads ANTHROPIC_API_KEY from environment
_anthropic_client = AsyncAnthropic()

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
        messages = [
            {"role": msg.role, "content": msg.content_json} for msg in db_messages
        ]

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
            async for event_str in self._call_with_retry(conversation, messages, system_prompt, tools):
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

    async def validate_tool_input(self, tool_name: str, tool_input: dict[str, Any]) -> dict[str, Any]:
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
            raise ValueError(
                f"create_task: 'priority' must be one of {sorted(valid_priorities)}"
            )
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
    # Conversation lifecycle
    # -------------------------------------------------------------------------

    async def mark_complete(self, conversation_id: uuid.UUID) -> None:
        """Mark a conversation as complete."""
        await self.repository.update(conversation_id, {"status": "complete"})

    async def mark_abandoned(self, conversation_id: uuid.UUID) -> None:
        """Mark a conversation as abandoned."""
        await self.repository.update(conversation_id, {"status": "abandoned"})
