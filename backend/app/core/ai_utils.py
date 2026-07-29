"""Shared AI/Claude API utilities used by checklist and dashboard services.

Centralizes:
- Claude model/token constants
- Anthropic client lazy singleton
- JSON fence stripping for AI responses
- Done-status constants for task filtering
- call_claude_json: shared pattern for Claude API calls with JSON parsing
- call_claude_json_strict: the fail-closed sibling for grounded AI findings
- gather_with_concurrency: bounded-concurrency asyncio.gather wrapper
"""

from __future__ import annotations

import asyncio
import json
import re
from collections.abc import Callable, Coroutine, Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from anthropic import AsyncAnthropic

from app.core.config import settings
from app.core.logging_config import get_logger

logger = get_logger(__name__)

# Claude API constants
CLAUDE_MODEL = "claude-sonnet-4-6"
CLAUDE_MAX_TOKENS = 2048
CLAUDE_TIMEOUT = 30.0

# Maximum concurrent AI calls (used by gather_with_concurrency)
AI_CONCURRENCY_LIMIT = 5

# Task statuses that mean "done" — skip when building checklists / detecting slips
DONE_STATUSES = frozenset({"complete", "cancelled"})

# Project status filters shared by checklist and dashboard services
ACTIVE_PROJECT_STATUSES = ("planning", "active")
DASHBOARD_PROJECT_STATUSES = ("planning", "active", "on_hold")

# Strip markdown code fences if Claude wraps JSON despite instructions
_JSON_FENCE_PATTERN = re.compile(r"```(?:json)?\s*(.*?)```", re.DOTALL)

# Lazy singleton for the Anthropic client
_anthropic_client: AsyncAnthropic | None = None


def get_anthropic_client() -> AsyncAnthropic:
    """Return a lazily-initialized AsyncAnthropic client (singleton).

    The key is read from settings (.env is the single source of truth); when
    unset, api_key=None lets the SDK fall back to the ANTHROPIC_API_KEY
    environment variable. Deferred creation avoids import-time side effects and
    test failures when the API key is not set.
    """
    global _anthropic_client
    if _anthropic_client is None:
        _anthropic_client = AsyncAnthropic(
            api_key=settings.anthropic_api_key, timeout=CLAUDE_TIMEOUT
        )
    return _anthropic_client


def strip_fences(text: str) -> str:
    """Remove markdown code fences from AI response text if present."""
    match = _JSON_FENCE_PATTERN.search(text)
    if match:
        return match.group(1).strip()
    return text.strip()


async def call_claude_json(
    system_prompt: str,
    user_content: str,
    fallback: dict[str, Any],
    scope_id: Any | None = None,
) -> dict[str, Any]:
    """Call Claude API and parse the response as JSON.

    Shared pattern used by checklist generation and schedule slip detection.
    On empty response, raises ValueError. On invalid JSON, logs a warning
    and returns the provided fallback dict.
    """
    client = get_anthropic_client()
    response = await client.messages.create(
        model=CLAUDE_MODEL,
        max_tokens=CLAUDE_MAX_TOKENS,
        system=system_prompt,
        messages=[{"role": "user", "content": user_content}],
    )

    if not response.content:
        raise ValueError(f"Empty response from Claude for scope {scope_id}")

    raw_text = response.content[0].text
    cleaned = strip_fences(raw_text)

    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        logger.warning(
            "call_claude_json: invalid JSON for scope %s — using fallback. Raw: %s...",
            scope_id,
            cleaned[:200],
        )
        return fallback


@dataclass(frozen=True)
class ClaudeJsonResponse:
    """A strictly-parsed Claude JSON turn, plus the raw text the retry turn needs."""

    data: dict[str, Any]
    raw_text: str
    input_tokens: int | None
    output_tokens: int | None


async def call_claude_json_strict(
    system_prompt: str,
    messages: Sequence[Mapping[str, str]],
    max_tokens: int = CLAUDE_MAX_TOKENS,
) -> ClaudeJsonResponse:
    """Call Claude and parse the reply as JSON, raising on anything unparseable.

    The strict sibling of call_claude_json. That function degrades to a
    caller-supplied default dict on bad JSON, which is a harmless degradation for a
    checklist and a silent-fabrication path for a grounded finding (SC3). Findings
    fail closed.

    There is NO transport retry on this path — the exponential-backoff envelope is
    streaming-only (ai/service.py). Callers that want resilience add it deliberately;
    the D-05 grounding retry is a VALIDATION retry and is a different thing entirely.
    """
    client = get_anthropic_client()
    response = await client.messages.create(
        model=CLAUDE_MODEL,
        max_tokens=max_tokens,
        system=system_prompt,
        messages=list(messages),
    )

    if not response.content:
        raise ValueError("Empty response from Claude")

    raw_text = strip_fences(response.content[0].text)
    input_tokens, output_tokens = _token_counts(response)
    return ClaudeJsonResponse(
        data=json.loads(raw_text),
        raw_text=raw_text,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
    )


def _token_counts(response: Any) -> tuple[int | None, int | None]:
    """Read the usage block defensively — a response without one must never fail a run."""
    usage = getattr(response, "usage", None)
    if usage is None:
        return None, None
    return getattr(usage, "input_tokens", None), getattr(usage, "output_tokens", None)


async def gather_with_concurrency[T](
    items: list[T],
    process_fn: Callable[[T], Coroutine[Any, Any, Any]],
    max_concurrent: int = AI_CONCURRENCY_LIMIT,
) -> list[Any]:
    """Run process_fn over items with bounded concurrency via asyncio.Semaphore.

    Each call is wrapped in try/except — failures return None and are logged.
    Returns a list of results (same length as items, with None for failures).
    """
    semaphore = asyncio.Semaphore(max_concurrent)

    async def _wrapped(item: T) -> Any:
        async with semaphore:
            try:
                return await process_fn(item)
            except Exception:
                logger.exception("gather_with_concurrency: task failed — returning None")
                return None

    return await asyncio.gather(*[_wrapped(item) for item in items])
