"""System prompt for AI quote line-item suggestions (FINAI-03/04, D-09).

Half of the grounding contract quote planning inherits from Phase 36's
profitability prompt: it mandates the "$" and "%" sigils the extractor keys
on, forbids the model from computing anything, and confines every quantity to
the structured field a validator can check by exact membership. That is what
keeps validation pure set membership rather than parsing an arithmetic claim
out of free text.

The two length bounds below are imported from their real owners — the
`quote_line_items` basis CHECK constraint and the QuoteLineItemCreate
description field — so this prompt can never advertise a looser bound than
the database enforces (the 36-08 finding, true here for the same reason).
"""

from __future__ import annotations

from typing import Final

from app.features.quotes.models import MAX_BASIS_LENGTH
from app.features.quotes.schemas import QuoteLineItemCreate

BASIS_MAX_CHARS: Final = MAX_BASIS_LENGTH


def _max_length(model: type, field_name: str) -> int:
    """One field's Field(max_length=...) constraint, read off the model rather
    than retyped — the only way this module's bound can never drift from the
    schema it must never advertise looser than."""
    for constraint in model.model_fields[field_name].metadata:
        candidate = getattr(constraint, "max_length", None)
        if candidate is not None:
            return candidate
    raise ValueError(f"{field_name} carries no max_length constraint")


DESCRIPTION_MAX_CHARS: Final = _max_length(QuoteLineItemCreate, "description")
SUGGESTED_LINES_MAX: Final = 12

# The keys a suggested line carries — exactly what QuoteSuggestionService reads
# and no others. Named once here so the output schema below and any caller
# checking the contract share one source of truth.
SUGGESTED_LINE_FIELDS: Final[tuple[str, ...]] = (
    "item_type",
    "description",
    "quantity",
    "unit",
    "unit_price",
    "basis",
)

_OUTPUT_SCHEMA = f"""```json
{{
  "lines": [
    {{
      "item_type": "<labor|material>",
      "description": "<string — <= {DESCRIPTION_MAX_CHARS} chars, the work or material itself>",
      "quantity": <number — copied verbatim from a payload rate row's typical_quantity>,
      "unit": "<string — copied verbatim from the same rate row's unit>",
      "unit_price": <number — copied verbatim from the same rate row's median_quoted_unit_price>,
      "basis": "<string — <= {BASIS_MAX_CHARS} chars, one sentence citing only payload figures>"
    }}
  ]
}}
```"""

QUOTE_PLANNING_SYSTEM_PROMPT = f"""You are ContractorHub AI, a construction estimator.

A trade has enough comparable history for a price-backed suggestion. Build labor and \
material line items for the draft quote below, priced from the payload's own rate rows \
— never from a number you compute yourself.

## 1. Output Schema

Return ONLY valid JSON matching the schema below — no markdown fences, no explanation, \
no prose before or after. Suggest at most {SUGGESTED_LINES_MAX} lines, one per rate row \
worth quoting.

{_OUTPUT_SCHEMA}

description is hard-bounded at {DESCRIPTION_MAX_CHARS} characters and basis at \
{BASIS_MAX_CHARS} characters. Over-length text is rejected, never shortened to fit.

## 2. Selection Rule

Select unit_price and quantity from the payload's rate_rows — copy them verbatim. Do \
not compute, average, adjust or interpolate any figure; a number you did not copy from \
a rate row is a fabricated price.

## 3. Figure Rules

Write every dollar figure your basis sentence cites with a leading "$" ($3,200, \
$3,200.41) and every percentage with a trailing "%" (6.2%). Cite ONLY figures that \
appear in the payload JSON — never add, subtract, sum or round to produce a new one.

Write the quantity ONLY in the structured quantity field, never inside the basis \
sentence — a quantity written in prose cannot be validated the way a structured field \
can.

## 4. Basis Shape

basis is the interpretive half of one sentence explaining why this rate applies; the \
server prepends the sample-count clause itself, so never restate how many comparables \
were used. If the rate reflects labor, use the payload's labor_basis wording \
("unburdened") rather than inventing your own label for it.

## 5. Data Honesty

labor_basis is "unburdened": wage cost only, excluding payroll tax, insurance and \
overhead. Never describe an unburdened figure as fully-loaded or all-in.

Return ONLY the JSON object. No other text."""

GROUNDING_RETRY_TEMPLATE = (
    "These fields or figures are not grounded in the payload and must not be used: "
    "{unmatched}. Rewrite every suggested line using ONLY unit prices and quantities "
    "copied verbatim from the payload's rate rows, and basis figures already present "
    "in the payload JSON above. Return the same JSON schema."
)

SERVER_BASIS_PREFIX_TEMPLATE = "median of %s comparable %s scopes — "
"""The sample-count clause the SERVER composes and prepends to the model's own
interpretive sentence — the count is code-composed so the model never has to
write, and can never fabricate, the sample size itself."""
