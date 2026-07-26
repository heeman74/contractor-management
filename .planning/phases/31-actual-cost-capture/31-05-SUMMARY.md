---
phase: 31-actual-cost-capture
plan: 05
subsystem: mobile
tags: [flutter, riverpod, drift, image_picker, rbac, offline-first, finance]

# Dependency graph
requires:
  - phase: 31-actual-cost-capture
    plan: 04
    provides: "Drift v16 cost_entries/cost_receipts tables, CostEntryDao/CostReceiptDao, CostEntrySyncHandler, CostReceiptUploadService, on-demand FinanceRepository"
provides:
  - "Riverpod finance.view/finance.manage permission provider backed by GET /me/permissions (first mobile fine-grained permission gate — previously mobile only had role-based checks)"
  - "AddCostSheet: offline cost-entry bottom sheet with amount/category/date/vendor/note + camera+gallery receipt capture (ImagePicker)"
  - "CostListSection/CostEntryCard: permission-gated cost list UI with authenticated receipt thumbnails, reused across job/trade-scope/project screens"
  - "Costs sections wired into job detail (Details tab), trade-scope detail, and project detail (read-only rollup) screens, all finance.view gated"
affects: [32-labor-cost-capture, 33-profit-margin-tracking, 34-budgeting]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "financePermissionProvider derives canView/canManage from a non-autoDispose myPermissionsProvider (GET /me/permissions) — mirrors web's usePermissions hook; false while loading so gated UI never flashes open"
    - "Project cost rollup jobIds problem solved without touching job_dao.dart: FinanceRepository.fetchProjectRollup now returns ProjectCostRollupFetch{total, jobIds} (distinct job_id values from the response entries), fed into a StateProvider that CostEntryDao.watchByProject's family key depends on — the fetch response is the only source of job-anchored project membership since mobile Jobs carries no projectId FK"
    - "CostListSection/CostEntryCard take resolved data (entries: List<CostEntry>) as props rather than watching a provider internally — mirrors the existing ScopeBillingSection/TaskPhotoGrid data-down pattern so each screen keeps explicit control of which provider (job/trade-scope/project) it watches"

key-files:
  created:
    - mobile/lib/features/finance/presentation/providers/cost_providers.dart
    - mobile/lib/features/finance/presentation/widgets/add_cost_sheet.dart
    - mobile/lib/features/finance/presentation/widgets/cost_entry_card.dart
    - mobile/lib/features/finance/presentation/widgets/cost_list_section.dart
    - mobile/test/e2e/phase_31_cost_capture_e2e_test.dart
  modified:
    - mobile/lib/features/finance/data/finance_repository.dart
    - mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart
    - mobile/lib/features/projects/presentation/screens/trade_scope_detail_screen.dart
    - mobile/lib/features/projects/presentation/screens/project_detail_screen.dart

key-decisions:
  - "financePermissionProvider is the app's first fine-grained (finance.*) permission check on mobile — prior gating was always role-based (UserRole.admin etc). Built as a thin GET /me/permissions FutureProvider + derived Provider<FinancePermission>, deliberately NOT role-derived, since PROJECT.md's v4.0 decision (finance.* granted to owner+PM by default, company-adjustable, admin explicitly excluded) cannot be hardcoded from UserRole"
  - "FinanceRepository.fetchProjectRollup return type extended from Future<String> to Future<ProjectCostRollupFetch> (total + jobIds) — a Plan 31-04 file, touched here as a Rule 3 blocking-issue fix: CostEntryDao.watchByProject's documented contract requires a jobIds list from the caller, and this on-demand fetch response is the only place job-anchored project membership is knowable on mobile (no projectId FK on the local Jobs table)"
  - "Costs create action lives only on job/trade-scope screens; project detail shows a read-only rollup (authoritative backend total, itemized entries) per CONTEXT.md Claude's-Discretion — no anchor-picker create path added"
  - "AddCostSheet reuses jobs/presentation/widgets/add_note_bottom_sheet.dart's public compressPhoto() helper for receipt compression (2K/90% + thumbnail) instead of duplicating the compression logic (CLAUDE.md DRY)"

requirements-completed: [COST-01, COST-02, COST-03]

