---
phase: 30-financial-schema-foundation-and-rbac-audit
plan: 03
subsystem: auth
tags: [rbac, finance-permissions, fastapi, sqlalchemy, dashboard]

# Dependency graph
requires:
  - phase: 30-01
    provides: finance.* permission catalog keys and RBAC matrix scaffolding
provides:
  - scrub_finance_fields helper (app.core.finance_scrub) — no-op with access, strips FINANCE_FIELD_NAMES without
  - DashboardService.get_alerts has_finance_view flag filtering FINANCIAL_ALERT_TYPES (empty today)
  - dashboard router resolves finance.view from effective_permissions and passes it through
affects: [30-04, 34, 36]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Inert-but-ready plumbing: helper/filter shipped with no data to act on yet, unit-tested for the contract, wired into the real leak surface in a later phase"

key-files:
  created:
    - backend/app/core/finance_scrub.py
    - backend/tests/unit/test_finance_scrub.py
  modified:
    - backend/app/features/dashboard/service.py
    - backend/app/features/dashboard/router.py

key-decisions:
  - "finance_scrub helper shipped as a tested utility only — NOT wired into ChecklistService/DashboardService dict-builders this phase (nothing to strip yet; wiring it in now would be dead code per CLAUDE.md, per 30-RESEARCH.md Open Question 3)"
  - "FINANCIAL_ALERT_TYPES ships empty — filter logic is provably inert today; Phase 36 only needs to populate the frozenset, not touch filter logic"

patterns-established:
  - "Permission-gated filters resolve effective_permissions(current_user, db) in the router and pass a plain bool kw-only flag into the service — keeps service layer testable without auth context"

requirements-completed: [FINSEC-04]

# Metrics
duration: 12min
completed: 2026-07-25
---

# Phase 30 Plan 03: Finance-Scrub Helper and Dashboard Alert Finance Filter Summary

**Standalone `scrub_finance_fields` helper plus a `has_finance_view`-gated filter on `DashboardService.get_alerts`, both shipped inert (no finance fields to strip, no financial alert types yet) with full unit coverage.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-07-25T01:12:00Z
- **Completed:** 2026-07-25T01:24:58Z
- **Tasks:** 2
- **Files modified:** 4 (2 created, 2 modified)

## Accomplishments
- `backend/app/core/finance_scrub.py` ships `FINANCE_FIELD_NAMES` (named frozenset constant) and `scrub_finance_fields(context, has_finance_access)` — identity no-op with access, shallow key-strip without
- `DashboardService.get_alerts` gained a keyword-only `has_finance_view: bool = False` param and a module-level `FINANCIAL_ALERT_TYPES: frozenset[str] = frozenset()` constant; filters out any alert whose `alert_type` is in that set unless the caller has finance view
- `dashboard/router.py get_alerts` resolves `effective_permissions(current_user, db)` and passes `has_finance_view="finance.view" in granted` through — router stays thin
- 5 pure unit tests cover no-op/strip/immutability/full-field-coverage behavior of the scrub helper and assert `FINANCIAL_ALERT_TYPES == frozenset()` as an explicit "inert today" contract for Phase 36 to update

## Task Commits

Each task was committed atomically:

1. **Task 1: finance_scrub helper + permission-aware dashboard alert filter** - `2ef0f87` (feat)
2. **Task 2: Unit tests for the finance-scrub helper and the empty-set filter contract** - `922ef5f` (test)

**Plan metadata:** (this commit, pending)

## Files Created/Modified
- `backend/app/core/finance_scrub.py` - FINANCE_FIELD_NAMES constant + scrub_finance_fields no-op/strip helper
- `backend/app/features/dashboard/service.py` - FINANCIAL_ALERT_TYPES constant; get_alerts gains has_finance_view kw-only filter
- `backend/app/features/dashboard/router.py` - resolves effective_permissions and passes has_finance_view through to get_alerts
- `backend/tests/unit/test_finance_scrub.py` - 5 pure unit tests for the scrub helper and the empty-alert-set contract

## Decisions Made
- Followed 30-RESEARCH.md Code Examples 3 and 4 exactly for the helper and filter shape — no deviation.
- Left `scrub_finance_fields` unwired from `checklists/service.py` and the AI dict-builders per Open Question 3 — confirmed via `grep -c "scrub_finance_fields" app/features/checklists/service.py` returning 0. The cross-surface leak tripwires (asserting today's AI dict output has no `FINANCE_FIELD_NAMES` keys) are explicitly deferred to plan 04's E2E suite, not this plan.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- One transient failure in `pytest tests/integration -q -k dashboard` (`test_dashboard_role_scoping`, a `ForeignKeyViolationError` on `users.company_id`) caused by concurrent test-DB contention with the parallel sibling agent (both agents share `contractorhub_test`). Re-ran the file in isolation and the full `-k dashboard` selection immediately after — both passed cleanly (5/5), confirming it was DB-contention noise, not a regression from this plan's changes.

## Next Phase Readiness
- `scrub_finance_fields` and `FINANCIAL_ALERT_TYPES` are ready for Phase 34 (budgeting AI context) and Phase 36 (AI profitability alerts) to consume without further plumbing changes.
- Plan 04 (same phase) owns the cross-surface leak tripwire E2E suite that exercises this plumbing end-to-end.

---
*Phase: 30-financial-schema-foundation-and-rbac-audit*
*Completed: 2026-07-25*

## Self-Check: PASSED

- FOUND: backend/app/core/finance_scrub.py
- FOUND: backend/tests/unit/test_finance_scrub.py
- FOUND commit: 2ef0f87
- FOUND commit: 922ef5f
