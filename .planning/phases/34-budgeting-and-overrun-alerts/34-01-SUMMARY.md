---
phase: 34-budgeting-and-overrun-alerts
plan: 01
subsystem: database
tags: [alembic, sqlalchemy, postgres, decimal, budgets, dashboard-alerts, fcm]

# Dependency graph
requires:
  - phase: 30-financial-schema-foundation-and-rbac-audit
    provides: budgets table (dormant), FINANCIAL_ALERT_TYPES filter plumbing (D-11), finance.* RBAC
  - phase: 33-profit-margin-tracking
    provides: margin_math PERCENT_MULTIPLIER + quantize/ROUND_HALF_UP conventions, labor_derivation CENTS
provides:
  - Migration 0035 — budget alert types in dashboard_alerts CHECK, budget threshold-state columns + total>0 CHECK + one-active-budget-per-anchor partial unique indexes, quotes.revised_from_quote_id revision chain
  - alert_types.py — single source of all five dashboard alert_type constants with FINANCIAL_ALERT_TYPES = {budget_warning, budget_overrun}
  - budget_math.py — pure Decimal threshold/percent/copy math with the four locked UI-SPEC alert templates and FCM push titles
  - Budget.warning_fired_at / overrun_fired_at exactly-once fire state (D-01), Quote.revised_from_quote_id (BUDG-04)
