"""Shared AI/Claude API utilities used by checklist and dashboard services.

Centralizes:
- Claude model/token constants
- Anthropic client lazy singleton
- JSON fence stripping for AI responses
- Done-status constants for task filtering
"""

from __future__ import annotations

import re

from anthropic import AsyncAnthropic

# Claude API constants
CLAUDE_MODEL = "claude-sonnet-4-6"
CLAUDE_MAX_TOKENS = 2048
CLAUDE_TIMEOUT = 30.0

# Task statuses that mean "done" — skip when building checklists / detecting slips
DONE_STATUSES = frozenset({"complete", "cancelled"})

# Strip markdown code fences if Claude wraps JSON despite instructions
_JSON_FENCE_PATTERN = re.compile(r"```(?:json)?\s*(.*?)```", re.DOTALL)

# Lazy singleton for the Anthropic client
_anthropic_client: AsyncAnthropic | None = None


def get_anthropic_client() -> AsyncAnthropic:
    """Return a lazily-initialized AsyncAnthropic client (singleton).

    The client reads ANTHROPIC_API_KEY from the environment on first call.
    Deferred creation avoids import-time side effects and test failures
    when the API key is not set.
    """
    global _anthropic_client
    if _anthropic_client is None:
        _anthropic_client = AsyncAnthropic(timeout=CLAUDE_TIMEOUT)
    return _anthropic_client


def strip_fences(text: str) -> str:
    """Remove markdown code fences from AI response text if present."""
    match = _JSON_FENCE_PATTERN.search(text)
    if match:
        return match.group(1).strip()
    return text.strip()
