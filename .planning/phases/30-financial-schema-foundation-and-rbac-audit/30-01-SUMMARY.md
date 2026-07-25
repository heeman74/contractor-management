---
phase: 30-financial-schema-foundation-and-rbac-audit
plan: 01
subsystem: auth
tags: [rbac, permissions, fastapi, pytest]

# Dependency graph
requires: []
provides:
  - "finance.view / finance.manage / finance.rates.manage permission keys in PERMISSION_CATALOG"
  - "_FINANCE_ONLY_KEYS exclusion tuple subtracted from the admin derivation"
  - "project_manager default permission set includes all three finance keys"
  - "backend/tests/test_phase_30_e2e.py phase E2E anchor with reusable _token() helper"
affects: [30-02, 30-03, 30-04, 32, 33, 34, 35, 36]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Finance-only permission keys excluded from admin via set subtraction on the derived _ADMIN_KEYS list (mirrors the existing _OWNER_ONLY_KEYS pattern)"
    - "Phase E2E anchor file (test_phase_30_e2e.py) established as the shared home for later Phase 30 plans' integration tests, with a reusable _token() JWT helper"

key-files:
  created:
    - backend/tests/unit/test_permissions_finance_keys.py
    - backend/tests/test_phase_30_e2e.py
  modified:
    - backend/app/core/permissions.py

key-decisions:
  - "Finance keys appended as the last catalog group (after Portal), per UI-SPEC copywriting contract, rather than interleaved near Quotes/Invoices"
  - "Admin exclusion implemented as a derived set subtraction (_FINANCE_ONLY_KEYS), not a hand-maintained admin list, so it can never drift as the catalog grows"

patterns-established:
  - "Finance-only permission keys excluded from admin via set subtraction on the derived _ADMIN_KEYS list"

requirements-completed: [FINSEC-01, FINSEC-02, FINSEC-03]

# Metrics
duration: 15min
completed: 2026-07-25
---

# Phase 30 Plan 01: Finance Permission Catalog and RBAC Foundation Summary

**Three finance.* permission keys added to the catalog under a derived-exclusion admin gate, proven safe by both a pure-unit regression test and the phase's first RBAC integration tests.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-07-25T01:04:00Z
- **Completed:** 2026-07-25T01:19:33Z
- **Tasks:** 3
- **Files modified:** 3 (1 modified, 2 created)

## Accomplishments
- `finance.view`, `finance.manage`, `finance.rates.manage` added to `PERMISSION_CATALOG` under a new "Finance" group, appended after "Portal" per the UI-SPEC copywriting contract
- Admin's derived permission set (`_ADMIN_KEYS`) excludes all three finance keys by construction via a new `_FINANCE_ONLY_KEYS` set subtraction — mirrors the existing `_OWNER_ONLY_KEYS` pattern so it can never drift as the catalog grows
- `project_manager`'s default permission list now includes all three finance keys; owner unchanged (wildcard already covers them)
- Pure-unit regression suite (`tests/unit/test_permissions_finance_keys.py`, 5 tests) proves admin exclusion, PM inclusion, catalog grouping, and gc/worker exclusion — runs in milliseconds, no DB
- Phase E2E anchor file (`tests/test_phase_30_e2e.py`) created with a shared `_token()` JWT-minting helper and 3 integration tests proving FINSEC-01/02/03 at the API/matrix layer: seeded-company defaults, admin exclusion via live `/me/permissions`, and an owner granting `finance.view` to `gc` through the existing roles matrix endpoint taking effect immediately (without also granting `finance.manage`)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add finance.* keys to the catalog and exclude them from admin** - `943d4c0` (feat)
2. **Task 2: Pure-unit regression test for admin exclusion and PM inclusion** - `6a02dfa` (test)
3. **Task 3: Phase E2E scaffold + RBAC integration tests** - `8bb3701` (test)

_Note: Task 1 is marked `tdd="true"`, but its `<verify>` command targets `tests/unit/test_permissions_finance_keys.py`, which Task 2 authors as its own dedicated deliverable. Task 1's acceptance criteria (grep + inline-python assertions) were verified directly against the catalog edit; Task 2's pytest suite is the actual regression coverage and was verified green before its commit._

## Files Created/Modified
- `backend/app/core/permissions.py` - Added `_FINANCE_ONLY_KEYS`, 3 catalog entries under group "Finance", updated `_ADMIN_KEYS` derivation, updated `project_manager` defaults
- `backend/tests/unit/test_permissions_finance_keys.py` - 5 pure-unit tests (no DB) proving admin exclusion, PM inclusion, catalog grouping, exclusion-tuple parity, gc/worker exclusion
- `backend/tests/test_phase_30_e2e.py` - Phase E2E anchor: shared `_token()` helper, `FINANCE_KEYS` constant, 3 integration tests covering FINSEC-01/02/03

## Decisions Made
- Finance keys appended as the last catalog group (after "Portal"), matching the UI-SPEC's requirement that the sensitive new group render as its own appended section rather than interleaved near Quotes/Invoices
- Admin exclusion implemented via derived set subtraction rather than a hand-maintained list, consistent with the existing `_OWNER_ONLY_KEYS` pattern, so future catalog additions can't accidentally leak into admin

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- `ruff check --fix` flagged two Yoda-condition (`SIM300`) findings and one unsorted-import block across the new test files; both were auto-fixed by `ruff check --fix` / `ruff format` before committing (mechanical lint fixes, not logic changes — no separate deviation entry needed since these are formatting-only and required by CLAUDE.md's pre-commit-must-pass rule).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- The three finance.* keys and their default grants are now the fixed contract every later Phase 30 plan (and later financial phases 32-36) build against.
- `backend/tests/test_phase_30_e2e.py` exists as the shared phase E2E anchor — plans 02/03 add their own test functions to this same file, and plan 04 fills in remaining coverage.
- No blockers for plan 30-02.

---
*Phase: 30-financial-schema-foundation-and-rbac-audit*
*Completed: 2026-07-25*

## Self-Check: PASSED

All created files and task commits verified present.
