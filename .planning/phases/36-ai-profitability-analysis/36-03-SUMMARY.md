---
phase: 36-ai-profitability-analysis
plan: 03
subsystem: finance
tags: [profitability, margin, detection, decimal, pure-module, ai]

# Dependency graph
requires:
  - phase: 33-margin-visibility
    provides: margin_math (margin_percent_for, quoted_revenue, ResolvedRevenue, RevenueAnchor)
  - phase: 35-web-financial-dashboard
    provides: trend_math cumulative as-of buckets, portfolio_math.ProjectFinancialFigures
  - phase: 36-ai-profitability-analysis
    provides: 36-01's AIProfitabilityFinding model and ai_profitability alert type
provides:
  - "profitability_math.py — the DB-free D-03 detector: eligibility, three signals, bands, fingerprint"
  - "skip_reason_for: the D-01 eligibility gate with four named SkipReason values"
  - "margin_decline_points: signal 1, the CUMULATIVE last-two-bucket drop"
  - "negative_margin_dollars: signal 2, read off dollars so zero-revenue losses fire"
  - "latest_quote_per_anchor + quote_implied_gap: signal 3, rebuilt from raw quote rows"
  - "band_for / fingerprint_for / candidate_for: two bands, the D-06 dedup key, one candidate per project"
  - "finance.service.contributing_anchor_cost promoted public for detector callers"
affects: [36-05, 36-06, 36-07, 36-08, ai-payload-builders, nightly-detection-sweep]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Fifth DB-free finance math module, same opener and named-Decimal-constant style as margin/budget/portfolio/trend"
    - "Signal figures are dropped unless they fired, so a payload can never show the AI a sub-threshold drift"
    - "The severity band lives inside the fingerprint, making a worsening band a different finding"

key-files:
  created:
    - backend/app/features/finance/profitability_math.py
    - backend/tests/unit/test_profitability_math.py
  modified:
    - backend/app/features/finance/service.py

key-decisions:
  - "margin_decline_points indexes buckets[-TREND_LOOKBACK_BUCKETS] (the last two edges), not the third-from-last"
  - "Module prose avoids the literal tokens the acceptance criteria grep for the absence of"
  - "The Pitfall-5 tautology guard doubles as the empty-comparable-set guard, so signal 3 has one early exit rather than two"
  - "candidate_for carries only fired signal figures; a sub-threshold drift is never handed to the AI as a finding"

patterns-established:
  - "Detection reads the UNSLICED trend: a UI window setting can never change what fires"
  - "Signal 3 composes the shipped quoted_revenue / margin_percent_for and the promoted contributing_anchor_cost, never restating them"

requirements-completed: [FINAI-01]

# Metrics
duration: 15min
completed: 2026-07-29
---

# Phase 36 Plan 03: Profitability Detection Math Summary

**DB-free D-03 detector: a four-reason D-01 eligibility gate, three margin-erosion signals (cumulative decline, negative dollars, quote-implied gap), two severity bands, and a band-carrying fingerprint — 43 fixture-free unit tests, zero DB.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-07-29T18:54:09Z
- **Completed:** 2026-07-29T19:09:00Z
- **Tasks:** 3 (each TDD: RED then GREEN)
- **Files modified:** 3 (2 created, 1 modified)

## Accomplishments

- `profitability_math.py` (319 lines) ships as the fifth DB-free finance math module. Every D-03 threshold and band boundary is a named, tunable `Decimal`; the module imports nothing from SQLAlchemy, FastAPI or any repository.
- Signal 3 is built from raw `(RevenueAnchor, DocumentAmounts)` rows through `latest_quote_per_anchor`, deliberately bypassing the shipped D-01 resolution that discards approved quotes at invoiced anchors — the exact leg this signal compares against. An acceptance grep pins that the resolution helper's name never appears in the module.
- The Pitfall-5 tautology guard is proven by test: a project whose comparable anchors all resolved to `quoted` yields no gap at all, so a rounding artifact can never fire the signal.
- The cumulative-vs-per-month trap (Pitfall 4) is pinned by a fixture whose two readings **disagree in sign**: per month the margin improves 10% → 20%, cumulatively it erodes 35.0% → 30.0%. The test asserts the cumulative reading fires.
- `_contributing_anchor_cost` promoted to `contributing_anchor_cost`; the 37 shipped Phase 33 and Phase 35 e2e tests stay green, proving the rename broke nothing.

## Task Commits

Each task ran RED → GREEN, committed atomically:

