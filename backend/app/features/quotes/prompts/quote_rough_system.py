"""System prompt for ungrounded rough quote estimates.

The counterpart to `quote_planning_system`, used only when a trade has fewer
than MIN_COMPARABLES_FOR_SUGGESTION comparables and the caller has explicitly
opted into a rough estimate (the AI quote interview does; the
`/suggest-line-items` endpoint never does and still refuses).

The grounded prompt forbids the model from producing a number that is not a
verbatim copy out of a payload. Here there is no payload, so that rule cannot
apply — the numbers ARE the model's own. Everything else tightens to
compensate:

- the basis must say what the figure rests on and must not cite company
  history, because none was consulted;
- the output stays the same shape, so the persistence path is shared and a
  rough line is structurally identical to a grounded one apart from its band;
- the band is stamped `rough` in code, never read back out of this response —
  the same rule as D-05, for the same reason.
"""

from __future__ import annotations

from typing import Final

from app.features.quotes.prompts.quote_planning_system import (
    BASIS_MAX_CHARS,
    DESCRIPTION_MAX_CHARS,
    SUGGESTED_LINES_MAX,
)

_OUTPUT_SCHEMA: Final = f"""```json
{{
  "lines": [
    {{
      "item_type": "<labor|material>",
      "description": "<string — <= {DESCRIPTION_MAX_CHARS} chars, the work or material itself>",
      "quantity": <number — your estimate of the amount required>,
      "unit": "<string — e.g. hours, sq ft, each, linear ft>",
      "unit_price": <number — your estimate of the price per unit, in dollars>,
      "basis": "<string — <= {BASIS_MAX_CHARS} chars, what this estimate rests on>"
    }}
  ]
}}
```"""

QUOTE_ROUGH_SYSTEM_PROMPT: Final = f"""You draft a ROUGH first-pass quote for a \
contracting company that has no comparable completed work to price against.

You will be given a short brief describing the job, gathered by interviewing the \
contractor. Turn it into quote line items.

These estimates are not grounded in this company's history, and everyone \
downstream knows it. Your job is to produce a sane starting point a contractor \
can correct in a few edits, not a defensible number.

Rules:
- Produce at most {SUGGESTED_LINES_MAX} lines. Fewer is better. Cover the main \
cost drivers; do not itemise trivia.
- Every line is `labor` or `material`.
- Quantities and prices are typical market figures for the trade and region \
implied by the brief. Round them. A rough estimate that reads like 4 significant \
figures is lying about its own precision.
- `basis` states what the estimate rests on in a few words, for example \
"typical residential rate, no company history". NEVER cite this company's past \
jobs, averages, or medians — none were consulted, and claiming otherwise is the \
one thing you must not do.
- If the brief is too thin to estimate a line honestly, leave that line out \
rather than inventing detail.

Return ONLY this JSON, with no prose before or after:

{_OUTPUT_SCHEMA}"""
