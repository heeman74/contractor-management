---
phase: 35-web-financial-dashboard
plan: 02
subsystem: testing
tags: [pytest, sqlalchemy, asyncpg, postgres, rls, finance, e2e]

# Dependency graph
requires:
  - phase: 30-financial-foundation
    provides: finance.* RBAC keys, cost_categories/cost_entries/budgets schema with RLS
  - phase: 32-labor-rates-and-cost-rollup
    provides: effective-dated labor rates and derived-labor project rollup
  - phase: 33-margin-visibility
    provides: margin block on the project rollup, raw-SQL quote-approval fixture lesson
  - phase: 34-budgeting-and-alerts
    provides: budget block on the project rollup, the endpoint-driven helper set this file reuses
provides:
  - Phase 35 backend E2E harness at backend/tests/test_phase_35_e2e.py
  - _count_sql_statements context manager (first query counter in the repo)
  - _seed_company_portfolio(project_count=N) multi-project portfolio seeder
  - _create_approved_quote / _create_invoice dated revenue seeders
  - Phase 35 URL constants (_COMPANY_FINANCIALS_URL, _project_financials_url, _project_trend_url)
affects: [35-05, 35-06, 35-07, 35-08]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Query counting via sqlalchemy.event on engine.sync_engine's before_cursor_execute, detached in a finally"
    - "Structure rows through shipped endpoints, high-volume money/time rows through one multi-row statement per table"
    - "Client-side uuid4() document ids so bulk-inserted line items can reference their parent without RETURNING"

key-files:
  created:
    - backend/tests/test_phase_35_e2e.py
  modified: []

key-decisions:
  - "The query counter listens on engine.sync_engine rather than wrapping sessions — SQLAlchemy's event API is synchronous by design, the same reason app/core/tenant.py's after_begin listener is sync"
  - "The portfolio seeder excludes the 'labor' cost category so no seeded entry folds into the derived labor row, keeping grand_total > total an unambiguous proof that time entries and rates seeded"
  - "Invoices and approved quotes sit on different anchors within a project (job[0]/scope[0] vs job[1]/scope[1]) so a seeded project resolves revenue_basis 'mixed', exercising both legs of the D-12 dual traversal"
  - "Bulk-inserted invoices/quotes carry client-generated uuid4() ids so their line items link without RETURNING, which SQLAlchemy does not return for text() executemany"
  - "The seeder takes the tenant's own client for structure endpoints and a separate finance.* header dict for the gated ones, relying on httpx per-request header precedence"

patterns-established:
  - "Scaffolding plans self-verify: every helper written before its consuming endpoint exists is proven against a SHIPPED endpoint in the same commit"
  - "Every seeded count is a named module constant; _SCOPES_PER_PROJECT is derived from len(_TRADE_NAMES) so the two can never disagree"

requirements-completed: [MARG-04]

# Metrics
duration: 54 min
completed: 2026-07-29
---

# Phase 35 Plan 02: Backend Test Harness Summary

**Phase 35's backend E2E harness built before its endpoints exist: the Phase 34 endpoint-driven helper set, a `before_cursor_execute` query counter with no repo precedent, and a parameterised multi-project portfolio seeder whose figures the shipped project rollup confirms.**

## Performance

- **Duration:** 54 min (roughly 35 min of it waiting on a contended shared test database)
- **Started:** 2026-07-29T02:01:00Z
- **Completed:** 2026-07-29T02:55:00Z
- **Tasks:** 3
- **Files modified:** 1 created, 0 modified

## Accomplishments

- `_count_sql_statements` — the D-03 N+1 guard's entire mechanism, and the first query-counting construct in this repository. Listens on `engine.sync_engine`, always detaches in a `finally`, and is proven by its own test that the recorded list stops growing after the block exits.
- `_seed_company_portfolio(project_count=N)` — per project: 4 trade scopes, 2 jobs, 20 cost entries, 50 completed time entries, 2 invoices, 2 approved quotes, 1 project budget, 4 scope budgets. Structure rows go through shipped endpoints so real validation runs; money and time rows go in as one multi-row statement per table.
- The seeder is proven correct against the **shipped** `GET /projects/{id}/cost-entries` rollup — entry count, `grand_total > total` (derived labor landed on top), budget total, and non-null revenue at basis `mixed` — before any of the three Phase 35 endpoints exist.
- Dated revenue seeders `_create_approved_quote` / `_create_invoice` that let later plans place revenue on a chosen month, including the `approved_at IS NULL` fixture the trend bucketing must not silently drop.

