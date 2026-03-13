---
phase: 08-business-operations
plan: "00"
subsystem: testing
tags: [pytest, flutter_test, weasyprint, fl_chart, test-stubs, wave-0]

# Dependency graph
requires:
  - phase: 07-client-portal-and-notifications
    provides: conftest.py fixtures and test infrastructure used as starting point

provides:
  - Backend integration test stubs for BIZ-01 through BIZ-04 (16 tests)
  - Backend unit test stubs for quote validation (4 tests)
  - Flutter E2E test stubs for full quote-to-invoice flow (14 skipped tests)
  - Phase 8 tables added to conftest.py TRUNCATE list
  - WeasyPrint installed in backend venv
  - fl_chart ^1.2.0 installed in mobile venv

affects: [08-01, 08-02, 08-03, 08-04, 08-05]

# Tech tracking
tech-stack:
  added:
    - weasyprint 68.1 (backend dev dependency via uv add --dev)
    - fl_chart ^1.2.0 (mobile Flutter dependency)
  patterns:
    - Wave 0 test stubs use pytest.fail() (not assert False) to comply with ruff PT015/B011 rules
    - Flutter stubs use skip parameter on test() calls — no wrapper needed

key-files:
  created:
    - backend/tests/integration/test_phase_8_e2e.py
    - backend/tests/unit/test_quote_validation.py
    - mobile/test/e2e/phase_8_business_ops_e2e_test.dart
  modified:
    - backend/tests/conftest.py (TRUNCATE list extended with Phase 8 tables)
    - mobile/pubspec.yaml (fl_chart added)
    - backend/pyproject.toml (weasyprint dev dependency)
    - backend/uv.lock

key-decisions:
  - "Wave 0 stubs use pytest.fail() not assert False — ruff PT015+B011 rules prohibit assert False in test files"
  - "WeasyPrint installed as dev dependency (uv add --dev) — project pyproject.toml has no [project] table for prod deps"
  - "Phase 8 TRUNCATE order: invoice_line_items -> invoices -> quote_line_items -> quote_templates -> quotes — child tables before parents to respect FK constraints"

patterns-established:
  - "Stub pattern: pytest.fail('not yet implemented') for backend; test(..., skip='not yet implemented') for Flutter"

requirements-completed: [BIZ-01, BIZ-02, BIZ-03, BIZ-04]

# Metrics
duration: 3min
completed: 2026-03-13
---

# Phase 8 Plan 00: Wave 0 Test Stubs and Dependencies Summary

**pytest and flutter_test stub scaffolding for Phase 8 business-operations, with WeasyPrint and fl_chart installed, enabling VALIDATION.md sampling commands to run after every task commit**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-13T23:54:00Z
- **Completed:** 2026-03-13T23:57:06Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Created 16 backend integration test stubs (BIZ-01 through BIZ-04) in `test_phase_8_e2e.py`, all discoverable by pytest
- Created 4 backend unit test stubs in `test_quote_validation.py` for quote validation edge cases
- Created 14 skipped Flutter E2E test stubs in `phase_8_business_ops_e2e_test.dart` covering Quote Flow, Invoice Flow, and Reports groups
- Extended `conftest.py` TRUNCATE list with Phase 8 tables: `invoice_line_items`, `invoices`, `quote_line_items`, `quote_templates`, `quotes`
- Installed WeasyPrint 68.1 as backend dev dependency
- Installed fl_chart ^1.2.0 as mobile Flutter dependency

## Task Commits

Each task was committed atomically:

1. **Task 1: Create backend test stubs, update conftest, and install WeasyPrint** - `1a0642d` (chore)
2. **Task 2: Create Flutter E2E test stub and add fl_chart dependency** - `5d1b96e` (chore)

## Files Created/Modified

- `backend/tests/integration/test_phase_8_e2e.py` — 16 async pytest stubs for BIZ-01 through BIZ-04
- `backend/tests/unit/test_quote_validation.py` — 4 unit stubs for quote validation edge cases
- `mobile/test/e2e/phase_8_business_ops_e2e_test.dart` — 14 skipped Flutter stubs (Quote Flow, Invoice Flow, Reports)
- `backend/tests/conftest.py` — TRUNCATE list extended with 5 Phase 8 tables
- `mobile/pubspec.yaml` — fl_chart ^1.2.0 added
- `backend/pyproject.toml` — weasyprint dev dependency added
- `backend/uv.lock` — dependency lock updated

## Decisions Made

- Used `pytest.fail("not yet implemented")` instead of `assert False` because ruff rules PT015 and B011 prohibit `assert False` in test files
- WeasyPrint installed as dev dependency (`uv add --dev`) because `pyproject.toml` has no `[project]` table for production dependencies
- Phase 8 TRUNCATE order respects FK constraints: `invoice_line_items` before `invoices`, `quote_line_items` before `quotes`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Replaced `assert False` stubs with `pytest.fail()` to pass ruff check**
- **Found during:** Task 1 (running ruff check before commit)
- **Issue:** ruff PT015 + B011 rules reject `assert False` in test files
- **Fix:** Replaced all `assert False, "msg"` with `pytest.fail("msg")` in both test files
- **Files modified:** `backend/tests/integration/test_phase_8_e2e.py`, `backend/tests/unit/test_quote_validation.py`
- **Verification:** `ruff check` exits 0; `pytest --collect-only` finds 20 tests
- **Committed in:** 1a0642d (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Required for ruff compliance (CLAUDE.md requires ruff check before commit). No scope creep.

## Issues Encountered

- WeasyPrint requires system-level `libpango` native library at import time; this library is not installed on the macOS dev machine. The Python package is installed correctly in the venv (confirmed via pyproject.toml and uv.lock). This is an OS-level prerequisite for production PDF generation, not a blocker for the test stub phase.

## User Setup Required

None — no external service configuration required for this plan.

## Next Phase Readiness

- All VALIDATION.md Wave 0 requirements satisfied
- `pytest tests/integration/test_phase_8_e2e.py --collect-only` discovers 16 tests
- `pytest tests/unit/test_quote_validation.py --collect-only` discovers 4 tests
- `flutter test test/e2e/phase_8_business_ops_e2e_test.dart` runs with 14 skipped, 0 failures
- Plans 08-01 through 08-05 can begin immediately in Wave 1

---
*Phase: 08-business-operations*
*Completed: 2026-03-13*

## Self-Check: PASSED

- FOUND: backend/tests/integration/test_phase_8_e2e.py
- FOUND: backend/tests/unit/test_quote_validation.py
- FOUND: mobile/test/e2e/phase_8_business_ops_e2e_test.dart
- FOUND: .planning/phases/08-business-operations/08-00-SUMMARY.md
- FOUND: commit 1a0642d
- FOUND: commit 5d1b96e
