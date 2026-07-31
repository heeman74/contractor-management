"""QuoteSuggestionService — candidate -> payload -> validate -> persist for
quote line suggestions (FINAI-03, FINAI-04, D-09).

Transferred from ProfitabilityService's grounded Claude pattern
(profitability_drafting.draft_for), with two differences: validation runs
over BOTH the structured fields (unit_price, quantity) AND the basis text,
and a failure in either drops the WHOLE suggested set rather than part of it
— a half-validated quote is not a quote.

A trade with fewer than MIN_COMPARABLES_FOR_SUGGESTION comparables never
reaches the Claude client: the cold-start gate returns before the payload is
even built (D-09). A raised transport error consumes no grounding retry — the
exception escapes the strict Claude JSON entry point before this module's
loop can iterate, the same shape 36-09 found true for the nightly finding
path.

Regenerating a suggestion never goes near the id-keyed line-item PATCH path —
that path matches a client-supplied list by id, and a server-generated
regeneration is not that. It instead deletes only the rows still carrying
server-owned AI provenance and an unreviewed state, and leaves every accepted
or edited row — including its id — untouched.
"""

from __future__ import annotations

import json
import uuid
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal

from fastapi import HTTPException, status

from app.core import ai_utils
from app.core.ai_grounding import validate_typed_grounding
from app.core.base_service import TenantScopedService, entity_or_404
from app.core.logging_config import get_logger
from app.features.projects.models import TradeScope
from app.features.quotes.models import (
    MAX_BASIS_LENGTH,
    REVIEW_STATE_UNREVIEWED,
    Quote,
    QuoteLineItem,
)
from app.features.quotes.prompts.quote_planning_system import (
    DESCRIPTION_MAX_CHARS,
    GROUNDING_RETRY_TEMPLATE,
    QUOTE_PLANNING_SYSTEM_PROMPT,
    SERVER_BASIS_PREFIX_TEMPLATE,
    SUGGESTED_LINES_MAX,
)
from app.features.quotes.quote_history_math import (
    MIN_COMPARABLES_FOR_SUGGESTION,
    ComparableSummary,
    summarize_comparables,
)
from app.features.quotes.repository import QuoteRepository
from app.features.quotes.schemas import (
    REFUSAL_INSUFFICIENT_HISTORY,
    REFUSAL_TRADE_UNRESOLVED,
    REFUSAL_UNGROUNDED,
)
from app.features.quotes.suggestion_payload import (
    SuggestionPayload,
    build_suggestion_payload,
    jsonb_payload,
    ungrounded_line_fields,
)
from app.features.quotes.suggestion_repository import QuoteComparableRepository

logger = get_logger(__name__)

GROUNDING_RETRY_LIMIT = 1
"""One VALIDATION retry — the same D-05 shape profitability_drafting uses."""

SUGGESTION_MAX_OUTPUT_TOKENS = 2048

_LINE_ITEM_TYPES = frozenset({"labor", "material"})

DROPPED_SUGGESTION_LOG_TEMPLATE = (
    "quote_suggestion: dropped ungrounded suggestion quote=%s offenders=%s"
)


@dataclass(frozen=True)
class SuggestionOutcome:
    """The five locked wire fields (37-UI-SPEC "Response contracts")."""

    refusal_reason: str | None
    trade_name: str | None
    comparable_count: int | None
    required_count: int | None
    suggested_line_count: int


