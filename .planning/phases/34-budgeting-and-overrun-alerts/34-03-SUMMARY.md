---
phase: 34-budgeting-and-overrun-alerts
plan: 03
subsystem: finance
tags: [sqlalchemy, fastapi, fcm, firebase, rbac, budgets, dashboard-alerts, asyncio]

# Dependency graph
requires:
  - phase: 34-budgeting-and-overrun-alerts (34-01)
    provides: budget_math (crossed_thresholds, budget_alert_text, push_title_for), alert_types constants, warning_fired_at/overrun_fired_at columns
  - phase: 34-budgeting-and-overrun-alerts (34-02)
    provides: BudgetRepository/BudgetService CRUD, set_total D-03 re-arm, FinanceService.project_spend/trade_scope_spend single spend definition
  - phase: 30-financial-schema-foundation-and-rbac-audit
    provides: FINANCIAL_ALERT_TYPES permission filter, finance.* RBAC keys, editable role matrix
  - phase: 24-gc-inspection-workflow
    provides: NotificationService FCM dispatch plumbing (_resolve_messaging, _dispatch_to_tokens)
provides:
  - BudgetRepository.claim_threshold — atomic UPDATE ... WHERE fired_at IS NULL RETURNING id exactly-once claim per threshold
  - BudgetRepository.alert_context — one-query project/scope name lookup; None when the anchor is gone/soft-deleted
  - BudgetService.evaluate_budget / evaluate_for_project / evaluate_for_trade_scope returning FiredBudgetAlert hand-offs
  - DashboardAlert rows with locked UI-SPEC copy (budget_warning=warning, budget_overrun=critical)
  - RbacRepository.user_ids_with_permission — live-matrix permission-holder query (no role literals)
  - NotificationRepository.get_tokens_for_users + NotificationService.send_budget_alert_notification
  - Fire-and-forget FCM push per fired alert with own-session background task (checklists pattern)
