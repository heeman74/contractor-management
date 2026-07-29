---
phase: 36-ai-profitability-analysis
plan: 09
subsystem: api
tags: [ai, fcm, rbac, dashboard-alerts, exactly-once, postgres, sqlalchemy]

# Dependency graph
requires:
  - phase: 36-08
    provides: "publish_findings returning PublishResult(published, qualifying_fingerprints) and PublishedFinding"
  - phase: 36-01
    provides: "ProfitabilityRepository.claim_alert / resolve_absent_fingerprints, AI_PROFITABILITY_ALERT_TYPE"
  - phase: 34-03
    provides: "the claim-first exactly-once alert precedent, _recipients_for and the fire-and-forget push shape"
provides:
  - "ProfitabilityService.analyze_company(company_id=..., target_date=...) — the whole nightly run for one company"
  - "Stale-fingerprint resolution keyed on what still QUALIFIES, never on what published (the D-06 keep-set)"
  - "Claim-first ai_profitability DashboardAlert writing with the locked AI_FINDING_PREFIX / SUGGESTED_ACTION_PREFIX frames"
  - "PUSH_TITLE_BY_BAND — one name per band for chip label, push title and alert severity"
  - "NotificationService.send_profitability_finding_notification"
  - "FCM dispatch to the live finance.view holder set with a str-only data payload"
affects: [36-10, scheduler wiring, mobile push handling]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Resolve-then-claim ordering inside one transaction so a worsening band resolves the prior band's row in the same run"
    - "Keep-set built from every qualifying candidate, so a transient AI failure can never resolve a live finding"
    - "Fire-and-forget FCM in a module-level task registry with add_done_callback(discard) and its own session"

key-files:
  created: []
  modified:
    - backend/app/features/finance/profitability_service.py
    - backend/app/features/notifications/service.py
    - backend/tests/test_phase_36_e2e.py
    - backend/tests/test_notification_service.py

key-decisions:
  - "analyze_company's keep-set is result.qualifying_fingerprints; the published-based variant is mutation-verified to break the transient-failure test"
  - "The lifecycle fixtures were re-balanced to start in the WARNING band (1,200 cost / 10,000 invoiced / 20,000 quoted = 6.0 points) because the shipped analyzable project is already critical on night one"
  - "The band worsens by ADDING COST, never by re-quoting: the invoice moves the job out of 'quote' status and the quote endpoint would 409"
  - "The push tail landed in Task 2 rather than Task 1 so each TDD commit is green on its own; the final analyze_company matches the plan exactly"
  - "_build_alert and _push_data are module-level pure builders beside _to_upsert, not methods — they need no session"
  - "dashboard_alert_id is written through the shipped BaseRepository.update rather than a new repository method"

patterns-established:
  - "Frame-string assertions read the prefix and then compare the remainder to the mocked AI string by reference — AI prose is never retyped in a test"
  - "A cleared-then-recurring condition is exercised by pausing and re-activating the project, which keeps the fingerprint identical and so proves the resolve-then-reinsert path rather than a band change"

requirements-completed: [FINAI-02]

# Metrics
duration: 26 min
completed: 2026-07-29
---

# Phase 36 Plan 09: Alert Lifecycle and FCM Dispatch Summary

**Exactly-once `ai_profitability` alerting: stale fingerprints resolve before the claim, each finding claims its alert atomically and writes the locked `AI finding — ` / `Suggested action: ` frames, and FCM goes only to the live `finance.view` holder set.**

## Performance

- **Duration:** 26 min
- **Started:** 2026-07-29T22:30:20Z
- **Completed:** 2026-07-29T22:56:32Z
- **Tasks:** 2 (both TDD: 4 commits)
- **Files modified:** 4

## Accomplishments

- `ProfitabilityService.analyze_company(company_id=..., target_date=...)` closes the nightly loop: publish → resolve → claim → alert → push, all inside the caller's transaction so a rollback un-claims every alert with it.
- **The D-06 correctness contract holds and is guarded.** The keep-set is `result.qualifying_fingerprints`, so a candidate dropped because its Claude call raised, its draft failed the length contract, or the nightly cap hit is never resolved. `test_transient_claude_failure_does_not_resolve_or_realert` was **mutation-verified**: swapping in the published-based keep-set fails exactly that test (the still-true finding resolves, night 3 inserts a fresh row and fires a second alert), and restoring it returns the suite to green.
- Resolution runs BEFORE the claim, so a condition worsening into a different band resolves the prior band's row in the *same* run and the new band's row inserts fresh with `alerted_at IS NULL` — keystone #2 asserts both halves.
- The AlertPanel entry is written entirely from the backend: `impact_text = AI_FINDING_PREFIX + alert_summary`, `remediation_text = SUGGESTED_ACTION_PREFIX + corrective_action`, `severity` identity-mapped from the band, and `days_behind` / `affected_scope_ids` / both rescheduling columns empty. `AlertPanel.tsx` was not touched.
- `send_profitability_finding_notification` ships as a sibling of the budget method (shared `_resolve_messaging` / `_dispatch_to_tokens`), and recipients come from `RbacRepository.user_ids_with_permission` — proven to follow a *new* `finance.view` grant with no code change.