class QuoteSuggestionService(TenantScopedService[Quote]):
    """Grounded line-item suggestions for one draft quote (FINAI-03, FINAI-04).

    candidate -> payload -> validate -> persist, transferred from
    ProfitabilityService. Two differences: validation runs over BOTH the
    structured fields and the basis text, and any failure in either drops the
    whole set rather than part of it — a half-validated quote is not a quote.
    """

    repository_class = QuoteRepository
    repository: QuoteRepository

    async def suggest(self, quote_id: uuid.UUID) -> SuggestionOutcome:
        quote = await self._get_quote_or_404(quote_id)
        self._require_draft(quote)

        trade = await self._resolve_trade(quote)
        if trade is None:
            return _refusal(REFUSAL_TRADE_UNRESOLVED)

        rows = await QuoteComparableRepository(self.db).comparables_for_trade(trade)
        summary = summarize_comparables(trade, rows.anchors, rows.lines)

        if summary.comparable_count < MIN_COMPARABLES_FOR_SUGGESTION:
            return _refusal(
                REFUSAL_INSUFFICIENT_HISTORY,
                trade_name=trade,
                comparable_count=summary.comparable_count,
                required_count=MIN_COMPARABLES_FOR_SUGGESTION,
            )

        payload = build_suggestion_payload(summary)
        lines = await self._draft_lines(quote_id, payload, summary)
        if lines is None:
            return _refusal(
                REFUSAL_UNGROUNDED,
                trade_name=trade,
                comparable_count=summary.comparable_count,
                required_count=MIN_COMPARABLES_FOR_SUGGESTION,
            )

        await self._persist(quote, lines, summary, payload)
        return SuggestionOutcome(
            refusal_reason=None,
            trade_name=trade,
            comparable_count=summary.comparable_count,
            required_count=MIN_COMPARABLES_FOR_SUGGESTION,
            suggested_line_count=len(lines),
        )

    async def _get_quote_or_404(self, quote_id: uuid.UUID) -> Quote:
        return entity_or_404(await self.repository.get_with_line_items(quote_id), "Quote not found")

    @staticmethod
    def _require_draft(quote: Quote) -> None:
        """The shipped 409 idiom: suggesting is refused on any quote that is
        not a draft."""
        if quote.status != "draft":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"Cannot suggest quote in status '{quote.status}'. Allowed statuses: ['draft']"
                ),
            )

    async def _resolve_trade(self, quote: Quote) -> str | None:
        """The Trap 3 ladder: scope name, then job trade, then a project-level
        line's own field. None means unresolvable — the caller returns
        trade_unresolved before a comparable is ever fetched."""
        if quote.trade_scope_id is not None:
            trade_scope = await self.db.get(TradeScope, quote.trade_scope_id)
            return trade_scope.trade_name if trade_scope is not None else None
        if quote.job_id is not None:
            return quote.job.trade_type if quote.job is not None else None
        return self._project_level_trade(quote)

    @staticmethod
    def _project_level_trade(quote: Quote) -> str | None:
        """The first non-empty line field on a project-level quote, in sort
        order, or None when every line's field is empty."""
        for item in sorted(quote.line_items, key=lambda line: line.sort_order):
            field = (item.field or "").strip()
            if field:
                return field
        return None

    async def _draft_lines(
        self, quote_id: uuid.UUID, payload: SuggestionPayload, summary: ComparableSummary
    ) -> list[dict[str, object]] | None:
        """The D-05-style retry loop: validate every line's structured fields
        and basis text, retry once naming every offender, then drop the whole
        set on a second failure.

        Nothing here reads a self-reported count or verdict back out of the
        model's own JSON — the persisted band always comes from
        quote_history_math, never from this response.
        """
        messages: list[dict[str, str]] = [_payload_turn(payload.payload)]
        offenders: tuple[str, ...] = ()
        for _attempt in range(GROUNDING_RETRY_LIMIT + 1):
            response = await ai_utils.call_claude_json_strict(
                QUOTE_PLANNING_SYSTEM_PROMPT, messages, max_tokens=SUGGESTION_MAX_OUTPUT_TOKENS
            )
            lines = response.data.get("lines")
            if not isinstance(lines, list) or not lines or len(lines) > SUGGESTED_LINES_MAX:
                offenders = ("lines",)
            else:
                offenders = _every_line_offender(lines, payload, summary)
            if not offenders:
                return lines
            messages = [
                *messages,
                {"role": "assistant", "content": response.raw_text},
                {
                    "role": "user",
                    "content": GROUNDING_RETRY_TEMPLATE.format(unmatched=", ".join(offenders)),
                },
            ]
        logger.warning(DROPPED_SUGGESTION_LOG_TEMPLATE % (quote_id, ", ".join(offenders)))
        return None

    async def _persist(
        self,
        quote: Quote,
        lines: list[dict[str, object]],
        summary: ComparableSummary,
        payload: SuggestionPayload,
    ) -> None:
        """Delete only the rows still carrying server-owned AI provenance and
        an unreviewed state, insert the freshly validated set, and store the
        payload it was validated against for the audit trail.
        """
        kept: list[QuoteLineItem] = []
        for item in quote.line_items:
            if item.ai_origin and item.review_state == REVIEW_STATE_UNREVIEWED:
                await self.db.delete(item)
            else:
                kept.append(item)
        next_sort_order = max((item.sort_order for item in kept), default=-1) + 1

        project_level_field = self._project_level_field(quote, summary.trade)
        suggested_at = datetime.now(UTC)
        for offset, line in enumerate(lines):
            self.db.add(
                QuoteLineItem(
                    quote_id=quote.id,
                    company_id=quote.company_id,
                    item_type=line["item_type"],
                    description=line["description"],
                    quantity=Decimal(str(line["quantity"])),
                    unit=line["unit"],
                    unit_price=Decimal(str(line["unit_price"])),
                    sort_order=next_sort_order + offset,
                    field=project_level_field,
                    ai_origin=True,
                    review_state=REVIEW_STATE_UNREVIEWED,
                    confidence_band=summary.confidence_band,
                    basis=_composed_basis(str(line["basis"]), summary),
                    suggested_at=suggested_at,
                )
            )
        quote.ai_suggestion_payload = jsonb_payload(payload.payload)
        await self.db.flush()
        self.db.expire(quote, ["line_items"])

    @staticmethod
    def _project_level_field(quote: Quote, trade: str) -> str | None:
        """A project-level quote tags its new lines with the resolved trade so
        the per-field job grouping an approval creates still finds them; a
        job- or scope-anchored quote needs no per-line field."""
        if quote.job_id is None and quote.trade_scope_id is None:
            return trade
        return None


