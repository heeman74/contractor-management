---
phase: 35-web-financial-dashboard
plan: 01
subsystem: api
tags: [finance, margin, budget, trend, portfolio, pure-math, tdd, decimal]

# Dependency graph
requires:
  - phase: 33-margin-visibility
    provides: margin_math D-01 anchor revenue resolution, summarize_margin, MarginSummary schema
  - phase: 34-budget-tracking
    provides: budget_math crossed_thresholds / percent_used threshold rule
  - phase: 32-labor-rates-and-cost-rollup
    provides: labor_derivation effective-dated rate rule, summarize_labor, work_date_for
provides:
  - "margin_math.anchor_revenues / combined_anchor_revenue / quoted_revenue — the shipped D-01 resolution, now DB-free and importable"
  - "schemas.to_margin_summary — MarginFigures to wire-schema mapper outside the service"
  - "FinanceService.rates_by_contractor — public single bounded rate fetch for the trend service"
  - "trend_math.py — monthly dense cumulative buckets via as-of D-01 replay"
  - "portfolio_math.py — portfolio totals and D-08/D-11 attention tiers"
affects: [35-02-financial-repository, 35-03-financial-service, 35-04-financial-data-layer, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "As-of replay: a past-dated figure is produced by re-running the shipped resolution over a filtered record set, never by a second implementation"
    - "Prefix-summed month partitions costed by summarize_labor, keeping the effective-dated rate rule out of SQL"
    - "Window slices output buckets, never input records"

key-files:
  created:
    - backend/app/features/finance/trend_math.py
    - backend/app/features/finance/portfolio_math.py
    - backend/tests/unit/test_trend_math.py
    - backend/tests/unit/test_portfolio_math.py
  modified:
    - backend/app/features/finance/margin_math.py
    - backend/app/features/finance/schemas.py
    - backend/app/features/finance/service.py

key-decisions:
  - "Revenue per trend bucket is re-resolved, never accumulated — an invoice supersedes its own quote exactly as the shipped rollup does, so the final bucket reconciles with rollup_for_project"
  - "incomplete_project_count counts incomplete-TIER projects, not every project carrying the flag, so the D-09 badge and the attention list read one predicate and cannot disagree"
  - "combined_anchor_revenue's parameter renamed anchor_revenues -> resolved_anchors; co-locating both in margin_math would otherwise shadow the sibling function"
  - "_missing_cost_flag applies D-12 to the project total at trend granularity — the trend has no per-anchor cost split, so the signal is deliberately coarser than the rollup's per-anchor sweep"

patterns-established:
  - "Promotion over duplication: shipped service helpers move into the DB-free math module when a second consumer needs them, rather than being re-implemented"
  - "Named tier/window maps (_TIER_RANK, TREND_WINDOW_MONTHS) replace bare string and month-count literals at use sites"

requirements-completed: [MARG-04]

# Metrics
duration: 96 min
completed: 2026-07-29
---

# Phase 35 Plan 01: Financial Math Foundation Summary

**Two DB-free math modules — `trend_math` (dense monthly buckets via as-of D-01 revenue replay) and `portfolio_math` (D-08 attention tiers + portfolio totals) — plus promotion of the shipped anchor-revenue resolution out of `service.py` so the trend replays it instead of re-implementing it.**

## Performance

- **Duration:** 96 min
- **Started:** 2026-07-29T01:56:04Z
- **Completed:** 2026-07-29T03:32:00Z
- **Tasks:** 3 (2 of them TDD, 5 commits total)
- **Files modified:** 7 (4 created, 3 modified)

## Accomplishments

- The Phase 33 D-01 per-anchor revenue resolution is now reachable from a DB-free module (`margin_math.anchor_revenues` / `combined_anchor_revenue` / `quoted_revenue`), with all 107 shipped Phase 32/33/34 finance e2e tests passing and **zero test-file edits**.
- `trend_math.trend_buckets` produces dense, gapless monthly cumulative buckets where each bucket is a full re-run of the shipped `summarize_margin` pipeline at that month's inclusive edge — so the final bucket reconciles with `rollup_for_project` by construction rather than by coincidence.
- `portfolio_math` derives attention tiers from live `crossed_thresholds` state (D-11); no input or output dataclass carries a `fired_at` field, so the alert-dedup timestamps *cannot* be consulted even by accident — pinned by a test that inspects the dataclass fields.
- 41 new unit tests (19 trend + 22 portfolio), all F.I.R.S.T.: no DB, no async, no fixtures beyond module-level builders.

## Task Commits

1. **Task 1: Promote the shared revenue-resolution helpers into margin_math** — `288f7d7` (refactor)
2. **Task 2: trend_math.py — monthly cumulative buckets by as-of replay** — `9aac09d` (test, RED) → `2b51744` (feat, GREEN)
3. **Task 3: portfolio_math.py — portfolio totals and D-08/D-11 attention tiers** — `30cf6c8` (test, RED) → `62ae320` (feat, GREEN)

No REFACTOR commits were needed — both modules were written to the ~20-line/one-thing target in the GREEN step and required no cleanup pass.

## Files Created/Modified

- `backend/app/features/finance/trend_math.py` — Month bucketing (`month_key`, `month_edge`, `dense_month_keys`), the `trend_buckets` orchestrator, and `window_slice`. Docstring carries the D-02 semantics table verbatim.
- `backend/app/features/finance/portfolio_math.py` — `worst_crossed_budget`, `attention_entry_for`, `attention_entries`, `portfolio_totals`, `anchor_label_for`.
- `backend/tests/unit/test_trend_math.py` — 19 tests, one per `<behavior>` bullet.
- `backend/tests/unit/test_portfolio_math.py` — 22 tests, one per `<behavior>` bullet.
- `backend/app/features/finance/margin_math.py` — Gained the three promoted revenue functions.
- `backend/app/features/finance/schemas.py` — Gained `to_margin_summary`.
- `backend/app/features/finance/service.py` — Lost the four moved definitions; imports them back (which is what keeps `budget_service`'s lazy `from ...service import quoted_revenue` resolving); `_rates_by_contractor` is now public `rates_by_contractor`.

## Decisions Made

- **Revenue is resolved per bucket, never accumulated.** Delta accumulation would double-count an anchor that was quoted and later invoiced, and the final bucket would not reconcile with the rollup. The accepted artifact — revenue *dropping* when a $10k quote is part-invoiced at $3k — is honest and annotated by `revenue_basis`.
- **`incomplete_project_count` counts the incomplete tier, not the flag.** The plan's `<behavior>` block and the UI-SPEC "badge/list agreement invariant" both require the badge count to equal the incomplete tier size; the plan's `<action>` sketch said "count of `project.margin.incomplete`", which is larger whenever a project is both flagged and overrun. Resolved in favour of the behavior contract; `_is_incomplete_tier` is the single predicate both the badge and the list read.
- **D-12 is coarser in the trend than in the rollup.** The rollup flags missing cost data per revenue-bearing anchor; the trend has no per-anchor cost split (labor is job-anchored while cost entries prefix-sum project-wide), so `_missing_cost_flag` applies the shipped `missing_cost_data` to the project total. Documented in the helper's docstring.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Extra shadow rename beyond the one the plan named**
- **Found during:** Task 1
- **Issue:** The plan called out the `anchor_revenues` local in `_project_margin`. Two further bindings shared the name: the parameter of `_combined_anchor_revenue` (which moves *into* `margin_math`, landing beside the `anchor_revenues` function it would shadow) and the parameter of `service._any_anchor_missing_cost_data`.
- **Fix:** Renamed both parameters to `resolved_anchors`. Both are called positionally, so no call site changed shape and behavior is identical.
- **Files modified:** backend/app/features/finance/margin_math.py, backend/app/features/finance/service.py
- **Verification:** 107 Phase 32/33/34 e2e tests pass unchanged; `grep -c resolved_anchors service.py` returns 5 (the plan's criterion expected 3, counting only `_project_margin`'s bind + 2 uses).
- **Committed in:** `288f7d7`

**2. [Rule 1 - Bug] Plan's internal contradiction on `incomplete_project_count`**
- **Found during:** Task 3
- **Issue:** The `<behavior>` block requires the count to equal the number of incomplete-tier entries; the `<action>` sketch specified counting every project with `margin.incomplete`. These differ whenever a project is both flagged and over budget.
- **Fix:** Implemented the `<behavior>`/UI-SPEC contract via a shared `_is_incomplete_tier` predicate, so the badge and the attention list are provably the same set.
- **Files modified:** backend/app/features/finance/portfolio_math.py
- **Verification:** `test_incomplete_project_count_matches_the_incomplete_tier_size` asserts `count == len(incomplete tier) == 1` for a fixture containing a flagged-and-overrun project.
- **Committed in:** `62ae320`

---

**Total deviations:** 2 auto-fixed (2 bugs — one latent `UnboundLocalError` class of shadow, one spec contradiction)
**Impact on plan:** Both were necessary for correctness. No scope creep; no new dependency; no shipped behavior changed.

### Acceptance-criterion notes (not deviations)

- Task 3's criterion `grep -n "fired_at" portfolio_math.py` returns no matches has one match — in the **module docstring**, which the same task's `<action>` explicitly requires ("Module docstring states D-11 in one WHY line: ...the fired timestamps are an alert-dedup claim, not a condition"). The criterion's intent (no code dependency on those columns) holds: no dataclass field, no import, no read.
- Task 2's criterion "no literal 3/6/12 month count outside `TREND_WINDOW_MONTHS`" holds; the only grep hit is the string `D-12` inside a docstring.

## Issues Encountered

**Test-DB contention with parallel agents produced a false regression.** The combined Phase 32/33/34 e2e run reported `2 failed, 96 passed, 9 errors` in 19m18s while sibling agents were running their own suites against the shared `contractorhub_test` database (the same command had passed 107/107 in 2m44s earlier in this plan). Re-running the suites in isolation after the contention cleared: `tests/test_phase_32_e2e.py` 27/27 in 71s, `tests/test_phase_33_e2e.py` + `tests/test_phase_34_e2e.py` 80/80 in 5m19s — **107/107 green**. Tasks 2 and 3 only add new modules that no shipped code path imports, so a real regression from them was not structurally possible; the isolated re-runs confirm it. No code change was made in response.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for 35-02 (financial repository): it must supply `TrendInputs` (with `effective_date` already resolved as `COALESCE(approved_at, created_at)` per Pitfall 4) and `ProjectFinancialFigures`; both dataclasses are the stable contract.
- `FinanceService.rates_by_contractor` is public so the trend service shares one bounded rate fetch rather than issuing its own (CLAUDE.md N+1 rule).
- `anchor_label_for` is available so the repository/service names scope anchors identically to shipped alert copy, rather than re-formatting the em-dash template.
- No blockers.

## Self-Check: PASSED

All 7 claimed files exist on disk; all 5 claimed task commits resolve in `git log`.

---
*Phase: 35-web-financial-dashboard*
*Completed: 2026-07-29*