affects: [34-02, 34-03, 34-04, 34-05, 34-06, 34-07, 34-08, 35-financial-dashboard, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "alert_types.py constants-only module: DB CHECK values and FINANCIAL_ALERT_TYPES expressed in one importable-from-anywhere place"
    - "budget_math mirrors margin_math: DB-free pure Decimal module owning every threshold comparison and locked copy string"

key-files:
  created:
    - backend/migrations/versions/0035_budget_alerts_and_quote_chain.py
    - backend/app/features/dashboard/alert_types.py
    - backend/app/features/finance/budget_math.py
    - backend/tests/unit/test_budget_evaluation.py
  modified:
    - backend/app/features/finance/models.py
    - backend/app/features/quotes/models.py
    - backend/app/features/dashboard/models.py
    - backend/app/features/dashboard/service.py
    - backend/tests/unit/test_finance_scrub.py
    - backend/tests/test_phase_30_e2e.py
    - docker-compose.yml

key-decisions:
  - "Alembic revision ID shortened to 0035_budget_alerts_quote_chain (30 chars) — the plan's 34-char ID overflowed alembic_version varchar(32); filename unchanged"
  - "service.py re-imports FINANCIAL_ALERT_TYPES/SCHEDULE_SLIP_ALERT_TYPE with an explanatory comment instead of noqa F401 — both names are used in the module, and RUF100 rejects unused noqa directives"
  - "budget_math imports only CENTS and PERCENT_MULTIPLIER (not ZERO_MONEY) — ZERO_MONEY has no use site and an unused import fails ruff"

patterns-established:
  - "Threshold-state columns: NULL = not fired, timestamp = fired; raising the total NULLs both (D-03 re-arm)"
  - "One active budget per anchor enforced by partial unique index (deleted_at IS NULL), service 409 in 34-02 is the friendly layer"

requirements-completed: [BUDG-03, BUDG-04]

# Metrics
duration: 13min
completed: 2026-07-28
---

# Phase 34 Plan 01: Schema and Pure-Logic Foundation Summary

**Migration 0035 (budget alert types, exactly-once threshold state, quote revision chain), FINANCIAL_ALERT_TYPES registered as the two budget types, and a pure-Decimal budget_math module owning all four locked alert templates**

## Performance

- **Duration:** 13 min
- **Started:** 2026-07-28T05:09:40Z
- **Completed:** 2026-07-28T05:22:59Z
- **Tasks:** 3 (Task 3 TDD: RED + GREEN commits)
- **Files modified:** 11

## Accomplishments

- Migration 0035 applied to the local Docker DB and verified reversible: dashboard_alerts accepts budget_warning/budget_overrun (unknown types still rejected), budgets carries warning_fired_at/overrun_fired_at + total>0 CHECK + one-active-budget-per-anchor partial unique indexes, quotes carries revised_from_quote_id
- Budget/Quote/DashboardAlert models mirror the new schema exactly (verified by import assertions and the phase 31 e2e suite)
- alert_types.py is the single source of all five alert_type constants; FINANCIAL_ALERT_TYPES == {budget_warning, budget_overrun} makes the Phase 30 D-11 permission filter live — the two shipped tests pinning the empty set were corrected in the same commit, and the FINSEC-04 leak test now seeds a real budget_warning alert instead of a monkeypatched stand-in
- budget_math.py computes percent-used (1dp ROUND_HALF_UP), threshold crossings (pure Decimal, warning-then-overrun order), money/percent display strings, and the four verbatim UI-SPEC alert templates — 19 unit tests, zero floats

## Task Commits

Each task was committed atomically:

1. **Task 1: Migration 0035 + model column additions** - `313748b` (feat)
2. **Task 2: Alert-type single source + FINANCIAL_ALERT_TYPES registration** - `fec7605` (feat)
3. **Task 3: budget_math pure module + unit tests (TDD)** - `46ec7a7` (test, RED) + `0e0ccab` (feat, GREEN)

## Files Created/Modified

- `backend/migrations/versions/0035_budget_alerts_and_quote_chain.py` - Alert-type CHECK expansion, budget threshold state + guards, quote revision chain
- `backend/app/features/dashboard/alert_types.py` - Single source of alert_type constants + FINANCIAL_ALERT_TYPES
- `backend/app/features/finance/budget_math.py` - Pure threshold/percent/copy math for budget alerts
- `backend/tests/unit/test_budget_evaluation.py` - 19 unit tests over threshold math and alert copy
- `backend/app/features/finance/models.py` - Budget.warning_fired_at/overrun_fired_at + total>0 CheckConstraint
- `backend/app/features/quotes/models.py` - Quote.revised_from_quote_id (no relationship — explicit query walk in 34-08)
- `backend/app/features/dashboard/models.py` - Five-value alert_type CheckConstraint
- `backend/app/features/dashboard/service.py` - Constants replaced by alert_types re-import; get_alerts docstring notes the filter is live
- `backend/tests/unit/test_finance_scrub.py` - Empty-set pin replaced with the budget-types contract
- `backend/tests/test_phase_30_e2e.py` - FINSEC-04 test exercises the real registration
- `docker-compose.yml` - migrate service now passes JWT_SECRET_KEY (blocking fix)

## Decisions Made

- Shortened the Alembic revision ID to `0035_budget_alerts_quote_chain` — see Deviations; filename and down_revision unchanged
- Replaced the plan's `# noqa: F401` re-export comment with a plain explanatory comment — both imported names are used in service.py, so the noqa was itself a RUF100 lint error
- budget_math imports CENTS + PERCENT_MULTIPLIER only; ZERO_MONEY had no use site and importing it would fail ruff's unused-import check

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan-specified revision ID overflowed alembic_version varchar(32)**
- **Found during:** Task 1 (first `docker compose up migrate` run)
- **Issue:** `0035_budget_alerts_and_quote_chain` is 34 characters; Alembic's version table column is varchar(32), so the version UPDATE failed with StringDataRightTruncationError
- **Fix:** Revision ID shortened to `0035_budget_alerts_quote_chain` (30 chars); file name and `down_revision = "0034_cost_receipts"` kept as planned
- **Files modified:** backend/migrations/versions/0035_budget_alerts_and_quote_chain.py
- **Verification:** Migration applies, reverses, and re-applies cleanly
- **Committed in:** 313748b (Task 1 commit)

**2. [Rule 3 - Blocking] migrate service missing JWT_SECRET_KEY**
- **Found during:** Task 1 (`docker compose up migrate` per CLAUDE.md rule)
- **Issue:** Alembic env imports app Settings, which requires jwt_secret_key; the migrate compose service only declared DATABASE_URL, so migration runs failed at Settings validation before Alembic started
- **Fix:** Added the same `JWT_SECRET_KEY: ${JWT_SECRET_KEY:-docker-dev-secret-change-in-production}` line the backend service already uses
- **Files modified:** docker-compose.yml
- **Verification:** `docker compose up migrate` completes with exit code 0
- **Committed in:** 313748b (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Both fixes were prerequisites for applying the migration locally. No scope creep; all planned contracts shipped byte-identical to the spec.

## Issues Encountered

- Docker Desktop was not running — launched it and waited for the daemon before applying the migration (environment, not code)
- The migrate container bakes `migrations/` at image build time (only `app/` is volume-mounted) — required `docker compose up --build migrate` after editing the revision ID

## Known Stubs

None — all shipped modules are fully wired; the deliberately dormant pieces (budget CRUD, alert firing, revision-chain walk) are later Phase 34 plans by design, not stubs in this plan's files.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plans 34-02 through 34-08 can consume: migration 0035 schema, alert_types constants, budget_math threshold/copy functions, Budget threshold-state columns, Quote.revised_from_quote_id
- Ready for 34-02 (budget CRUD service/endpoints — the partial unique indexes back its 409 duplicate handling)

---
*Phase: 34-budgeting-and-overrun-alerts*
*Completed: 2026-07-28*

## Self-Check: PASSED

All 4 created files exist on disk; all 4 task commits (313748b, fec7605, 46ec7a7, 0e0ccab) present in git history.