## Task Commits

1. **Task 1: Test module skeleton and reused helper set** — `10b3b9f` (test)
2. **Task 2: `_count_sql_statements` context manager** — `f0ec4f7` (test)
3. **Task 3: `_seed_company_portfolio` and correctness smoke tests** — `a4e5b03` (test)

## Files Created/Modified

- `backend/tests/test_phase_35_e2e.py` (834 lines) — the whole deliverable: 30 helpers, 5 self-verifying tests, Phase 35 URL constants, and the bulk-insert SQL for the D-03 seed.

## Decisions Made

- **Counter target.** `sqlalchemy.event.listen(engine.sync_engine, "before_cursor_execute", ...)` rather than session instrumentation. `conftest.py` monkey-patches `db_module.engine` to a NullPool engine at import time, and because conftest is imported before any test module, `from app.core.database import engine` binds the test engine — so the counter observes exactly the connections the ASGI app uses.
- **No `labor` category in the seed.** A labor-categorised cost entry folds into the derived labor row (Phase 32 decision), which would make `grand_total > total` ambiguous. Seeding only `materials`/`subcontractor`/`other` keeps that assertion a clean proof that the time entries and labor rates seeded.
- **Split revenue anchors.** Invoices land on `job[0]`/`scope[0]`, approved quotes on `job[1]`/`scope[1]`, so every seeded project resolves both an invoiced and a quoted anchor — `revenue_basis == "mixed"` — instead of invoices silently winning everywhere and leaving the quote leg unexercised.
- **Client-generated document ids.** SQLAlchemy does not return `RETURNING` values for `text()` executemany, so bulk-inserted invoices and quotes carry `uuid4()` ids generated in Python; their line items reference those ids directly.
- **Attention-tier totals baked into the seeder.** Spend is $4,000.00 per project by construction ($2,000.00 of cost entries plus $2,000.00 of derived labor), so project 0 gets a $3,000.00 budget (overrun) and project 1 a $4,500.00 budget (warning band). The later attention-tier fixtures reuse this seeder unchanged.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Contractor emails used the reserved `.test` TLD**
- **Found during:** Task 3 (`_seed_rated_contractors`)
- **Issue:** `POST /api/v1/users/` returned 422 — `email-validator` rejects `.test` as "a special-use or reserved name", so the seeder could not create its two rated contractors and no labor could be derived.
- **Fix:** Introduced `_CONTRACTOR_EMAIL_DOMAIN = "portfolio-contractors.com"` (a named constant, with the WHY in a comment) and built emails as `portfolio-{uuid4().hex}@{_CONTRACTOR_EMAIL_DOMAIN}` so two tenants seeded in the same test can never collide on `uq_users_email`.
- **Files modified:** `backend/tests/test_phase_35_e2e.py`
- **Verification:** `pytest tests/test_phase_35_e2e.py -k seed_company_portfolio` went from 2 failed to 2 passed.
- **Committed in:** `a4e5b03` (Task 3 commit)

**2. [Rule 3 - Blocking] Task 1 needed a real test to satisfy its own acceptance criterion**
- **Found during:** Task 1
- **Issue:** The plan says Task 1 adds no test bodies, but its acceptance criterion requires `pytest --collect-only` to exit 0. pytest exits 5 ("no tests collected") on a body-less module, so the two statements cannot both hold.
- **Fix:** Added the two harness self-tests the plan's own `<objective>` calls for ("helpers plus self-verifying smoke tests against shipped endpoints") — `test_revenue_seeders_land_at_anchors_the_shipped_rollup_resolves` and `test_undated_approved_quote_keeps_a_null_approved_at`. Both exercise the genuinely new (not copied) helpers, so this adds proof rather than filler.
- **Files modified:** `backend/tests/test_phase_35_e2e.py`
- **Verification:** `pytest tests/test_phase_35_e2e.py --collect-only` exits 0 with 2 tests; both pass.
- **Committed in:** `10b3b9f` (Task 1 commit)