# Metrics
duration: 32min
completed: 2026-07-25
---

# Phase 31 Plan 05: Mobile Cost-Capture UI Summary

**Riverpod cost-capture presentation layer — a permission-gated `AddCostSheet` with camera/gallery receipt capture wired into job, trade-scope, and project detail screens, backed by a new `financePermissionProvider` (mobile's first `finance.*` fine-grained permission gate).**

## Performance

- **Duration:** ~32 min
- **Tasks:** 3 completed
- **Files modified:** 9 (5 created, 4 modified)

## Accomplishments

- `financePermissionProvider` fetches `GET /me/permissions` and derives `canView`/`canManage` booleans — the first mobile permission check that isn't role-derived, matching PROJECT.md's v4.0 decision that `finance.*` defaults to owner+PM (admin excluded) and is company-adjustable server-side.
- `AddCostSheet` creates a cost entry fully offline (amount/category/date/vendor/note via `CostEntryDao.insertCostEntry`) and attaches zero-to-many receipts captured from camera **or** gallery (`ImagePicker`), each queued locally as `pending_upload` for `CostReceiptUploadService` to drain on reconnect.
- `CostListSection`/`CostEntryCard` render cost entries with authenticated receipt thumbnails (`resolveMediaUrl` + `mediaAuthHeaders`, local-file fallback until uploaded — mirrors `TaskPhotoGrid`), a display-rounded amount (`toStringAsFixed(2)`), and a finance.manage-gated delete action.
- Job detail (Details tab), trade-scope detail, and project detail screens each show a Costs section gated on `financePermissionProvider().canView` — job and trade-scope screens offer offline "Add cost"; project detail shows a read-only aggregated rollup using the backend's authoritative total (never a locally-summed estimate, per 31-RESEARCH.md Pitfall 5).
- Solved the "no projectId FK on mobile Jobs" gap from 31-04 without touching `job_dao.dart`: `FinanceRepository.fetchProjectRollup` now returns the distinct job IDs found in its own response, which drive `CostEntryDao.watchByProject`'s `jobIds` argument reactively.
- Shipped `phase_31_cost_capture_e2e_test.dart`: offline create (zero Dio calls, sync_queue enqueued, receipt `pending_upload`), reconnect drain (`drainQueue()` POSTs `/cost-entries/`, `pullDelta()` drives the receipt POST to `/cost-entries/{id}/receipts`, receipt transitions to `uploaded` with `remoteUrl`), and a gating widget test (Costs section absent/present based on `finance.view`). `dart analyze` clean across `lib/features/finance`, `lib/features/jobs`, `lib/features/projects`, `test`; full `flutter test` suite (1153+ tests) green with no regressions.

## Task Commits

Each task was committed atomically:

1. **Task 1: Cost providers + AddCostSheet + cost list/card widgets** - `fb02c48` (feat)
2. **Task 2: Wire Costs sections into job/trade-scope/project detail screens, permission-gated** - `6870f6a` (feat)
3. **Task 3: Mobile phase E2E (offline create + receipt upload on reconnect)** - `9bec778` (test)

## Files Created/Modified

- `mobile/lib/features/finance/presentation/providers/cost_providers.dart` - `myPermissionsProvider`/`financePermissionProvider`, DAO/repository providers, cache-first `costEntriesForJobProvider`/`costEntriesForTradeScopeProvider`/`receiptsForCostEntryProvider` (background-refresh via `Future.microtask`), `costCategoriesProvider`/`costCategoryNameMapProvider`, and the project-rollup pair (`costRollupForProjectProvider` + `costRollupTotalProvider`) that coordinate via a private `_projectJobIdsProvider`
- `mobile/lib/features/finance/presentation/widgets/add_cost_sheet.dart` - modal bottom sheet: amount/category dropdown/date picker/vendor/note + camera+gallery receipt capture via `ImagePicker`, saves via `CostEntryDao.insertCostEntry` + `CostReceiptDao.insertReceipt`
- `mobile/lib/features/finance/presentation/widgets/cost_entry_card.dart` - category/amount/date/vendor/note row with authenticated receipt thumbnails and a finance.manage-gated delete action
- `mobile/lib/features/finance/presentation/widgets/cost_list_section.dart` - header + "Add cost" (finance.manage) + entry list + empty state, takes anchor + resolved `entries` as props
- `mobile/lib/features/finance/data/finance_repository.dart` - `fetchProjectRollup` now returns `ProjectCostRollupFetch{total, jobIds}` instead of a bare total string
- `mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart` - Costs card in the Details tab (`CostListSection` + `AddCostSheet`), gated on `financePermissionProvider().canView`
- `mobile/lib/features/projects/presentation/screens/trade_scope_detail_screen.dart` - Costs section appended to the task list, bound to `costEntriesForTradeScopeProvider`, gated on finance.view
- `mobile/lib/features/projects/presentation/screens/project_detail_screen.dart` - read-only `_ProjectCostRollupSection` (authoritative total + itemized entries), gated on finance.view
- `mobile/test/e2e/phase_31_cost_capture_e2e_test.dart` - offline create, reconnect drain + receipt upload, and permission-gating coverage

## Decisions Made

- `financePermissionProvider` is intentionally NOT derived from `UserRole` (unlike every other mobile permission check to date) — see key-decisions above.
- `FinanceRepository.fetchProjectRollup`'s return type was extended (Rule 3 — blocking issue) rather than adding a new mobile-only Jobs-by-project query, keeping the fix inside the already-owned 31-04 on-demand fetch path instead of introducing a job_dao.dart change outside this plan's declared file list.
- Create-cost UI stays on job/trade-scope screens only; project detail is read-only, per 31-CONTEXT.md's Claude's-Discretion note that an anchor-picker create path there is optional.
- Reused `compressPhoto()` from `add_note_bottom_sheet.dart` for receipt image compression rather than duplicating the compression/thumbnail logic.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Extended `FinanceRepository.fetchProjectRollup` to return job IDs alongside the total**
- **Found during:** Task 1 (cost providers) / Task 2 (project detail screen wiring)
- **Issue:** `CostEntryDao.watchByProject` (31-04) requires an explicit `jobIds` argument from the caller because the mobile `Jobs` table has no `projectId` FK. No existing mobile provider or DAO method could supply that list — without a fix, the project rollup could only ever show trade-scope-anchored costs, silently dropping job-anchored ones.
- **Fix:** Changed `fetchProjectRollup`'s return type from `Future<String>` to `Future<ProjectCostRollupFetch>` (`{total, jobIds}`), deriving `jobIds` from the distinct `job_id` values already present in the fetch response (no new query). `cost_providers.dart`'s `costRollupTotalProvider` stores the result in a `_projectJobIdsProvider` state that `costRollupForProjectProvider` watches, so job-anchored entries appear in the local reactive stream once the first fetch completes.
- **Files modified:** `mobile/lib/features/finance/data/finance_repository.dart`, `mobile/lib/features/finance/presentation/providers/cost_providers.dart`
- **Verification:** `dart analyze` clean; no other call sites of `fetchProjectRollup` existed outside `finance_repository.dart` itself (verified via grep before changing the signature).
- **Committed in:** `fb02c48` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary to make the project rollup's `jobIds` contract (documented in 31-04's own SUMMARY as the caller's responsibility) actually satisfiable without adding a new mobile Jobs-by-project query outside this plan's scope. No architectural change — a return-type extension on an already-owned method.

## Issues Encountered

None beyond the deviation above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Mobile field-capture surface for COST-01/02/03 is complete: offline add with camera/gallery receipts on job/trade-scope screens, read-only project rollup, and D-06 permission gating (Costs sections invisible without finance.view) — all covered by a green phase E2E.
- `financePermissionProvider` is available for reuse by Phase 32+ (labor cost, budgeting, profitability) mobile screens that also need finance.* gating — no new permission-fetch plumbing needed.
- `ProjectCostRollupFetch` establishes the pattern for "derive locally-unknowable local-query params from an on-demand fetch response" — useful precedent if Phase 33/34 hit a similar mobile-schema gap.
- No blockers.

---
*Phase: 31-actual-cost-capture*
*Completed: 2026-07-25*

## Self-Check: PASSED

All created/modified files found on disk; all three task commit hashes (`fb02c48`, `6870f6a`, `9bec778`) found in git history.
