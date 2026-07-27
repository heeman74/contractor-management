---
phase: 32-labor-rates-and-cost-rollup
plan: 01
subsystem: finance
tags: [labor-rates, effective-dated, fastapi, sqlalchemy, rls, rbac, decimal]

# Dependency graph
requires:
  - phase: 30-financial-schema-foundation
    provides: labor_rates table + ix_labor_rates_company_user_effective (migration 0032), finance.rates.manage permission key with admin exclusion
  - phase: 31-actual-cost-capture
    provides: finance router/repository/service structure, inline require_permission gate pattern, test_phase_31_e2e helper conventions
provides:
  - Pure DB-free labor derivation module (work_date_for, resolve_rate_row_for_work_date, session_labor_cost, summarize_labor)
  - LaborRateRepository (append-only reads/writes over labor_rates, resolver sort order, user_exists soft-FK check)
  - LaborRateService (create with 404 on unknown user, history, one-current-rate-per-worker resolution)
  - POST/GET /api/v1/labor-rates/ gated finance.rates.manage (no PATCH/DELETE)
  - _group_rates_by_user helper for 32-02 derivation reuse
affects: [32-02 derivation queries, 32-03 web Team page rates UI, 33-margin, 37-ai-quote-planning]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Effective-dated lookup as a pure Protocol-typed module (EffectiveDatedRate) — resolution rule lives in exactly one place, unit-tested without a DB"
    - "bisect_right over ascending (effective_from, created_at) sort — last row at shared effective_from IS the created_at tie-break"
    - "Per-session Decimal quantization with ROUND_HALF_UP — itemized views always sum to the displayed total"

key-files:
  created:
    - backend/app/features/finance/labor_derivation.py
    - backend/tests/unit/test_labor_derivation.py
    - backend/tests/test_phase_32_e2e.py
  modified:
    - backend/app/features/finance/schemas.py
    - backend/app/features/finance/repository.py
    - backend/app/features/finance/service.py
    - backend/app/features/finance/router.py

key-decisions:
  - "PEP 695 type parameters (def f[RateT: EffectiveDatedRate]) instead of module-level TypeVar — ruff UP047 enforces the modern generic syntax"
  - "UTC work-day convention (clocked_in_at.astimezone(UTC).date()) stated verbatim in the module docstring; users.timezone deliberately unused"
  - "Both rate read and write gated finance.rates.manage — zero-exception posture (admin and worker 403 even on their own rate)"

patterns-established:
  - "Effective-dated rate rule: greatest effective_from <= work day, latest created_at tie-break, no covering row = unrated seconds"
  - "Append-only money history: corrections via backdating or same-effective_from re-entry, never UPDATE/DELETE"

requirements-completed: [COST-04, COST-05]

# Metrics
duration: 21min
completed: 2026-07-27
---

# Phase 32 Plan 01: Labor Rates Backend Foundation Summary

**Append-only effective-dated labor rates: pure bisect-based rate resolver with ROUND_HALF_UP Decimal math, LaborRate repository/service, and POST/GET /labor-rates/ gated finance.rates.manage**

## Performance

- **Duration:** 21 min
- **Started:** 2026-07-27T04:10:09Z
- **Completed:** 2026-07-27T04:31:43Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments

- The codebase's first effective-dated lookup shipped as a pure, DB-free module (`labor_derivation.py`) — the rate rule (greatest `effective_from` <= work day, latest `created_at` tie-break, unrated when uncovered) lives in exactly one place, proven by 14 unit tests
- COST-04 backend complete: append-only rate creation with any effective date (past/present/future), full per-worker history, and a one-query current-rate-per-worker listing
- Zero-exception permission posture verified: admin and worker roles both receive 403 with `Missing permission: finance.rates.manage` on read AND write
- Full backend suite green (664 passed, 1 skipped) — no phase 30/31 regressions, no new migrations, no new dependencies

## Task Commits