### Documentation Corrections

**3. Row-count figure in the seeder docstring**
- The plan's prescribed docstring claims "~5,000 financial rows at project_count=25". The specified shape actually produces ~2,250 rows (500 cost entries, 1,250 time entries, 50 invoices + 50 line items, 50 quotes + 50 line items, 125 budgets, 100 scopes, 50 jobs, 25 projects). The docstring states the accurate figure — an honest number matters more than matching plan prose, and 35-08's latency budget will be read off this docstring.

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking) + 1 documentation correction
**Impact on plan:** No scope creep. The bug fix was required for the seeder to work at all; the added Task 1 tests are exactly the self-verification the plan's objective asks for.

## Issues Encountered

**Shared test-database contention with parallel agents (environmental, unresolved by design).**

`backend/tests/conftest.py` truncates every table before each test, which needs an `AccessExclusiveLock` on the whole schema. That is fundamentally incompatible with two pytest processes sharing one database: while a sibling backend agent ran its suite against `contractorhub_test`, my runs failed in the **conftest `seed_two_tenants` fixture** with `asyncpg.exceptions.DeadlockDetectedError` (a register `INSERT INTO user_roles` deadlocking against a concurrent `TRUNCATE`) and, once a truncation was rolled back, `UniqueViolationError: uq_users_email`.

- Zero failures ever occurred inside a Phase 35 test body — every error was fixture setup.
- Isolating onto a private database was not possible: `appuser` has neither `rolcreatedb` nor `rolsuper`.
- Resolved by waiting for a clean window. The final uncontended run is **5 passed in 20.82s**, with the two seeder tests at 3.54s and 4.53s — far inside the plan's 60s ceiling. The 51.7s / 48.6s figures observed mid-contention were entirely lock waiting.
- **Not fixed, deliberately:** `conftest.py` is shared, out of this plan's scope, and owned by another agent this wave. Worth a future decision (per-worker test databases, or `pytest-xdist`-style DB templating) if parallel agent execution becomes routine.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Every later Phase 35 backend plan (35-05 through 35-08) can now add tests to this file with no new scaffolding: the helper set, the query counter and the portfolio seeder are all in place and green.
- 35-08 owns the two D-03 tests that consume this work (`test_company_rollup_query_count_is_constant_in_project_count`, `test_company_rollup_latency_budget`). At project_count=25 the seeder issues ~300 endpoint calls plus 6 bulk statements; the 2-project smoke test's 3.5s suggests that lands well inside a normal pytest run, but 35-08 should confirm on an uncontended database.
- The three financial endpoint URLs are declared but unused until 35-05/35-06/35-07 ship the endpoints. This is intentional forward declaration, documented in the file.
- **Carry-forward concern:** if plans keep executing in parallel against one Postgres, expect spurious red backend suites. Read the failing frame before debugging — a deadlock inside `seed_two_tenants` is contention, not a regression.

## Self-Check: PASSED

- `backend/tests/test_phase_35_e2e.py` exists on disk (834 lines, min_lines 200 satisfied)
- Commits `10b3b9f`, `f0ec4f7`, `a4e5b03` all present in `git log --all`
- must_haves artifact `contains: "def _count_sql_statements"` — present
- must_haves key_link `before_cursor_execute` on `engine.sync_engine` — present, detached via `event.remove` in a `finally`
- `pytest tests/test_phase_35_e2e.py -q` → 5 passed in 20.82s
- `ruff check . && ruff format --check .` → clean across all 306 backend files
- `git status --short backend/` → clean; no shipped test file was modified

---
*Phase: 35-web-financial-dashboard*
*Completed: 2026-07-29*
