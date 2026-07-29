---
phase: 36-ai-profitability-analysis
plan: 05
subsystem: ai
tags: [claude, grounding, decimal, prompts, anthropic, sc3]

requires:
  - phase: 36-01
    provides: ai_profitability alert type, finding persistence and claim_alert
  - phase: 36-03
    provides: profitability_math candidate signals whose precomputed deltas become the closed payload set
provides:
  - "app/core/ai_grounding.py — payload-shape-agnostic D-05 grounding validator (extraction, closed allowed set, set-membership matching)"
  - "call_claude_json_strict + ClaudeJsonResponse — a Claude JSON call that fails closed instead of degrading to a caller dict"
  - "PROFITABILITY_SYSTEM_PROMPT + GROUNDING_RETRY_TEMPLATE — the D-09 prompt contract and the validation-retry turn"
affects: [36-06, 36-07, 36-08, 37-ai-quote-planning]

tech-stack:
  added: []
  patterns:
    - "Closed allowed-value set: payloads carry every citable figure as a named Decimal field, so grounding is pure set membership"
    - "Strict-sibling pattern for AI plumbing: a fail-closed call beside the shipped degrade-on-bad-JSON call, neither touching the other"
    - "Prompt length constants interpolated into the prompt text so prompt copy and DB CHECKs cannot diverge"

key-files:
  created:
    - backend/app/core/ai_grounding.py
    - backend/tests/unit/test_ai_grounding.py
    - backend/app/features/finance/prompts/__init__.py
    - backend/app/features/finance/prompts/profitability_system.py
  modified:
    - backend/app/core/ai_utils.py

key-decisions:
  - "MONEY_PATTERN's comma-grouped alternative requires at least one group (+, not the plan's *) — with * it matches \"$320\" inside \"$3200\" and the plan's own behavior list demands \"$3200\" extract as 3200"
  - "The whole-dollar tolerance is deliberately one-directional: a cited whole dollar matches a cents payload value, a cited cents figure never matches a whole-dollar payload value"
  - "collect_allowed_values skips floats as well as strings — callers pass money as Decimal, so a float in a payload is a caller bug that should surface as an unmatched figure, not be silently admitted"
  - "Two docstrings reworded away from the plan's literal prose because that prose contained the exact tokens two acceptance criteria grep for the ABSENCE of (\"from app.features\", \"fallback\")"

patterns-established:
  - "Grounding validators live in app/core with no feature-package imports so quotes and finance share one implementation"
  - "Validation retry vs transport retry are named apart in docstrings — this path has no transport retry at all"

requirements-completed: [FINAI-01]

duration: 12 min
completed: 2026-07-29
---

# Phase 36 Plan 05: Grounding Machinery Summary

**A payload-shape-agnostic Decimal grounding validator in `app/core`, a fail-closed `call_claude_json_strict`, and the D-09 prompt contract that makes set-membership validation sound.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-07-29T19:13:22Z
- **Completed:** 2026-07-29T19:25:51Z
- **Tasks:** 3 (2 TDD)
- **Files created/modified:** 5

## Accomplishments

- `validate_grounding` extracts every `$`/`%` literal from AI text and checks each against a closed `frozenset[Decimal]`, returning the offending literals verbatim so the retry turn can name them back.
- `collect_allowed_values` walks nested mappings and sequences while skipping strings and bools — a project named "2026" cannot make "$2,026" citable, and `True` cannot become `Decimal("1")`.
- The two representation tolerances the shipped formatters force (cent equality plus a whole-dollar `ROUND_HALF_UP` match; one-decimal percents) are implemented and tested in both rounding directions.
- A fabricated `$0` is unmatched unless the payload carries a real zero (Pitfall 9).
- `call_claude_json_strict` raises on empty content and on unparseable JSON, accepts a multi-turn message list, and reads `usage` defensively; the shipped `call_claude_json` is untouched (verified by diff) and the Phase 26 checklist suite stays green.
- The prompt forbids the model from computing anything and mandates the sigils the extractor keys on — that combination is what turns D-05 into set membership rather than an arithmetic search.

## Task Commits

1. **Task 1: ai_grounding.py — extraction, closed allowed set, matching** — `823ad9c` (test), `07d1820` (feat)
2. **Task 2: call_claude_json_strict — fail closed** — `dc43262` (test), `0068b85` (feat)
3. **Task 3: D-09 prompt contract and retry template** — `8abfacb` (feat)

## Files Created/Modified

- `backend/app/core/ai_grounding.py` — `CitedFigure`, `GroundingResult`, `collect_allowed_values`, `extract_figures`, `matches_allowed`, `validate_grounding`. No feature-package imports; Phase 37 reuses it unchanged.
- `backend/app/core/ai_utils.py` — added `ClaudeJsonResponse`, `call_claude_json_strict`, `_token_counts`. Nothing inside `call_claude_json` changed.
- `backend/app/features/finance/prompts/profitability_system.py` — length constants, `PROFITABILITY_SYSTEM_PROMPT` (7 numbered rules), `GROUNDING_RETRY_TEMPLATE`.
- `backend/app/features/finance/prompts/__init__.py` — empty package marker, mirroring `checklists/prompts/`.
- `backend/tests/unit/test_ai_grounding.py` — 33 tests (26 validator, 7 `strict_call`).

## Decisions Made