affects: [34-04 nightly sweep, 34-06 cost-mutation hooks, 34-08 quote-revision deltas, 35-financial-dashboard, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Exactly-once alert firing: atomic claim-first UPDATE (Phase 25 mark_invoiced precedent) + ORM expire after raw-SQL claim"
    - "Resolve alert context BEFORE claiming so a vanished anchor never burns a claim"
    - "Push recipients resolved in the request session before scheduling; background task gets primitives + fresh session only"

key-files:
  created: []
  modified:
    - backend/app/features/finance/budget_repository.py
    - backend/app/features/finance/budget_service.py
    - backend/app/features/rbac/repository.py
    - backend/app/features/notifications/repository.py
    - backend/app/features/notifications/service.py
    - backend/tests/test_phase_34_e2e.py

key-decisions:
  - "claim_threshold keeps the plan's budget_id signature and expires the identity-mapped Budget via db.get (identity-map hit, no extra query in the evaluation path)"
  - "Push scheduling lives at the tail of evaluate_budget only, so every future trigger (mutation hook, sweep, quote delta) inherits FCM delivery without repeating dispatch logic"
  - "async_session_factory imported lazily inside _send_budget_push_safe so the test-suite NullPool factory monkeypatch is honored (checklists precedent)"

patterns-established:
  - "FiredBudgetAlert dataclass: the evaluation->notification hand-off carries only primitives (ids, title, body)"
  - "_roles_granting(permission_key, role_map): permission->roles resolution mirrors effective_permissions exactly, never role-name literals"

requirements-completed: [BUDG-03]

# Metrics
duration: 40min
completed: 2026-07-28
---

# Phase 34 Plan 03: Alert Evaluation Engine and FCM Targeting Summary

**Exactly-once 80%/100% budget alerts: atomic threshold claims writing locked-copy dashboard alerts, plus fire-and-forget FCM pushes targeted at live finance.view holders**

## Performance

- **Duration:** 40 min
- **Started:** 2026-07-28T06:02:40Z
- **Completed:** 2026-07-28T06:42:46Z
- **Tasks:** 3 (2 TDD)
- **Files modified:** 6

## Accomplishments

- Each threshold crossing produces exactly one dashboard alert — proven under a genuine two-session race (`asyncio.gather` over independent `async_session_factory()` transactions, each committing) where exactly one evaluator claims and one alert row exists
- Alert copy is byte-identical to the UI-SPEC templates ("Riverside Remodel — Plumbing scope has spent $8,200 of its $10,000 budget (82%)." asserted verbatim), severity warning/critical by tier, re-arm on raise and D-10 below-spend honesty both covered
- FCM recipients derive from the live RBAC matrix: owner + PM targeted, contractor/admin never; revoking finance.view from project_manager in the matrix immediately drops PMs from recipients
- Push title/body/data locked: body byte-identical to impact_text, all data values strings with `""` for a missing scope; a raising or credential-less send never breaks the evaluating transaction
- 13 alert tests green; phase-34 file 33 tests green; phase 24 FCM + phase 26 dashboard regressions green

## Task Commits

Each task was committed atomically:

1. **Task 1: Atomic threshold claim + alert context lookup** - `a68231f` (feat)
2. **Task 2: BudgetService.evaluate_* writes the dashboard alert** - `06bf5b0` (test RED), `239abb6` (feat GREEN)
3. **Task 3: finance.view targeting + FCM push** - `09e8090` (test RED), `efde3aa` (feat GREEN)

## Files Created/Modified

- `backend/app/features/finance/budget_repository.py` - BudgetAlertContext, per-threshold `_CLAIM_SQL`, claim_threshold with post-claim ORM expire, alert_context single-query anchor lookup
- `backend/app/features/finance/budget_service.py` - evaluate_budget/evaluate_for_project/evaluate_for_trade_scope, FiredBudgetAlert, DashboardAlert persistence, `_push_data`, `_recipients_for`, `_schedule_budget_pushes`, `_send_budget_push_safe`
- `backend/app/features/rbac/repository.py` - user_ids_with_permission + `_roles_granting` (effective_permissions resolution rule, one DISTINCT join query)
- `backend/app/features/notifications/repository.py` - get_tokens_for_users (one IN query)
- `backend/app/features/notifications/service.py` - send_budget_alert_notification (graceful skip, never raises)
- `backend/tests/test_phase_34_e2e.py` - 13 `alerts` tests: locked copy, once/dedup, double fire, re-arm, below-spend, concurrent race, soft-deleted anchor, dashboard visibility, push targeting/revocation/payload/failure/no-creds

## Decisions Made

- `claim_threshold` keeps the planned `budget_id` signature; the required post-claim `db.expire(budget, ...)` resolves the instance through `db.get` (identity-map hit for the evaluation path, so no extra query in practice)
- Push dispatch is wired once at the tail of `evaluate_budget` — evaluate_for_project/evaluate_for_trade_scope and every future trigger inherit it, per the plan's "one place" rule
- `async_session_factory`, `set_current_tenant_id` and `NotificationService` are imported inside `_send_budget_push_safe` (checklists precedent) — a module-level factory import would bind the pre-monkeypatch factory under the test suite's NullPool swap

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Task 1 acceptance grep counted a docstring mention of the claim SQL**
- **Found during:** Task 1 (verification)
- **Issue:** The claim_threshold docstring quoted "RETURNING id", making `grep -c "RETURNING id"` return 3 instead of the required exactly-2 (the two `_CLAIM_SQL` statements)
- **Fix:** Reworded the docstring ("returning the id"); SQL statements untouched
- **Files modified:** backend/app/features/finance/budget_repository.py
- **Verification:** `grep -c "RETURNING id"` == 2; ruff clean
- **Committed in:** a68231f (Task 1 commit)

**2. [Rule 1 - Bug] Revocation test seeded the budget after revoking finance.manage**
- **Found during:** Task 3 (GREEN phase)
- **Issue:** The live-matrix revocation test stripped project_manager's finance.* keys before `_seed_scope_budget_with_spend`, whose PM-token budget POST then 403'd
- **Fix:** Reordered the test: seed budget and spend first, revoke the matrix, then evaluate
- **Files modified:** backend/tests/test_phase_34_e2e.py
- **Verification:** test_alerts_push_respects_live_matrix_revocation passes
- **Committed in:** efde3aa (Task 3 commit)

**3. [Rule 1 - Bug] Pre-existing docstrings tripped the no-db.commit acceptance grep**
- **Found during:** Task 2 (verification)
- **Issue:** budget_service docstrings (one from 34-02) contained the literal "db.commit()", violating the acceptance criterion that `grep "db.commit()"` return nothing in the file
- **Fix:** Reworded both docstrings to "Never commits"; no code change
- **Files modified:** backend/app/features/finance/budget_service.py
- **Verification:** grep returns nothing; behavior unchanged
- **Committed in:** 239abb6 (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (3 bugs — one test-ordering fix, two doc-wording fixes for acceptance greps)
**Impact on plan:** None on behavior or scope; all planned contracts shipped exactly as specified.

## Issues Encountered

- The no-credentials RED test passed trivially before push wiring existed (evaluation already succeeded without dispatch); it became meaningful once `send_budget_alert_notification` was wired into the real path. The four behavior-bearing RED tests failed as required in both TDD tasks.

## Authentication Gates

None — FCM is patched at the service layer per the Phase 24 precedent; no live Firebase credentials needed.

## Known Stubs

None — evaluation, alert persistence and push dispatch are wired end to end. The triggers that will call `evaluate_*` automatically (cost-mutation hooks, nightly sweep, quote-revision deltas) are later Phase 34 plans by design, not stubs in this plan's files.

## User Setup Required

None - no external service configuration required. Live pushes additionally need `GOOGLE_APPLICATION_CREDENTIALS`, which the sender already skips gracefully without (shipped Phase 24 behavior).

## Next Phase Readiness

- 34-06 (cost-mutation hooks) can call `evaluate_for_project`/`evaluate_for_trade_scope` after flush and inherit alerts + push for free
- The nightly sweep plan can iterate `BudgetRepository.list_active` and call `evaluate_budget`; the atomic claim makes the sweep idempotent by construction
- 34-08 (quote deltas) re-arms via `set_total` then evaluates — both single-sourced already

---
*Phase: 34-budgeting-and-overrun-alerts*
*Completed: 2026-07-28*

## Self-Check: PASSED

All 6 modified files and the SUMMARY exist on disk; all five task commits (a68231f, 06bf5b0, 239abb6, 09e8090, efde3aa) present in git history. Full backend suite: 779 passed, 1 skipped.
