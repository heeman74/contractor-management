---
phase: 36-ai-profitability-analysis
plan: 01
subsystem: database
tags: [postgres, alembic, sqlalchemy, rls, upsert, finance, ai]

# Dependency graph
requires:
  - phase: 30-financial-schema-and-rbac
    provides: finance.* permission keys, FINANCIAL_ALERT_TYPES leak filter, alert_types.py single source
  - phase: 34-budget-tracking-and-alerts
    provides: claim-first exactly-once alert pattern, dashboard_alerts alert_type CHECK shape (migration 0035)
provides:
  - ai_profitability_findings table with FORCE RLS, appuser grant and the open-fingerprint partial unique index
  - three DB length CHECKs (alert_summary/corrective_action 280, narrative 600) — the DB half of the UI-SPEC text contract
  - ai_profitability registered in all THREE alert-type literals, so the Phase 30 finance.view filter gates AI findings for free
  - ProfitabilityRepository (upsert_finding / claim_alert / resolve_absent_fingerprints / latest_open_for_project) + FindingUpsert
  - backend/tests/test_phase_36_e2e.py with the shared Phase 36 helper set every later plan reuses
affects: [36-02, 36-03, 36-04, 36-05, 36-06, 36-07, 36-08, 36-09, 36-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Open-row partial unique index as the upsert arbiter: (company_id, fingerprint) WHERE deleted_at IS NULL AND resolved_at IS NULL"
    - "Resolve-then-reinsert lifecycle (D-06): resolving a fingerprint frees the arbiter so a recurrence inserts a fresh, unalerted row"
    - "Alert-state columns excluded from the ON CONFLICT set_ so a restatement cannot re-arm an alert or rewrite a discovery date"

key-files:
  created:
    - backend/migrations/versions/0036_ai_profitability_findings.py
    - backend/app/features/finance/profitability_models.py
    - backend/app/features/finance/profitability_repository.py
    - backend/tests/test_phase_36_e2e.py
  modified:
    - backend/app/features/dashboard/alert_types.py
    - backend/app/features/dashboard/models.py
    - backend/tests/conftest.py

key-decisions:
  - "severity_band is excluded from the upsert set_ alongside alerted_at and found_on — the band is part of the fingerprint, so a band change is a different finding that must resolve-and-reinsert (D-06), never mutate in place"
  - "claim_alert mirrors BudgetRepository.claim_threshold including the post-claim ORM expire, so a later in-session read cannot serve the stale pre-claim NULL and double-alert"
  - "The Pitfall 3 drift guard reads the CheckConstraint expression off DashboardAlert.__table__ rather than relying on an insert — a SQLAlchemy CheckConstraint is DDL-only and is never evaluated on flush, so an insert alone proves the migration's value list and nothing about models.py"
  - "resolve_absent_fingerprints uses a bare open-row WHERE when the keep-set is empty — NOT IN () is invalid SQL and an empty keep-set is the normal 'nothing found tonight' case"

patterns-established:
  - "FindingUpsert frozen dataclass: one argument instead of twelve, per the CLAUDE.md 3-arg ceiling"
  - "_tenant_repository async context manager in the test file: repository inside a SET LOCAL session, committed by the caller — the scheduler-path convention"

requirements-completed: [FINAI-01, FINAI-02]

# Metrics
duration: 20min
completed: 2026-07-29
---

# Phase 36 Plan 01: AI Profitability Persistence Floor Summary

**`ai_profitability_findings` table with FORCE RLS and an open-fingerprint partial unique index, backing a ProfitabilityRepository whose nightly upsert restates finding text without ever re-arming its alert.**

## Performance

- **Duration:** 20 min (plus ~6 min of cross-suite regression runs)
- **Started:** 2026-07-29T18:30:18Z
- **Completed:** 2026-07-29T18:50:00Z
- **Tasks:** 3
- **Files modified:** 7 (4 created, 3 modified)

## Accomplishments

- Migration 0036 ships the findings table with FORCE RLS, the `appuser` grant, four indexes and five named CHECK constraints — verified applied AND reversed cleanly, then applied to the test, dev and Docker databases.
- `ai_profitability` is now spelled in all three places it independently exists (migration SQL, `alert_types.py`, `dashboard/models.py`), and its membership in `FINANCIAL_ALERT_TYPES` means the Phase 30 permission filter at `dashboard/service.py:753-755` gates AI findings with no further code.
- `ProfitabilityRepository` implements the three lifecycle guarantees every later Phase 36 plan depends on: idempotent nightly upsert, claim-first exactly-once alerting, and the D-06 resolve-then-recur cycle that lets a worsening severity band re-fire.
- `backend/tests/test_phase_36_e2e.py` ships with the full shared helper set (copied, not imported) plus six green tests.

## Task Commits

1. **Task 1: Migration 0036 + the three alert-type literals + ORM model** — `6b3fa6e` (feat)
2. **Task 2: Test harness + ProfitabilityRepository** — `689b0e9` (test, RED) → `e506458` (feat, GREEN)
3. **Task 3: Schema-level integration tests** — `68aaf4e` (test)

_Task 2 was a TDD task: the RED commit's test file fails to import, the GREEN commit makes all three pass._

## Files Created/Modified

- `backend/migrations/versions/0036_ai_profitability_findings.py` — findings table, RLS block, partial unique index, alert_type CHECK expansion
- `backend/app/features/finance/profitability_models.py` — `AIProfitabilityFinding` + the three text-length constants the service half will reuse
- `backend/app/features/finance/profitability_repository.py` — `ProfitabilityRepository` and the `FindingUpsert` frozen dataclass
- `backend/tests/test_phase_36_e2e.py` — Phase 36 helper set + six tests
- `backend/app/features/dashboard/alert_types.py` — `AI_PROFITABILITY_ALERT_TYPE`, added to `FINANCIAL_ALERT_TYPES`
- `backend/app/features/dashboard/models.py` — third alert_type literal extended
- `backend/tests/conftest.py` — `ai_profitability_findings` registered in the `clean_tables` TRUNCATE list

## Decisions Made

- **`severity_band` stays out of the upsert `set_`.** The band is encoded in the fingerprint, so a band change is a *different* finding. Letting it mutate in place would silently upgrade a warning to critical without ever alerting anyone — the exact failure D-06's resolve-then-reinsert exists to prevent.
- **`claim_alert` keeps the Phase 34 post-claim ORM expire.** Without it, a caller that upserts and then claims in one session would read `alerted_at IS NULL` from the identity map afterwards and could publish a second alert. This mirrors `BudgetRepository._expire_fired_state` rather than inventing a second convention.
- **No `open_finding_count` method.** The D-10 nightly cap counts findings published tonight (36-08 counts them in-memory), not open rows; a method with no caller is dead code.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Registered `ai_profitability_findings` in the conftest TRUNCATE list**
- **Found during:** Task 2 (GREEN run)
- **Issue:** `clean_tables` lists every table explicitly with no `CASCADE`. PostgreSQL refuses to truncate `projects` while an unlisted table holds an FK to it, so *every* backend test errored during setup with `cannot truncate a table referenced in a foreign key constraint`.
- **Fix:** Added `ai_profitability_findings` to the TRUNCATE list ahead of `projects` (it references both `projects` and `dashboard_alerts`), with a comment naming both parents.
- **Files modified:** `backend/tests/conftest.py`
- **Verification:** The three repository tests went from collection-time error to passing; 178 tests across the phase 26/30/31/32/33/34/35/36 suites are green.
- **Committed in:** `e506458` (Task 2 GREEN commit)

**2. [Rule 1 - Bug] Strengthened the Pitfall 3 drift guard so it actually detects drift**
- **Found during:** Task 3
- **Issue:** The plan specified proving the `models.py` CheckConstraint literal by constructing a `DashboardAlert` through the ORM and flushing it. That does not work: a SQLAlchemy `CheckConstraint` is DDL-only and is never evaluated on flush, and `conftest` builds the schema with `alembic upgrade head` rather than `metadata.create_all`. The insert therefore proves the *migration's* value list and says nothing about `models.py` — the test would have passed with `models.py` left un-updated, which is precisely the drift RESEARCH Pitfall 3 warns about.
- **Fix:** Kept the ORM round-trip (it is the migration-half proof) and added `_orm_alert_type_check_sql()`, which reads the constraint expression off `DashboardAlert.__table__` and asserts the value is present. The test now covers all three literals: migration SQL (insert succeeds), `models.py` (metadata read), `alert_types.py` (`FINANCIAL_ALERT_TYPES` membership).
- **Files modified:** `backend/tests/test_phase_36_e2e.py`
- **Verification:** Break-it-once — removing `'ai_profitability'` from the `models.py` CheckConstraint literal makes `test_ai_profitability_alert_type_accepted_by_orm` fail; restoring it makes it pass. The as-specified version passes in both states.
- **Committed in:** `68aaf4e` (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both were necessary for correctness. Deviation 1 unblocked the entire backend suite; deviation 2 turned a test that only claimed to guard Pitfall 3 into one that does. No scope creep — no new files, no new dependencies.

## Issues Encountered

- **`docker compose up migrate` reported success without running the migration.** The `migrate` service builds from `./backend`, so its cached image did not contain the new migration file and the container exited 0 at revision 0035. Resolved with `docker compose up migrate --build`; confirmed the Docker DB is at `0036_ai_profitability_findings` and the table exists with its policy, indexes and constraints. Worth remembering for every future migration in this repo — a bare `docker compose up migrate` can silently no-op.
- **`alembic` needs an explicit `DATABASE_URL`.** Running it from the venv without one fails with `password authentication failed for user "placeholder"`. Exported the URL per target database (test / dev) for the upgrade-downgrade-upgrade verification.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The persistence floor is complete and every later Phase 36 plan can write through `ProfitabilityRepository` and extend `test_phase_36_e2e.py` (helper set already in place).
- `FINAI-01`'s detection/scheduling half is **not** delivered here — this plan ships only the storage and alert-type registration it depends on. The nightly analysis, the AI drafting and the D-10 publish cap land in 36-08.
- `test_alert_summary_db_length_check` deliberately owns the DATABASE half of the length contract; 36-08 must use the distinct name `test_over_length_draft_is_rejected_not_truncated` for the service half or ruff F811 will silently shadow one of them.
- Regression: 178 tests green across the phase 26/30/31/32/33/34/35/36 suites; `ruff check` and `ruff format --check` clean across 312 files.

## Self-Check: PASSED

All 4 created files and 3 modified files verified present on disk. All 4 task commits
(`6b3fa6e`, `689b0e9`, `e506458`, `68aaf4e`) verified in git history.

---
*Phase: 36-ai-profitability-analysis*
*Completed: 2026-07-29*
