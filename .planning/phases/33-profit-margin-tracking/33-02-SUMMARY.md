---
phase: 33-profit-margin-tracking
plan: "02"
subsystem: finance
tags: [margin, revenue, sqlalchemy, decimal, rls, pytest]

# Dependency graph
requires:
  - phase: 33-profit-margin-tracking (33-01)
    provides: margin_math.py value objects (RevenueAnchor, DocumentAmounts) and pure margin rules
  - phase: 32-labor-rates-and-cost-rollup
    provides: WorkSession/labor derivation, cost breakdown queries, D-12 rollup traversal shape
  - phase: 25-per-trade-billing
    provides: Invoice/Quote models with job_id XOR trade_scope_id anchors
provides:
  - Phase 33 backend integration contract — 13 named RED tests in test_phase_33_e2e.py (green in 33-03)
  - RevenueRepository — bounded per-anchor and per-project invoice/quote money-field aggregates
  - D-14 project-level approved-quote leg (latest_project_level_approved_quote_amounts)
  - WorkSession.job_id so per-anchor labor presence is identifiable at project level
affects: [33-03 margin API assembly, 33-04 web margin UI, 33-05 mobile margin UI, 34-budgeting, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Column-only GROUP BY document aggregates returning value objects (never ORM rows, lazy="raise" safe)
    - Revenue queries copy the cost rollup's dual-outerjoin D-12 traversal verbatim
    - Integration contract shipped RED one wave ahead of the implementation that turns it green

key-files:
  created:
    - backend/tests/test_phase_33_e2e.py
  modified:
    - backend/app/features/finance/repository.py
    - backend/app/features/finance/labor_derivation.py

key-decisions:
  - "Quote approval in tests seeded via raw SQL UPDATE, not POST /quotes/{id}/approve — the endpoint demands sent/viewed transitions and creates jobs for project-level quotes"
  - "One shared _to_anchored_amounts row mapper serves both document types — invoice and quote queries lead with the same six columns by construction"
  - "Entity creation in tests uses the admin tenant client (users.create/invoices.create holder); finance reads use synthetic project_manager tokens — mirrors phase 32"

patterns-established:
  - "Anchor-taking repository methods (_anchor_filter) so services never branch on job-vs-scope"
  - "QUOTE_STATUS_APPROVED module constant — no status literal in any where clause"

requirements-completed: [MARG-01, MARG-02, MARG-03]

# Metrics
duration: 25min
completed: 2026-07-28
---

# Phase 33 Plan 02: Revenue Queries and Integration Contract Summary

**13-test RED margin integration contract plus RevenueRepository: bounded Decimal-only invoice/quote aggregates per anchor and per project through the D-12 dual-outerjoin traversal, with WorkSession now carrying job_id**

## Performance

- **Duration:** ~25 min active execution (session limit interrupted the plan mid-Task-2; wall clock 2026-07-27T17:11Z → 2026-07-28T00:12Z)
- **Started:** 2026-07-27T17:11:35Z
- **Completed:** 2026-07-28T00:12:32Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Shipped the phase's executable integration contract: 13 named tests encoding every observable consequence of D-01..D-14 (invoiced-wins-outright, latest-approved-quote fallback, pre-tax revenue, D-12 same-traversal netting, D-14 project-level quote, Pitfall-9 keystone honesty flag, D-07 absent-not-flagged, finance.view 403)
- `RevenueRepository` returns `DocumentAmounts`/`RevenueAnchor` value objects from column-only GROUP BY aggregates — O(1) round trips per leg regardless of document count, `lazy="raise"` never trips
- Project revenue legs (invoice + quote) copy `rollup_for_project`'s `(TradeScope.project_id == p) | (Job.project_id == p)` traversal byte-for-byte, so 33-03's margin nets revenue and cost through identical joins
- `WorkSession` gained a trailing defaulted `job_id`, populated by the shared costable-session query — the per-anchor labor-presence signal the project incomplete flag needs, with zero disturbance to existing callers (126 phase 31/32 + unit tests still green)

## Task Commits

Each task was committed atomically:

1. **Task 1: Phase 33 backend integration contract (RED)** - `78b55c0` (test)
2. **Task 2: RevenueRepository + WorkSession.job_id** - `b2f3ee8` (feat)

## Files Created/Modified

- `backend/tests/test_phase_33_e2e.py` - 13 MARG-01/02/03 integration tests (RED until 33-03), phase-32-style seed helpers extended with scope-anchored cost seeding, invoice/quote posting, and SQL quote approval
- `backend/app/features/finance/repository.py` - `RevenueRepository` (5 read-only methods), `_invoice_amounts_query`/`_approved_quote_amounts_query` builders, `_anchor_filter`, `_to_anchored_amounts`, `QUOTE_STATUS_APPROVED`; costable-session query now selects `TimeEntry.job_id`
- `backend/app/features/finance/labor_derivation.py` - `WorkSession.job_id: uuid.UUID | None = None` trailing field

## Decisions Made

- Test fixtures approve quotes via raw SQL (`SET LOCAL` + `UPDATE quotes SET status='approved'`) instead of the approve endpoint, which requires a sent/viewed transition and creates jobs for project-level quotes — both would pollute margin fixtures
- Entity creation flows through the admin tenant client (holds `users.create`, `invoices.create`, `quotes.create`); finance GETs use synthetic `project_manager` tokens; the 403 test uses synthetic admin tokens — exactly the phase-32 split
- A single `_to_anchored_amounts` mapper handles both document row shapes because both queries lead with the same six columns (the quote query's trailing `created_at` is ignored by the `row[:6]` unpack)

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

- `backend/tests/test_phase_33_e2e.py` — all 13 tests are intentionally RED (the `margin` block does not exist on any response yet). This is the plan's designed contract-first posture; 33-03 (Wave 3) assembles the API and turns them green. Collect-only verification passed (13 collected, ruff clean).
- `RevenueRepository` has no in-service consumer yet — 33-03 wires it into `FinanceService` margin assembly. Shipped ahead per the plan's wave split; not dead code but staged infrastructure.

## Issues Encountered

- Execution was interrupted by a session limit between the `labor_derivation.py` edit and the `repository.py` edits; resumed cleanly from verified git state with no rework (Task 1 commit already landed).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 33-03 (Wave 3) has everything it needs: `margin_math` (33-01), revenue rows per anchor/project + D-14 leg + per-job labor presence (this plan), and the 13-test contract to turn green
- Verification for 33-03: `cd backend && .venv/bin/pytest tests/test_phase_33_e2e.py -q` must go 13/13 green

## Self-Check: PASSED

- `backend/tests/test_phase_33_e2e.py` exists (613 lines, 13 collected) ✓
- `backend/app/features/finance/repository.py` contains `class RevenueRepository(TenantScopedRepository[Invoice])` ✓
- `backend/app/features/finance/labor_derivation.py` contains `job_id: uuid.UUID | None = None` ✓
- Commits `78b55c0` and `b2f3ee8` exist on master ✓
- Phase 31/32 + unit regression: 126 passed ✓

---
*Phase: 33-profit-margin-tracking*
*Completed: 2026-07-28*