Each task was committed atomically:

1. **Task 1 (TDD RED): failing labor derivation tests** - `dbaf4b8` (test)
2. **Task 1 (TDD GREEN): pure labor derivation module** - `e99a78e` (feat)
3. **Task 2: LaborRate schemas, repository, service** - `7b25bfe` (feat)
4. **Task 3: labor-rate endpoints + COST-04 integration tests** - `f00abbd` (feat)

## Files Created/Modified

- `backend/app/features/finance/labor_derivation.py` - Pure rate resolution + labor cost math (work_date_for, resolve_rate_row_for_work_date, session_labor_cost, summarize_labor); zero SQLAlchemy/FastAPI imports
- `backend/tests/unit/test_labor_derivation.py` - 14 DB-free unit tests: boundary date, tie-break, future-dated, unrated, UTC work day, half-up rounding, per-session quantization
- `backend/app/features/finance/schemas.py` - LaborRateCreate (gt=0, lt=100000, 2dp) and LaborRateResponse appended
- `backend/app/features/finance/repository.py` - LaborRateRepository: list_history_for_user (DESC display order), list_all_rates / list_rates_for_users (ascending resolver order), user_exists
- `backend/app/features/finance/service.py` - LaborRateService (create/history/current) + module-level _group_rates_by_user for 32-02 reuse
- `backend/app/features/finance/router.py` - POST + GET /labor-rates/ with inline finance.rates.manage gates; no PATCH/DELETE
- `backend/tests/test_phase_32_e2e.py` - 10 COST-04 integration tests + phase-31-style helpers ready for 32-02 extension

## Decisions Made

- **PEP 695 generics over TypeVar:** the plan's skeleton used `RateT = TypeVar(...)`; ruff UP047 requires `def resolve_rate_row_for_work_date[RateT: EffectiveDatedRate](...)`. Same semantics, modern syntax, zero behavioral difference.
- Followed all other plan specifications exactly (UTC work-day convention docstring verbatim, bisect_right tie-break, per-session quantization, soft-FK user_exists check).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Converted TypeVar generics to PEP 695 type-parameter syntax**
- **Found during:** Task 1 (pure labor-derivation module)
- **Issue:** The plan-specified `TypeVar("RateT", bound=EffectiveDatedRate)` fails `ruff check` (UP047) — pre-commit would block every commit
- **Fix:** `def resolve_rate_row_for_work_date[RateT: EffectiveDatedRate](...)` / `def summarize_labor[RateT: EffectiveDatedRate](...)`; removed the module-level TypeVar
- **Files modified:** backend/app/features/finance/labor_derivation.py
- **Verification:** ruff check clean, all 14 unit tests pass
- **Committed in:** e99a78e (Task 1 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Syntax-only change required by the project's lint rules. No scope creep.

## Acceptance-Criteria Notes

- Task 2 criterion "`grep -c \"db.commit()\"` returns 0" technically matches 1 — the match is the pre-existing Phase 31 module docstring line "*No db.commit() — get_db handles transaction lifecycle*", which documents the rule. Zero actual `db.commit()` calls exist in service.py; the criterion's intent holds.

## Issues Encountered

None — all 10 integration tests passed on first run; full suite green.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `labor_derivation.py` + `_group_rates_by_user` + `LaborRateRepository.list_rates_for_users` are ready for 32-02's two-query bounded derivation (COST-05/COST-06)
- `/api/v1/labor-rates/` endpoints ready for 32-03's web Team page rate column + history dialog
- `test_phase_32_e2e.py` helpers (`_create_user`, `_seed_cost_categories`, project/scope/job creators) in place for 32-02 test extension

---
*Phase: 32-labor-rates-and-cost-rollup*
*Completed: 2026-07-27*

## Self-Check: PASSED

- All 3 created files exist on disk
- All 4 task commits (dbaf4b8, e99a78e, 7b25bfe, f00abbd) present in git history