1. **Task 1: eligibility gate and signals 1-2** — `a408006` (test) → `c4dc02f` (feat)
2. **Task 2: quote-implied gap + promoted anchor-cost helper** — `d1ae229` (test) → `5070628` (feat)
3. **Task 3: bands, fingerprint, candidate assembly** — `25bc091` (test) → `8a0afa3` (feat)

No REFACTOR commits were needed — each GREEN landed clean under `ruff check` and `ruff format --check`.

## Files Created/Modified

- `backend/app/features/finance/profitability_math.py` — the whole detector: constants, `SkipReason`, `QuoteGapInputs`/`QuoteGap`/`DetectionInputs`/`CandidateSignal`, and the seven public functions.
- `backend/tests/unit/test_profitability_math.py` — 43 fixture-free unit tests. Selector counts: `-k decline` 7, `-k negative` 5, `-k quote_implied` 10, `-k fingerprint` 3.
- `backend/app/features/finance/service.py` — `_contributing_anchor_cost` → `contributing_anchor_cost`, with a docstring line explaining why it is public.
- `.planning/phases/36-ai-profitability-analysis/deferred-items.md` — one out-of-scope failure logged (see Issues Encountered).

## Decisions Made

**1. `margin_decline_points` compares the last two bucket edges, not the third-from-last.**
The plan's snippet docstring said "third-from-last", but its own behavior block ("from the LAST TWO buckets", "returns None when fewer than 2 buckets exist"), D-03 ("last 2 monthly trend buckets"), `TREND_LOOKBACK_BUCKETS = 2`, the `len(buckets) < TREND_LOOKBACK_BUCKETS` guard and the RESEARCH reference implementation (`buckets[-1]`, `buckets[-2]`) all say the last two. Implemented as `buckets[-TREND_LOOKBACK_BUCKETS]` so the constant drives both the guard and the index.

**2. The tautology guard is the only early exit in `quote_implied_gap`.**
The plan listed an empty-comparable-set check and the Pitfall-5 invoiced-anchor check as separate steps. `any()` over an empty set is already `False`, so `_has_billed_anchor` covers both — one exit instead of two, with no behavior difference and no unreachable branch.

**3. `candidate_for` drops signal figures that did not fire.**
A 2-point decline alongside a fired quote gap sets `margin_decline_points` to `None` in the candidate. The payload is what the AI cites, and D-05 validates cited figures — carrying a sub-threshold number invites the AI to name it as a finding.

**4. Bands are computed from the fired magnitudes, so band and signal can never disagree.**
`band_for` takes the same filtered figures `candidate_for` stores, so the fingerprint's band always describes the same number the payload carries.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan action text contradicted its own acceptance criteria on three forbidden tokens**

- **Found during:** Tasks 1 and 2
- **Issue:** The plan's action blocks specified module prose containing the literal strings `ACTIVE_PROJECT_STATUSES` ("Deliberately NOT ai_utils.ACTIVE_PROJECT_STATUSES"), `window_slice` ("window_slice is a UI concern") and `anchor_revenues` ("anchor_revenues() cannot supply this leg"). The same tasks' acceptance criteria assert `! grep -q` for all three. Writing the prose verbatim would have failed the criteria that exist to prove detection never reaches those code paths.
- **Fix:** Reworded each to preserve the intent without the token — "the shared active-status tuple in `core.ai_utils`, which also admits planning", "trimming the trend to a chart window is a UI concern", "the shipped D-01 resolution... drops approved quotes at invoiced anchors by design".
- **Files modified:** `backend/app/features/finance/profitability_math.py`
- **Verification:** All ten Task 1 and nine Task 2 acceptance greps pass.
- **Committed in:** `c4dc02f`, `5070628`

**2. [Rule 1 - Bug] The decline docstring's bucket index contradicted the behavior block**

- **Found during:** Task 1
- **Issue:** As documented under Decisions #1 — "third-from-last" would require ≥3 buckets and contradict `TREND_LOOKBACK_BUCKETS = 2` and the stated `len < 2` guard.
- **Fix:** Implemented `buckets[-TREND_LOOKBACK_BUCKETS]` and wrote the docstring as "between the last two bucket edges".
- **Files modified:** `backend/app/features/finance/profitability_math.py`
- **Verification:** `test_margin_decline_points_needs_two_buckets` (two buckets suffice) plus the 5.0/4.9 boundary tests.
- **Committed in:** `c4dc02f`

**3. [Rule 3 - Blocking] The promoted helper had one in-file call site, not two**

