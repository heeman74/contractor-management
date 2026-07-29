---
phase: 36-ai-profitability-analysis
plan: 07
subsystem: api
tags: [fastapi, sqlalchemy, decimal, structlog, ai-grounding, profitability]

requires:
  - phase: 36-01
    provides: ai_profitability_findings migration + ProfitabilityRepository
  - phase: 36-03
    provides: profitability_math (D-01 eligibility, D-03 detection, bands, fingerprints)
  - phase: 36-05
    provides: app/core/ai_grounding.py (collect_allowed_values) + the prompt contract
  - phase: 35-web-financial-dashboard
    provides: PortfolioService batched company read, trend replay, portfolio_math figures
provides:
  - "ProfitabilityService.scan_candidates: batched read -> D-01 eligibility gate -> D-03 detection -> aggregates-only payload"
  - "Three public PortfolioService seams: all_project_figures, unsliced_trend_buckets, margin_context"
  - "portfolio_service.project_cost_blocks: one assembly pass yielding both the cost breakdown and the margin context"
  - "The CLOSED payload contract: 21 named fields, six of them precomputed citable deltas, all money/percent as Decimal"
  - "O(eligible) scan evidence: a mutation-verified statement-count test"
affects: [36-08, 36-09, 36-10, ai-quote-planning]

tech-stack:
  added: []
  patterns:
    - "Eligibility-gate-before-replay: the per-project bounded read runs only for projects the gate cleared, making the scan O(eligible)"
    - "Closed-set payload assembly: every figure the prompt may cite is a named Decimal field, so D-05 validation stays pure set membership"
    - "Structured logging as the run log: one named-reason line per skip plus one per-company summary, rendered at the call site so tests can assert them"

key-files:
  created:
    - backend/app/features/finance/profitability_service.py
  modified:
    - backend/app/features/finance/portfolio_service.py
    - backend/tests/test_phase_36_e2e.py

key-decisions:
  - "_build_payload takes a PayloadInputs dataclass carrying the batched cost blocks, NOT the plan's ProjectCostRollup — a real rollup would mean a per-project rollup query, which the plan's own key_link forbids"
  - "project_cost_blocks added as a fourth (internal) portfolio seam so the breakdown and the margin context come from ONE assembly pass; margin_context now delegates to it"
  - "The revenue-bearing zero-cost project is skipped as NO_COST_DATA, not INCOMPLETE_DATA — the shipped D-01 ladder checks the zero-cost rung before the incomplete flag"
  - "Log lines are %-rendered at the call site: structlog's stdlib bridge defers formatting to the handler, so positional args never reach structlog.testing.capture_logs"
  - "structlog.testing.capture_logs replaces the plan's caplog — caplog captures nothing from this app's structlog configuration (verified empirically)"
  - "ProfitabilityCandidate shipped without its payload field in Task 2 and gained it in Task 3's GREEN step, so no commit ever carried an empty placeholder payload"

patterns-established:
  - "Payload closure is a caller obligation: the payload builder, not the validator, is what makes the allowed-value set closed"
  - "Query-count bounds are mutation-verified: replacing `eligible` with all figures makes the two counts equal and the test fails"

requirements-completed: [FINAI-01]

duration: 26min
completed: 2026-07-29
---

# Phase 36 Plan 07: Nightly Scan Read Half Summary

**`ProfitabilityService.scan_candidates` — one batched company read, the D-01 eligibility gate with named skip reasons, D-03 detection through `profitability_math`, and a 21-field aggregates-only AI payload whose six citable deltas are precomputed named Decimals.**

## Performance

- **Duration:** 26 min
- **Started:** 2026-07-29T21:29:59Z
- **Completed:** 2026-07-29T21:56:24Z
- **Tasks:** 3 (Task 3 executed TDD: RED then GREEN)
- **Files modified:** 3

## Accomplishments

- `PortfolioService` now exposes `all_project_figures`, `unsliced_trend_buckets` and `margin_context`; `company_financials` and `margin_trend` route through them, so the figures have one source and the trend has one source.
- New `ProfitabilityService.scan_candidates`: one company-wide batched read, eligibility partitioning with a logged named reason per skipped project, detection delegated wholly to `profitability_math`, and a per-company summary log line. No `db.commit()`, no `window_slice`, no query inside a loop other than the deliberately bounded per-eligible-project trend replay.
- The AI payload is aggregates-only and CLOSED: `project_name`, `project_status`, `cost`, `revenue`, `revenue_basis`, `quoted_revenue_share`, `margin`, `margin_percent`, `labor_basis`, `labor_cost`, `categories[]`, `budgets[]` (with `percent_used`/`remaining` precomputed), `trend[]` (last two cumulative buckets), `signal`, `severity_band`, plus the six delta fields `negative_margin_dollars`, `margin_decline_points`, `quote_gap_points`, `billed_margin_percent`, `quote_implied_margin_percent`, `over_quote_dollars`.
- Seven new integration tests: four D-01 skips asserting the exact logged reason, the end-to-end `quote_gap` candidate, the payload field-set/Decimal/forbidden-field contract (checked through `collect_allowed_values`), and the O(eligible) statement-count bound.