- **`MONEY_PATTERN` uses `(?:,\d{3})+`, not the plan's `*`.** Regex alternation is first-match-wins at a position, so with `*` the comma-grouped alternative matches `"$320"` inside `"$3200"` and the second alternative never runs. Requiring at least one comma group makes `"$3,200"` take alternative one and `"$3200"` fall through to alternative two intact — which is exactly what the plan's behavior list demands.
- **The whole-dollar tolerance is one-directional by design.** `allowed.quantize(WHOLE_DOLLAR, ROUND_HALF_UP) == cited` admits `"$3,200"` for a payload `3200.41` (what `format_alert_money` and a model both naturally write) but does not admit a cited `"$3,200.41"` for a payload `3200`. The model inventing cents is fabrication; the model dropping them is formatting. Tested in both rounding directions plus the wrong-side-of-the-boundary rejection.
- **Floats are not collected.** Only `Decimal` and non-bool `int` become citable. Callers pass money as `Decimal` and serialize at the call site, so a stray float is a caller bug that should surface as an unmatched figure rather than be silently admitted with binary-float equality semantics.
- **Percent and money never cross-match.** `is_percent` selects the comparison, so `6.2%` cannot be satisfied by a payload dollar value of `6.2` — covered by its own test.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The plan's `MONEY_PATTERN` truncates un-grouped dollar amounts**

- **Found during:** Task 1 (RED run of `test_extract_figures_finds_every_money_form`)
- **Issue:** The plan's pattern `-?\$\s?\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|...` matches `"$320"` inside `"$3200"` — the grouped alternative succeeds with zero comma groups and the un-grouped alternative is never tried. The plan's own behavior list requires `$3200` to extract as `3200`.
- **Fix:** Changed `(?:,\d{3})*` to `(?:,\d{3})+` so the grouped alternative requires a comma and `$3200` falls through to the un-grouped alternative.
- **Files modified:** `backend/app/core/ai_grounding.py`
- **Verification:** `test_extract_figures_finds_every_money_form` asserts all four forms (`$3,200`, `$3,200.41`, `$3200`, `-$350.00`) and their normalized Decimals.
- **Committed in:** `07d1820`

**2. [Rule 3 - Blocking] Two of the plan's own docstrings would have failed the plan's own acceptance greps**

- **Found during:** Task 1 and Task 2
- **Issue:** The criteria are token-absence greps: `! grep -q "from app.features" ai_grounding.py` and `! grep -A25 "async def call_claude_json_strict" | grep -q "fallback"`. The plan's suggested prose contained both tokens verbatim ("it imports nothing from app.features"; "returns a caller-supplied fallback dict on bad JSON").
- **Fix:** Reworded to "carries no feature-package imports" and "degrades to a caller-supplied default dict on bad JSON". Meaning preserved exactly; only the greppable tokens changed. Same class of adjustment as the 36-03 prose decision already recorded in STATE.md.
- **Files modified:** `backend/app/core/ai_grounding.py`, `backend/app/core/ai_utils.py`
- **Verification:** Both greps now report absence; the descriptive intent is still stated in each docstring.
- **Committed in:** `07d1820`, `0068b85`

**3. [Rule 2 - Missing Critical] Added a seventh `strict_call` test for a present `usage` block**

- **Found during:** Task 2
- **Issue:** The plan's six behaviors only assert the *absent*-usage path. Nothing proved the tokens are actually read when present, so a `_token_counts` returning `None, None` unconditionally would have passed.
- **Fix:** Added `test_strict_call_reads_usage_tokens_when_present` asserting `1200` / `340` reach `ClaudeJsonResponse`.
- **Files modified:** `backend/tests/unit/test_ai_grounding.py`
- **Verification:** `-k strict_call` selects 7 tests, all green.
- **Committed in:** `dc43262`, `0068b85`

---

**Total deviations:** 3 auto-fixed (1 bug, 1 blocking, 1 missing critical)
**Impact on plan:** No scope change. The regex fix is required for a plan-stated behavior; the wording fixes are required by the plan's own acceptance criteria; the extra test closes a hole those criteria left open.

## Issues Encountered

None. The 36-03 blocker noted in STATE.md (`test_financial_alert_types_are_the_budget_types` red on an exact-frozenset assertion) was already relaxed to a subset check in `bb3a151` before this plan started, so the full `tests/unit` suite ran green (229 passed).

## Known Stubs

None. Every function in this plan is fully implemented and tested. `ai_grounding` and `call_claude_json_strict` have no call sites yet by design — plan 36-06/36-07 wires them into the finding service and 36-08 exercises the prompt end to end.

## User Setup Required

None — no external service configuration required.

## Verification

- `python -m pytest tests/unit -q` — 229 passed
- `python -m pytest tests/unit/test_ai_grounding.py -q` — 33 passed (26 validator + 7 `strict_call`)
- `python -m pytest tests/test_phase_26_e2e.py -q` — 19 passed (checklists unaffected by the `ai_utils` addition)
- `ruff check .` clean; `ruff format --check .` — 318 files already formatted
- `git diff` on `ai_utils.py` shows additions only; nothing inside `call_claude_json` changed

## Next Phase Readiness

- SC3's machinery is complete and reusable: the validator has no feature-package imports, so Phase 37's quote planning imports it unchanged.
- The service plan that consumes this must precompute every citable delta as a named `Decimal` payload field — the closed-set property is a caller obligation, not something the validator can enforce.
- `GROUNDING_RETRY_LIMIT` (the validation retry count) still belongs to the service plan; this module deliberately ships no retry loop.

---
_Phase: 36-ai-profitability-analysis_
_Completed: 2026-07-29_

## Self-Check: PASSED

All 6 claimed files exist on disk; all 5 task commits (823ad9c, 07d1820, dc43262, 0068b85, 8abfacb) are present in git history.