## Task Commits

1. **Task 1 (RED): failing lifecycle tests** — `c9133a6` (test)
2. **Task 1 (GREEN): resolve stale fingerprints, claim-first alert emission** — `589c2df` (feat)
3. **Task 2 (RED): failing FCM dispatch tests** — `508a018` (test)
4. **Task 2 (GREEN): push to live finance.view holders** — `b6c67f3` (feat)

No REFACTOR commits were needed — both implementations landed clean under `ruff check` and `ruff format --check`.

## Files Created/Modified

- `backend/app/features/finance/profitability_service.py` — `analyze_company`, `_fire_findings`, `_fire_finding`, `_recipients_for`, `_schedule_profitability_pushes`, `_send_profitability_push_safe`, module-level `_build_alert` / `_push_data`, and the `AI_FINDING_PREFIX` / `SUGGESTED_ACTION_PREFIX` / `PUSH_TITLE_BY_BAND` / `_PROFITABILITY_PUSH_TASKS` constants.
- `backend/app/features/notifications/service.py` — `send_profitability_finding_notification`, placed beside the budget sibling.
- `backend/tests/test_phase_36_e2e.py` — two new sections (9 tests): the alert lifecycle and the FCM dispatch contract, plus the lifecycle fixtures (`_seed_lifecycle_project`, `_worsen_into_critical_band`, `_pause_project`, `_analyze_company`, `_all_findings`, `_ai_profitability_alerts`) and the RBAC/push harness (`_seed_role_holders`, `_finance_view_holders`, `_grant_finance_view`, `_patched_profitability_push`, `_flush_background_pushes`).
- `backend/tests/test_notification_service.py` — 2 tests exercising the new notification method's own body (per-token dispatch, graceful skip without Firebase).

## Decisions Made

**1. The lifecycle fixtures had to be re-balanced, not reused.** The shipped `_seed_analyzable_project` (5,000 cost / 6,000 invoiced / 10,000 quoted) is a 33.3-point gap — already `critical` on night one, with nowhere to escalate to. The new fixture bills 10,000 of a 20,000 quote against 1,200 of cost: 88.0% billed against 94.0% quote-implied is exactly **6.0 points** (warning). Adding 1,800 more cost gives 70.0% against 85.0% = **15.0 points** (critical). Both land on exact one-decimal values, so no rounding boundary is being straddled, and the margin stays positive at both levels so `negative_margin` cannot pre-empt the comparison.

**2. The band worsens by adding cost, never by re-quoting.** `QuoteService.create_quote` rejects a job that is not in `quote` status, and `_create_invoice` marks the job complete — so a second approved quote at the same anchor would 409. Cost is the only lever that moves the gap without fighting the job status machine.

**3. The clear-and-recur test pauses the project rather than billing the gap away.** Billing up to the quote amount would clear the condition but a later recurrence would carry a *different* fingerprint, which re-alerts through the band-change path already covered by keystone #2. Pausing (`active → on_hold → active`) keeps the fingerprint byte-identical, so the second alert can only come from resolve-then-reinsert — which is the D-06 mechanism actually under test.

**4. `_build_alert` and `_push_data` are module-level pure builders.** Both need no session and no `self`; the plan sketched `self._build_alert(...)` but the file already keeps its builders (`_to_upsert`, `_to_draft`, `_build_payload`) at module level, and a pure function is the honest signature.

**5. `dashboard_alert_id` is written through `BaseRepository.update`.** The plan's `files_modified` deliberately excludes `profitability_repository.py`, and the shipped generic partial-update is exactly the operation needed — no new repository method, no raw `db.get` in the service.

**6. A raised transport error consumes no D-05 retry.** `test_transient_claude_failure_does_not_resolve_or_realert` asserts exactly one Claude call on the failing night, with the reason in-file: the grounding retry exists for *validation* failures, and `gather_with_concurrency` isolates a raised call into a `None` draft on the first attempt.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added unit tests for the new notification method's own body**
- **Found during:** Task 2 (FCM dispatch)
- **Issue:** The e2e tests patch `NotificationService.send_profitability_finding_notification`, so the method body — token lookup, empty-recipient guard, dispatch loop, credential-free degradation — would have shipped with **zero** executed coverage. CLAUDE.md requires a test for every new service function, and the budget sibling has the same gap (no test in `test_notification_service.py`), so copying the precedent would have propagated it.
- **Fix:** Two tests in `backend/tests/test_notification_service.py` mirroring the shipped `test_send_job_notification_success` / `test_no_notification_when_fcm_not_configured` shape: one asserts every recipient's token receives the same title/body/data, the other asserts `get_tokens_for_users` is never awaited without Firebase credentials.
- **Files modified:** `backend/tests/test_notification_service.py`
- **Verification:** Both RED before the method existed; `pytest tests/test_notification_service.py -q` → 9 passed.
- **Committed in:** `508a018` (RED) / `b6c67f3` (GREEN)