- **Found during:** Task 2
- **Issue:** The plan said "update its two in-file call sites". `grep -rn` across `backend/` found the definition plus exactly one call, inside `_any_anchor_missing_cost_data`.
- **Fix:** Renamed the definition and the single call. Verified repo-wide that no `_contributing_anchor_cost` reference survives.
- **Files modified:** `backend/app/features/finance/service.py`
- **Verification:** `pytest tests/test_phase_33_e2e.py tests/test_phase_35_e2e.py` — 37 passed.
- **Committed in:** `5070628`

---

**Total deviations:** 3 auto-fixed (2 bugs in plan text, 1 blocking discrepancy)
**Impact on plan:** All three were plan-text errors that its own acceptance criteria or the shipped code contradicted. Every behavior, threshold and acceptance criterion shipped as specified. No scope creep.

## Issues Encountered

**Pre-existing failure in `tests/unit/test_finance_scrub.py` — NOT caused by this plan, deliberately not fixed.**

`test_financial_alert_types_are_the_budget_types` asserts `FINANCIAL_ALERT_TYPES` equals exactly `{"budget_warning", "budget_overrun"}`. Plan 36-01 (commit `6b3fa6e`) registered `ai_profitability` as a third financial alert type per D-07 without updating this Phase 30 exact-equality assertion. Confirmed pre-existing by inspecting both files at `6b3fa6e`, which predates this plan's first commit.

Per the scope boundary (only auto-fix issues directly caused by the current task's changes), it is logged in `deferred-items.md` for whichever plan next touches the alert-delivery path (36-06 or 36-08). This plan touches no alert-type, dashboard or scrub code.

With that one exception, `pytest tests/unit` is 195 passed / 1 failed, and every suite this plan is responsible for is green:

- `tests/unit/test_profitability_math.py` — 43 passed
- `tests/test_phase_33_e2e.py tests/test_phase_35_e2e.py` — 37 passed (the rename broke nothing)
- `ruff check .` and `ruff format --check .` — clean across 314 files

## Verification Against Success Criteria

| Criterion | Evidence |
|---|---|
| Imports nothing from SQLAlchemy/FastAPI/repositories | `! grep -qE 'sqlalchemy\|fastapi\|repository'` passes |
| Every threshold and band boundary is a named `Decimal` | `MARGIN_DECLINE_POINTS`, `CRITICAL_DECLINE_POINTS`, `QUOTE_IMPLIED_GAP_POINTS`, `CRITICAL_QUOTE_GAP_POINTS` |
| Never calls the window slicer or the D-01 resolution helper | both absence greps pass |
| Signal 2 reads `margin`, not `margin_percent` | `test_negative_margin_dollars_fires_at_zero_revenue` asserts the percent is `None` while the loss is real |
| A worsening band yields a new fingerprint | `test_fingerprint_changes_when_the_band_worsens` |

## Must-Haves

| Truth | Test |
|---|---|
| Ineligible project yields a named skip reason, never a candidate | `test_skip_reason_*` (6 tests) |
| 5.0-point cumulative decline is a candidate, 4.9 is not | `test_margin_decline_points_is_the_drop_across_the_last_two_buckets` / `..._below_the_trigger_is_not_a_candidate` |
| Negative margin fires even where `margin_percent` is `None` | `test_negative_margin_dollars_fires_at_zero_revenue` |
| Invoiced-below-quote by 5 points is a candidate; quote-only never is | `test_quote_implied_gap_fires_at_exactly_five_points` / `..._is_none_for_a_quote_only_project` |
| Same inputs give the same fingerprint; a band change gives a different one | `test_fingerprint_is_identical_across_repeated_detection_runs` / `..._changes_when_the_band_worsens` |

## Known Stubs

None. Every function ships wired and tested; nothing returns a placeholder.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

The detector is complete and callable. The consuming plans need only supply already-fetched rows:

- `DetectionInputs(figures, buckets, quote_gap_inputs)` — `figures` from `portfolio_math.ProjectFinancialFigures`, `buckets` from `trend_math.trend_buckets` **unsliced**, and `QuoteGapInputs` from the D-01 resolved map, `latest_quote_per_anchor(raw_quote_rows)`, and per-anchor costs built with the now-public `contributing_anchor_cost`.
- `CandidateSignal.fingerprint` is the D-06 upsert key that 36-01's `AIProfitabilityFinding` already stores, and `CandidateSignal.band` maps 1:1 to `DashboardAlert.severity`.

One caution for the caller: pass the UNSLICED bucket list. Handing `window_slice`'s output to `candidate_for` would let a chart setting change what alerts fire.

## Self-Check: PASSED

All 2 created files and 1 modified file exist on disk; all 6 task commits resolve in
`git log`. Verified 2026-07-29.

---
*Phase: 36-ai-profitability-analysis*
*Completed: 2026-07-29*