def _refusal(
    reason: str,
    *,
    trade_name: str | None = None,
    comparable_count: int | None = None,
    required_count: int | None = None,
) -> SuggestionOutcome:
    """One named refusal, zero lines persisted."""
    return SuggestionOutcome(
        refusal_reason=reason,
        trade_name=trade_name,
        comparable_count=comparable_count,
        required_count=required_count,
        suggested_line_count=0,
    )


def _payload_turn(payload: Mapping[str, object]) -> dict[str, str]:
    """The comparable payload as the opening user turn, Decimals rendered as
    exact strings for the model to read."""
    return {"role": "user", "content": json.dumps(payload, default=str)}


def _composed_basis(model_basis: str, summary: ComparableSummary) -> str:
    """The sample-count clause the SERVER composes, prefixed onto the model's
    own interpretive sentence."""
    return SERVER_BASIS_PREFIX_TEMPLATE % (summary.comparable_count, summary.trade) + model_basis


def _every_line_offender(
    lines: list[object], payload: SuggestionPayload, summary: ComparableSummary
) -> tuple[str, ...]:
    """Every offending field or figure across every suggested line, deduplicated
    in first-seen order — one bad line anywhere drops the whole set."""
    offenders: list[str] = []
    for line in lines:
        offenders.extend(_line_offenders(line, payload, summary))
    return tuple(dict.fromkeys(offenders))


def _line_offenders(
    line: object, payload: SuggestionPayload, summary: ComparableSummary
) -> tuple[str, ...]:
    if not isinstance(line, Mapping):
        return ("line",)
    offenders = list(ungrounded_line_fields(line, payload.allowed_lines))
    if line.get("item_type") not in _LINE_ITEM_TYPES:
        offenders.append("item_type")
    description = line.get("description")
    if (
        not isinstance(description, str)
        or not description
        or len(description) > DESCRIPTION_MAX_CHARS
    ):
        offenders.append("description")
    offenders.extend(_basis_offenders(line.get("basis"), payload, summary))
    return tuple(offenders)


def _basis_offenders(
    model_basis: object, payload: SuggestionPayload, summary: ComparableSummary
) -> tuple[str, ...]:
    """The basis text's own offenders: missing, over-length once composed with
    the server's prefix, or citing a figure the payload does not contain.

    Over-length text is rejected whole here — never shortened to fit.
    """
    if not isinstance(model_basis, str) or not model_basis:
        return ("basis",)
    if len(_composed_basis(model_basis, summary)) > MAX_BASIS_LENGTH:
        return ("basis_length",)
    return validate_typed_grounding(model_basis, payload.allowed_figures).unmatched
