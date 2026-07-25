---
phase: 30-financial-schema-foundation-and-rbac-audit
plan: 04
subsystem: testing
tags: [pytest, rls, rbac, postgresql, sqlalchemy, finance]

# Dependency graph
requires:
  - phase: 30-01
    provides: finance.* permission catalog, _FINANCE_ONLY_KEYS admin exclusion, DEFAULT_ROLE_PERMISSIONS PM/owner grants
  - phase: 30-02
    provides: migration 0032 (5 finance tables + RLS + category seed + PM backfill), finance ORM models
  - phase: 30-03
    provides: finance_scrub.FINANCE_FIELD_NAMES helper, dashboard.service.FINANCIAL_ALERT_TYPES filter
provides:
  - Integration proof that migration 0032's PM backfill actually reaches an existing (pre-migration) company and is idempotent
  - Integration proof of 4-category-per-company seed + idempotent re-seed
  - RLS isolation proof for cost_entries and budgets (new financial tables)
  - Enforced leak tripwires for GET /reports/dashboard, GET /dashboard/alerts, and the two AI dict-builders
affects: [31-cost-category-crud, 32-actual-cost-capture, 34-budgeting, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Direct raw-SQL replay of a migration's guarded UPDATE/INSERT (via async_session_factory + SET LOCAL) to integration-test migration effects without re-running Alembic"
    - "Recursive dict-key collection helper for schema-leak tripwire assertions"
    - "monkeypatch.setattr on a module-level frozenset constant to test currently-inert filter logic"

key-files:
  created: []
  modified:
    - backend/tests/test_phase_30_e2e.py

key-decisions:
  - "Simulated a pre-migration company by inserting a bare companies row + company_role_permissions rows directly (bypassing RbacRepository), since seed_two_tenants companies are created after migration 0032 already ran and get the new default matrix"
  - "cost_categories re-seed test scopes the migration's multi-company INSERT...SELECT to a single company via SET LOCAL + bind param, since RLS is already enabled+forced on the table post-migration (unlike the pre-RLS migration run)"
  - "No CHECK constraint enforces CostEntry/Budget job_id/trade_scope_id XOR at the DB level (only the Pydantic schema layer does) — RLS isolation test leaves both anchors NULL, which is valid at the DB layer"
  - "dashboard_alerts.alert_type has no real financial value yet — monkeypatched FINANCIAL_ALERT_TYPES to treat the existing allowed 'dependency_risk' type as a stand-in financial type, documented inline, per the plan's explicit guidance"
  - "AI dict-builder leak test calls ChecklistService._build_user_content_from_dict / DashboardService._build_slip_content_from_dict via Cls.__new__(Cls) — both are pure functions of the input dict, no service state needed"

requirements-completed: [FINSEC-01, FINSEC-02, FINSEC-03, FINSEC-04]

# Metrics
duration: ~40min
completed: 2026-07-24
---

# Phase 30 Plan 04: Phase-gate Integration Tests Summary

**Extended backend/tests/test_phase_30_e2e.py with 6 new integration tests proving migration 0032's PM backfill/category-seed effects and RLS isolation, plus 3 enforced finance-leak tripwires on reports/alerts/AI-context surfaces — full 611-test backend suite green.**

## Performance

- **Duration:** ~40 min (includes a 12.5 min full-suite regression run)
- **Tasks:** 2
- **Files modified:** 1 (backend/tests/test_phase_30_e2e.py)

## Accomplishments

- Proved migration 0032's guarded `UPDATE company_role_permissions ... WHERE role = 'project_manager' AND NOT (permissions @> '["finance.view"]')` actually reaches an existing (simulated pre-migration) company, leaves the admin row byte-for-byte unchanged, and is idempotent on re-run.
- Proved every company ends up with exactly 4 `is_system` cost categories (labor/materials/subcontractor/other) and the `ON CONFLICT (company_id, name) DO NOTHING` seed is idempotent.
- Proved RLS isolation on the two new heavily-referenced financial tables (`cost_entries`, `budgets`) — tenant B cannot read tenant A's rows.
- Converted the D-06 "reports response has no finance fields" and FINSEC-04 "AI context has no finance fields" guarantees from manual inspection into enforced pytest assertions using `FINANCE_FIELD_NAMES`.
- Proved the (currently inert) `FINANCIAL_ALERT_TYPES` dashboard-alert filter actually works once populated, via `monkeypatch`.
- Ran the full backend regression suite (611 passed, 1 skipped, 0 failed) confirming the 51-key permission catalog and the `get_alerts(has_finance_view=...)` signature change introduced no regressions, including `tests/integration/test_role_permissions.py`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Migration-effect tests — PM backfill, category seed + idempotency, RLS isolation** - `7a1cdfa` (test)
2. **Task 2: Legacy-surface leak tripwires — reports, dashboard-alert filter, AI context** - `0a840c4` (test)

**Plan metadata:** (this commit) `docs(30-04): complete phase-gate integration tests plan`

## Files Created/Modified

- `backend/tests/test_phase_30_e2e.py` - Extended with 6 new async test functions (existing_company_backfilled, cost_categories_seeded, cost_entry_rls_isolation, reports_dashboard_leaks_no_finance_fields, dashboard_alerts_filtered_by_finance_permission, ai_context_builders_leak_no_finance_fields) plus small raw-SQL/session helpers, closing out the Phase 30 gate.

## Decisions Made

- Pre-migration company simulation uses raw SQL directly against `companies`/`company_role_permissions` rather than the ORM's `RbacRepository`, since the repository always seeds the *current* (post-migration) `DEFAULT_ROLE_PERMISSIONS`, which already includes finance keys for `project_manager`.
- The cost-category re-seed test intentionally scopes the migration's global `INSERT ... SELECT FROM companies` to a single company (bind param + `SET LOCAL`) because the table now carries `FORCE ROW LEVEL SECURITY` post-migration — the original multi-tenant unscoped INSERT only worked in the migration because it ran *before* `ENABLE ROW LEVEL SECURITY`.
- Used the existing allowed `dependency_risk` alert type as a documented stand-in "financial" type when monkeypatching `FINANCIAL_ALERT_TYPES`, since no real financial alert type exists until Phase 36 and `dashboard_alerts.alert_type` is DB-CHECK-constrained to three fixed values.

## Deviations from Plan

None - plan executed exactly as written. (Two small mechanical fixes were made without deviating from the plan's intent: the request path for project creation needed a trailing slash (`/api/v1/projects/`) to avoid a 307 redirect losing the POST body, and `ruff format` reflowed a few chained `.scalars().all()` expressions — both caught immediately by the automated verify step and corrected before commit.)

## Issues Encountered

None beyond the two mechanical fixes noted above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 30 (financial-schema-foundation-and-rbac-audit) is now fully gated: FINSEC-01 through FINSEC-04 all have enforced automated coverage, the 5 finance tables exist with RLS, and the finance.* permission catalog is proven end-to-end (defaults, admin exclusion, owner override, migration backfill). Phase 31 (cost-category CRUD) and later phases (32 actual-cost capture, 34 budgeting, 36 AI profitability) can build directly on this schema/RBAC foundation without re-verifying it.

No blockers carried forward from this plan.

---
*Phase: 30-financial-schema-foundation-and-rbac-audit*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: backend/tests/test_phase_30_e2e.py
- FOUND: .planning/phases/30-financial-schema-foundation-and-rbac-audit/30-04-SUMMARY.md
- FOUND: 7a1cdfa (Task 1 commit)
- FOUND: 0a840c4 (Task 2 commit)
