"""Turning one candidate into a grounded, publishable finding (FINAI-01, D-05).

The Claude half of the nightly analysis, with no DB and no service attached: a
candidate goes in, a validated `FindingDraft` or None comes out. Nothing here
persists, alerts or commits.

Validate-and-block is the contract. `core.ai_grounding` decides whether a figure
is citable; this module owns the loop AROUND that verdict — the single retry, the
turns the retry is made of, and the drop that follows a second failure. A draft
that still cites an unmatched figure is dropped whole: never published, never
clipped to fit, never partially saved.

Feature-agnostic on purpose, like the validator it wraps: it imports the payload's
`ProfitabilityCandidate` but no repository, no alerting and no scheduler, so a
second grounded-AI feature reuses the retry envelope instead of restating it.

Decision IDs (D-nn), success criteria (SCn) and requirement tags (FINAI-nn) used
below resolve in .planning/phases/36-ai-profitability-analysis/36-CONTEXT.md.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from decimal import Decimal

from app.core.ai_grounding import collect_allowed_values, validate_grounding
from app.core.ai_utils import ClaudeJsonResponse, call_claude_json_strict
from app.core.logging_config import get_logger
from app.features.finance.profitability_models import (
    MAX_ALERT_SUMMARY_LENGTH,
    MAX_CORRECTIVE_ACTION_LENGTH,
    MAX_NARRATIVE_LENGTH,
)
from app.features.finance.profitability_payload import ProfitabilityCandidate, payload_turn
from app.features.finance.prompts.profitability_system import (
    GROUNDING_RETRY_TEMPLATE,
    PROFITABILITY_SYSTEM_PROMPT,
)

logger = get_logger(__name__)

# Rendered at the call site for the reason given in profitability_service: this app
# binds structlog to the stdlib bridge, so %-args never reach capture_logs.
TOKEN_USAGE_LOG_TEMPLATE = "ai_profitability: tokens project=%s input=%s output=%s"
DISMISSAL_LOG_TEMPLATE = "ai_profitability: dismissed project=%s reason=%s"
EMPTY_DRAFT_LOG_TEMPLATE = "ai_profitability: dropped textless finding project=%s"
UNGROUNDED_DROP_LOG_TEMPLATE = "ai_profitability: dropped ungrounded finding project=%s figures=%s"

GROUNDING_RETRY_LIMIT = 1
"""D-05: one VALIDATION retry, and only one.

There is no transport retry on this path — the exponential-backoff envelope is
streaming-only (ai/service.py), so a transient API error surfaces as a raised
candidate that gather_with_concurrency isolates.
"""

PROFITABILITY_MAX_OUTPUT_TOKENS = 1024
"""D-10 per-project ceiling. max_tokens caps OUTPUT only; the input side is bounded
by the aggregates-only payload rule, not by this number."""


@dataclass(frozen=True)
class FindingDraft:
    """A validated, publishable finding before it touches the database."""

    narrative: str
    corrective_action: str
    alert_summary: str


async def draft_for(candidate: ProfitabilityCandidate) -> FindingDraft | None:
    """One candidate's grounded finding, or None when it is dismissed or ungrounded.

    Validate-and-block with exactly one retry (D-05). A finding still citing a
    figure the payload does not contain on the second attempt is DROPPED and
    logged: never published, never clipped to fit, never partially saved.
    """
    allowed = collect_allowed_values(candidate.payload)
    messages = [payload_turn(candidate.payload)]
    ungrounded: tuple[str, ...] = ()
    for _attempt in range(GROUNDING_RETRY_LIMIT + 1):
        response = await call_claude_json_strict(
            PROFITABILITY_SYSTEM_PROMPT, messages, max_tokens=PROFITABILITY_MAX_OUTPUT_TOKENS
        )
        _log_token_usage(candidate, response)
        if not response.data.get("confirmed"):
            _log_dismissal(candidate, response.data)
            return None
        draft = _to_draft(response.data)
        if draft is None:
            logger.warning(EMPTY_DRAFT_LOG_TEMPLATE % (candidate.project_id,))
            return None
        ungrounded = _ungrounded_literals(draft, allowed)
        if not ungrounded:
            return draft
        messages = [*messages, *_retry_turns(response.raw_text, ungrounded)]
    logger.warning(UNGROUNDED_DROP_LOG_TEMPLATE % (candidate.project_id, ", ".join(ungrounded)))
    return None


def within_length_contract(draft: FindingDraft) -> bool:
    """The D-09/UI-SPEC bounds, checked against the same constants the DB enforces.

    Over-length text is rejected whole rather than shortened to fit: clipping a
    grounded sentence can drop the very figure that justifies it.
    """
    return (
        len(draft.narrative) <= MAX_NARRATIVE_LENGTH
        and len(draft.corrective_action) <= MAX_CORRECTIVE_ACTION_LENGTH
        and len(draft.alert_summary) <= MAX_ALERT_SUMMARY_LENGTH
    )


def _retry_turns(raw_text: str, ungrounded: tuple[str, ...]) -> list[dict[str, str]]:
    """The two turns that continue the conversation into its one retry: the model's
    own reply, then the literals it is not allowed to use."""
    return [
        {"role": "assistant", "content": raw_text},
        {
            "role": "user",
            "content": GROUNDING_RETRY_TEMPLATE.format(unmatched=", ".join(ungrounded)),
        },
    ]


def _to_draft(data: Mapping[str, object]) -> FindingDraft | None:
    """The three AI strings, or None when the model confirmed a finding without writing one.

    The prompt reserves empty strings for a dismissal, so a confirmed reply with
    empty text is malformed — publishing it would ship a blank card and a blank alert.
    """
    draft = FindingDraft(
        narrative=_ai_string(data, "narrative"),
        corrective_action=_ai_string(data, "corrective_action"),
        alert_summary=_ai_string(data, "alert_summary"),
    )
    if not (draft.narrative and draft.corrective_action and draft.alert_summary):
        return None
    return draft


def _ai_string(data: Mapping[str, object], field: str) -> str:
    """One AI text field, read defensively so a null can never reach a NOT NULL column."""
    value = data.get(field)
    return value if isinstance(value, str) else ""


def _ungrounded_literals(draft: FindingDraft, allowed: frozenset[Decimal]) -> tuple[str, ...]:
    """Every figure the draft cites that the payload does not contain, across ALL
    three AI strings — validating only the narrative would let a fabricated figure
    reach the dashboard alert and the push body.

    Deduplicated in first-seen order so the retry turn names each literal once.
    """
    verdicts = (
        validate_grounding(text, allowed)
        for text in (draft.narrative, draft.corrective_action, draft.alert_summary)
    )
    return tuple(dict.fromkeys(literal for verdict in verdicts for literal in verdict.unmatched))


def _log_token_usage(candidate: ProfitabilityCandidate, response: ClaudeJsonResponse) -> None:
    """The run log's cost line — one per Claude turn, the D-05 retry included."""
    logger.info(
        TOKEN_USAGE_LOG_TEMPLATE
        % (candidate.project_id, response.input_tokens, response.output_tokens)
    )


def _log_dismissal(candidate: ProfitabilityCandidate, data: Mapping[str, object]) -> None:
    """An AI dismissal is a normal outcome (D-02), so it is logged with its reason."""
    logger.info(DISMISSAL_LOG_TEMPLATE % (candidate.project_id, data.get("dismissal_reason")))