## Task Commits

1. **Task 1: Promote three PortfolioService seams** — `60390b4` (refactor)
2. **Task 2: scan_candidates eligibility + detection + run log** — `f550a70` (feat)
3. **Task 3 RED: failing eligibility/candidate/payload tests** — `88685e6` (test)
4. **Task 3 GREEN: aggregates-only payload with named deltas** — `5c6f692` (feat)

## Files Created/Modified

- `backend/app/features/finance/profitability_service.py` — the scan half: eligibility partition, per-eligible detection, payload assembly (`_build_payload` composed of `_cost_block`, `_context_block`, `_signal_block`), skip/summary logging.
- `backend/app/features/finance/portfolio_service.py` — three promoted seams, plus `ProjectCostBlocks` / `project_cost_blocks` so the breakdown and margin context come from one pass.
- `backend/tests/test_phase_36_e2e.py` — `_count_sql_statements` (copied per the self-contained convention), `_seed_analyzable_project`, `_activate_project`, `_scan_candidates`, log-assertion helpers, and the seven new tests.

## Decisions Made

**1. `_build_payload` consumes batched cost blocks, not a `ProjectCostRollup`.** The plan's signature would have required `FinanceService.rollup_for_project` per project — a per-project rollup loop the plan's own `key_links` forbid ("one batched company read, no per-project rollup loop") — and a `ProjectCostRollup` also carries raw `CostEntry` rows the payload must never see. `PayloadInputs` (figures + candidate + `ProjectCostBlocks` + unsliced buckets) supplies the category mix and the folded labor row from rows already fetched.

**2. `project_cost_blocks` as the single cost-side assembly.** The payload needs the category mix and the derived labor total; the margin needs the anchor costs and the grand total. Returning both from one pass means the labor fold is applied exactly once and the two halves cannot disagree. `margin_context` (the Task 1 seam) is now a one-line delegation.

**3. The zero-cost revenue-bearing project is `NO_COST_DATA`.** The plan expected `INCOMPLETE_DATA` for that fixture, but the shipped D-01 ladder tests `cost <= 0` before `margin.incomplete`, so `NO_COST_DATA` is the real verdict. The Pitfall-9 property the plan cares about (a fabricated 100% margin never reaches the AI) holds either way, and `INCOMPLETE_DATA` is covered by the unrated-labor test where cost is positive and the margin's honesty flag is what fires.

**4. Log lines render at the call site.** `logger.info(TEMPLATE % (...))`, not `logger.info(TEMPLATE, ...)`: this app binds structlog to the stdlib bridge, which defers %-formatting to the handler, so with positional args the values never reach `structlog.testing.capture_logs` and the run log would be unassertable. A WHY comment sits on the templates.

**5. `structlog.testing.capture_logs`, not `caplog`.** Verified empirically: with this app's structlog configuration `caplog.records` is empty even at INFO level, so a caplog-based skip-reason assertion would have passed vacuously.

**6. Deliberate payload exclusions.** The uncosted-time second count and the incomplete-reason list are absent by design — D-01 guarantees both are empty for any analyzed project, so including either would ship a citable zero waiting to be fabricated against. The `_build_payload` docstring states this in prose that avoids the literal field tokens, because the task's acceptance criterion greps for their ABSENCE (the same trap 36-03 and 36-05 hit).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `_build_payload(rollup: ProjectCostRollup)` was unobtainable**
- **Found during:** Task 3
- **Issue:** A `ProjectCostRollup` only comes from `FinanceService.rollup_for_project`, i.e. ~6 queries per project inside the scan loop — forbidden by CLAUDE.md's N+1 rule and by this plan's own `key_links`. It also carries raw cost-entry rows.
- **Fix:** Introduced `PayloadInputs` plus `portfolio_service.project_cost_blocks`, so the payload's category mix and labor row come from the batched company read.
- **Files modified:** backend/app/features/finance/profitability_service.py, backend/app/features/finance/portfolio_service.py
- **Verification:** `test_candidate_scan_query_count_is_bounded_by_eligible_projects` plus the shipped Phase 35 query-count invariance test, both green.
- **Committed in:** `f550a70` (seam) and `5c6f692` (payload)