### Sequencing adjustments (no behavior difference)

**2. The push tail landed in Task 2, not Task 1.** The plan's Task-1 action block showed the finished `analyze_company` including `_recipients_for` and `_schedule_profitability_pushes`, but Task 1's `<behavior>` says nothing about pushes and Task 2 lists the same file again. Implementing the tail in Task 2 keeps each TDD commit independently green (Task 1's tests cannot patch a method that does not exist yet). The final `analyze_company` is byte-for-byte the plan's version.

**3. `if fired:` guards the recipient lookup.** Mirrors `evaluate_budget`: on a quiet night nothing alerted, so the permission query is skipped entirely. Recipients are still resolved in the request session before any task is scheduled, which is the behavior the plan pins.

**4. Added `test_push_title_map_covers_both_bands`.** Not requested, but `PUSH_TITLE_BY_BAND` is the single source for the chip label, the push title and the alert severity; pinning both entries means a rename cannot silently give one band two names. It also makes the `"Margin warning"` / `"Margin critical"` acceptance criterion a runtime assertion rather than a grep.

---

**Total deviations:** 1 auto-fixed (1 missing critical) + 3 sequencing/coverage adjustments
**Impact on plan:** No scope creep. Every plan artifact, behavior and acceptance criterion is delivered; the additions are test coverage the CLAUDE.md testing rules require.

## Issues Encountered

- **One RED assertion was wrong, not the implementation.** The first draft of `test_transient_claude_failure_does_not_resolve_or_realert` expected `GROUNDING_RETRY_LIMIT + 1` Claude calls on the failing night. A raised transport error propagates out of `_draft_for` before the retry loop can iterate, so there is exactly one call. Corrected in the test with an in-file explanation of why.
- **Pre-existing dirty artifacts** (`web/playwright-report/`) were left unstaged throughout, per the execution brief.

## Verification Evidence

- `pytest tests/test_phase_36_e2e.py -q` → **37 passed** (28 shipped + 9 new)
- `pytest tests/test_phase_34_e2e.py tests/test_notification_service.py -q` → **76 passed** (the budget push path is unaffected)
- `pytest tests/test_phase_34_e2e.py tests/test_phase_36_e2e.py tests/test_notification_service.py tests/unit -q` → **342 passed**
- `ruff check .` → clean · `ruff format --check .` → 319 files already formatted
- **Mutation check (D-06 keep-set):** replacing `resolve_absent_fingerprints(result.qualifying_fingerprints)` with the published-based keep-set → `1 failed, 5 passed`; restored → `6 passed`.
- **Acceptance greps:** all 11 Task-1 and all 8 Task-2 criteria verified, including the two negative greps (`! grep -q "resolve_absent_fingerprints(\[p.fingerprint"` and `! grep -qE '"owner"|"project_manager"'` against the service).
- **`AlertPanel.tsx` unmodified:** `git diff --name-only c9133a6~1..HEAD` returns only the four backend files.

## Known Stubs

None. Every symbol this plan added is wired and exercised by a test.

## User Setup Required

None - no external service configuration required. FCM stays optional: without `GOOGLE_APPLICATION_CREDENTIALS` the push degrades silently and the nightly run is unaffected.

## Next Phase Readiness

- **Ready for 36-10.** `analyze_company(company_id=..., target_date=...)` matches the `_run_for_all_companies` scheduler contract exactly and never commits, so the scheduler owns the transaction as it does for `sweep_budgets`.
- **For the plan that registers the job:** the fire-and-forget push tasks outlive the request. `_send_profitability_push_safe` calls `set_current_tenant_id` and opens its own session precisely because the scheduler's session is gone by then.
- **No blockers.** The pre-existing Phase 35 concern about parallel pytest processes sharing `contractorhub_test` still applies — this plan was executed as the sole agent and every suite ran green sequentially.

---
*Phase: 36-ai-profitability-analysis*
*Completed: 2026-07-29*

## Self-Check: PASSED

All 4 modified files and the SUMMARY exist on disk; all 4 task commits (`c9133a6`, `589c2df`, `508a018`, `b6c67f3`) are present in the repository history.