**2. [Rule 1 - Bug] `caplog` cannot observe this app's logs**
- **Found during:** Task 3
- **Issue:** The plan's `caplog`-based assertion captures zero records under this app's structlog configuration; the test would have passed no matter what the service logged.
- **Fix:** Assert through `structlog.testing.capture_logs`, and render the log templates at the call site so the captured event carries the project id and the reason.
- **Files modified:** backend/app/features/finance/profitability_service.py, backend/tests/test_phase_36_e2e.py
- **Verification:** All four skip tests fail when the skip line is removed and pass with it; the summary-line assertion carries the exact analyzed/candidates/skipped counts.
- **Committed in:** `88685e6`, `5c6f692`

**3. [Rule 1 - Bug] Test fixtures were creating draft projects while asserting active behavior**
- **Found during:** Task 3
- **Issue:** `ProjectCreate` declares no `status` field, so the file's `_create_project` helper posted `{"status": "active"}` into the void and every "active" fixture was actually `draft` — which D-01 skips. Eligibility tests would have been meaningless.
- **Fix:** Removed the ignored body field, documented the trap in the helper docstring, and added `_activate_project` (PATCH) which every analyzable fixture calls.
- **Files modified:** backend/tests/test_phase_36_e2e.py
- **Verification:** `test_skips_non_active_project` (draft) and the candidate tests (patched to active) now exercise opposite sides of the gate.
- **Committed in:** `88685e6`

**4. [Rule 3 - Blocking] Task 1 acceptance grep needed a docstring reshape**
- **Found during:** Task 1
- **Issue:** `grep -A4 "async def margin_trend" | grep -q unsliced_trend_buckets` could not pass with the shipped six-line docstring ahead of the call.
- **Fix:** Condensed `margin_trend`'s docstring so it names the seam it now delegates to, and moved the "six bounded queries then a pure Python replay" note onto `unsliced_trend_buckets` where those reads actually live.
- **Files modified:** backend/app/features/finance/portfolio_service.py
- **Verification:** All Task 1 acceptance greps pass; Phase 35 suite green (24 passed).
- **Committed in:** `60390b4`

---

**Total deviations:** 4 auto-fixed (2 blocking, 2 bug)
**Impact on plan:** No scope change. Deviation 1 preserves the plan's stated performance invariant that its own suggested signature would have broken; deviations 2 and 3 turn two would-be vacuous tests into real ones.

## Issues Encountered

- `ruff`'s PT018 rejected three compound assertions in the payload test; split into single-fact assertions with a named `_PAYLOAD_BUDGET_MONEY_FIELDS` tuple.
- The plan's Task 2 dataclass listed a `payload` field before Task 3 built it. Rather than commit an empty placeholder payload, Task 2 shipped `ProfitabilityCandidate` with its four metadata fields and Task 3's GREEN step added `payload` — every commit is internally complete.

## Known Stubs

None. `scan_candidates` returns fully-populated candidates; the Claude call, validation, persistence and alerting are separate plans (36-08+) by design, not stubs here.

## Verification Evidence

- `pytest tests/test_phase_35_e2e.py tests/test_phase_36_e2e.py tests/unit -q` → **266 passed** (includes the shipped company-rollup query-count invariance test).
- `ruff check .` and `ruff format --check .` → clean (319 files).
- **Mutation check on the O(eligible) claim:** passing all `figures` (not `eligible`) into detection makes the two statement counts equal and `test_candidate_scan_query_count_is_bounded_by_eligible_projects` fails; restored, green again.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `scan_candidates` hands 36-08 exactly what the Claude call needs: the `CandidateSignal` (signal, band, fingerprint), the finding's honesty columns (`revenue_basis`, `labor_included`), and the closed payload to ground against via `collect_allowed_values`.
- **Carry-forward for 36-08/09:** the closed-set property remains a CALLER obligation. Any figure the prompt is later allowed to cite must be added to `_build_payload` as its own named Decimal field — the validator cannot derive it.
- Wave 4's remaining backend plans should keep running serially against `contractorhub_test` (the Phase 35 truncation-deadlock blocker still stands).

---
*Phase: 36-ai-profitability-analysis*
*Completed: 2026-07-29*

## Self-Check: PASSED

- All three key files exist on disk.
- All four task commits present in git history (`60390b4`, `f550a70`, `88685e6`, `5c6f692`).
