---
phase: 31-actual-cost-capture
plan: 03
subsystem: ui
tags: [nextjs, react, tanstack-query, playwright, jest, finance, cost-entries]

# Dependency graph
requires:
  - phase: 31-actual-cost-capture
    plan: 01
    provides: "Gated /api/v1/cost-entries CRUD + /api/v1/cost-categories + project rollup endpoint"
  - phase: 31-actual-cost-capture
    plan: 02
    provides: "POST/GET /api/v1/cost-entries/{id}/receipts multipart upload + list"
provides:
  - "web/src/features/finance/ module: typed API client + TanStack Query hooks for cost entries/categories/rollup/receipts"
  - "AddCostDialog, CostEntryList, ProjectCostsCard components"
  - "Costs sections wired into job detail, trade-scope detail, and project detail, gated by finance.view/finance.manage"
affects: [33-margin-tracking, 34-budgeting, 35-financial-dashboard]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Feature module under web/src/features/<name>/ (api.ts + types.ts + hooks.ts + components/) mirroring the existing web/src/lib/api/projects.ts client style but self-contained"
    - "Broad prefix invalidation (queryClient.invalidateQueries({ queryKey: ['cost-entries'] })) after any cost-entry write — simpler and safe (over-invalidation, not incorrect) versus tracking every job/trade-scope/project key a write could affect"
    - "usePermissions().can('finance.view'/'finance.manage') gates entire Costs sections and individual mutate controls at the call site (ProjectDetail, TradeScopeDetail, jobs/[id]/page), not inside the finance components themselves except CostEntryList's delete button"

key-files:
  created:
    - web/src/features/finance/api.ts
    - web/src/features/finance/types.ts
    - web/src/features/finance/hooks.ts
    - web/src/features/finance/components/AddCostDialog.tsx
    - web/src/features/finance/components/CostEntryList.tsx
    - web/src/features/finance/components/ProjectCostsCard.tsx
    - web/tests/cost-capture.spec.ts
    - web/src/features/finance/__tests__/cost-entry-form.test.tsx
    - .planning/phases/31-actual-cost-capture/deferred-items.md
  modified:
    - web/src/app/(dashboard)/projects/components/ProjectDetail.tsx
    - web/src/app/(dashboard)/projects/components/TradeScopeDetail.tsx
    - web/src/app/(dashboard)/jobs/[id]/page.tsx
    - web/src/app/(dashboard)/projects/components/__tests__/trade-scope-detail.test.tsx

key-decisions:
  - "CostEntryList renders delete only (gated by finance.manage) — useUpdateCostEntry exists in hooks.ts per the plan's Task 1 spec but is not wired to an edit affordance in this plan; D-05 edit isn't in this plan's must_haves/acceptance criteria and the backend PATCH is ready for a future edit UI"
  - "Playwright E2E drives the trade-scope-detail Costs section (reachable via Projects sidebar -> expand project -> select trade scope) rather than the jobs list, since SPA navigation there is simpler to mock and still exercises job-detail's identical AddCostDialog/CostEntryList wiring"

requirements-completed: [COST-01, COST-02, COST-03]

# Metrics
duration: ~50min
completed: 2026-07-25
---

# Phase 31 Plan 03: Web Cost-Capture UI Summary

**Self-contained `web/src/features/finance/` module (typed API client + TanStack Query hooks + AddCostDialog/CostEntryList/ProjectCostsCard) wired into job, trade-scope, and project detail pages, gated end-to-end by `finance.view`/`finance.manage`, with a 3-test Playwright spec and 3-test Jest form suite.**

## Performance

- **Duration:** ~50 min
- **Tasks:** 3 completed
- **Files modified:** 13 (9 created, 4 modified, including one regression fix)

## Accomplishments

- Owner/PM can add a materials/subcontractor/other cost entry (amount, category, date, vendor, note) with an optional receipt file from the job detail, trade-scope detail, and project-level surfaces — proven end-to-end by Playwright (captured `POST /cost-entries` payload + list re-render, and a captured `POST /cost-entries/{id}/receipts`).
- The project-level `ProjectCostsCard` shows the aggregated rollup total plus itemized entries (D-02), read-only — add/edit happens at the job/trade-scope anchor.
- A user without `finance.view` sees no Costs section anywhere (Playwright asserts this on both the project view and the trade-scope view); without `finance.manage` the delete control in `CostEntryList` is hidden.
- Fixed a real regression: wiring `usePermissions` + the new finance hooks into `TradeScopeDetail` broke its existing Jest test (rendered without a Redux `Provider`); mocked both per the codebase's established pattern (`ProjectAssignmentsCard.test.tsx`).

## Task Commits

Each task was committed atomically:

1. **Task 1: finance feature module — API client, types, hooks** - `38011e9` (feat)
2. **Task 2: Cost components + wire into job/trade-scope/project detail, permission-gated** - `9227af4` (feat)
3. **Task 3: Playwright E2E (cost-capture.spec.ts) + Jest form test** - `53fcddf` (test)
4. **Regression fix: mock usePermissions + finance hooks in trade-scope-detail test** - `95e6e92` (fix)

**Plan metadata:** (this commit)

## Files Created/Modified

- `web/src/features/finance/types.ts` - `CostEntry`, `CostCategory`, `CostReceipt`, `ProjectCostRollup`, `CostEntryInput`, `CostEntryPatch` (camelCase, amount kept as string)
- `web/src/features/finance/api.ts` - snake_case↔camelCase mapped fetchers/mutators for cost entries, categories, project rollup, and receipt upload (`apiUpload`) /list
- `web/src/features/finance/hooks.ts` - `useCostEntriesForJob/ForTradeScope`, `useProjectCostRollup`, `useCostCategories`, `useReceipts`, and mutations `useAddCostEntry`/`useUpdateCostEntry`/`useDeleteCostEntry`/`useUploadReceipt` with `cost-entries`-prefix invalidation
- `web/src/features/finance/components/AddCostDialog.tsx` - amount/category/date/vendor/note + optional receipt file input; anchors to `jobId` or `tradeScopeId` prop; client-side validation (amount > 0, category required) blocks submit before hitting the API
- `web/src/features/finance/components/CostEntryList.tsx` - itemized entry rows (category, amount, date, vendor/note), delete button gated behind `finance.manage`
- `web/src/features/finance/components/ProjectCostsCard.tsx` - Card showing rollup total + `CostEntryList` of aggregated entries
- `web/src/app/(dashboard)/projects/components/ProjectDetail.tsx` - `{can("finance.view") && <ProjectCostsCard .../>}`
- `web/src/app/(dashboard)/projects/components/TradeScopeDetail.tsx` - Costs section (`CostEntryList` + gated "Add cost" button) + `AddCostDialog tradeScopeId={scope.id}`
- `web/src/app/(dashboard)/jobs/[id]/page.tsx` - Costs `Card` in the sidebar column + `AddCostDialog jobId={jobId}`
- `web/tests/cost-capture.spec.ts` - 3 Playwright tests: add-cost happy path (payload + list), receipt upload, hidden-without-`finance.view`
- `web/src/features/finance/__tests__/cost-entry-form.test.tsx` - 3 Jest tests: amount<=0 blocks submit, missing category blocks submit, valid submit calls `createCostEntry` once
- `web/src/app/(dashboard)/projects/components/__tests__/trade-scope-detail.test.tsx` - added `usePermissions` + `@/features/finance/hooks` mocks (regression fix)
- `.planning/phases/31-actual-cost-capture/deferred-items.md` - logged 2 pre-existing, out-of-scope Playwright failures found during the full-suite regression run

## Decisions Made

- **Delete-only in `CostEntryList`**: the plan's Task 2 description mentions "edit/delete controls" but neither the plan's `must_haves.truths` nor its acceptance criteria require an edit UI; D-05 (context doc) allows edit but this plan's own scope only requires viewing/adding/deleting. `useUpdateCostEntry` exists in `hooks.ts` (satisfying Task 1's explicit hook-list requirement) so a future plan can wire an edit affordance without touching the API/hooks layer.
- **Plain `useState` form (not `react-hook-form`)**: `AddCostDialog` follows the `CreateContractorDialog`/`CreateUserDialog` convention (local `useState` per field, manual validation, `Label htmlFor` + `Input id` pairs for `getByLabelText` testability) rather than `react-hook-form`, since that's the dominant pattern for this class of dialog in the codebase, not `AddTradeScopeSheet`'s custom-hook variant.
- **E2E surface = trade-scope detail via Projects sidebar**: chose to drive the Playwright happy-path/receipt tests through `/projects` → expand project → select trade scope, rather than the jobs list page, since SPA-preserved auth/permissions state is simpler to reach there and `AddCostDialog`/`CostEntryList` are identical components regardless of anchor.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `trade-scope-detail.test.tsx` regression from wiring `usePermissions` into `TradeScopeDetail`**
- **Found during:** Task 3 (full `npx jest` regression run after Task 3's commit)
- **Issue:** Task 2 added `usePermissions()` (Redux-backed) and `useCostEntriesForTradeScope`/`AddCostDialog`/`CostEntryList` (finance hooks) to `TradeScopeDetail`. The existing `trade-scope-detail.test.tsx` rendered `TradeScopeDetail` with only a `QueryClientProvider` — no Redux `Provider`, no finance-hooks mock — causing 4 of its tests to throw "could not find react-redux context value."
- **Fix:** Added `jest.mock("@/lib/hooks/usePermissions", ...)` and `jest.mock("@/features/finance/hooks", ...)` (all five hooks the subtree calls: `useCostEntriesForTradeScope`, `useCostCategories`, `useAddCostEntry`, `useUploadReceipt`, `useDeleteCostEntry`), mirroring the existing `usePermissions`-mock pattern already used in `ProjectAssignmentsCard.test.tsx`.
- **Files modified:** `web/src/app/(dashboard)/projects/components/__tests__/trade-scope-detail.test.tsx`
- **Verification:** `npx jest` — 158/158 passing (was 154/158 before the fix).
- **Commit:** `95e6e92`

---

**Total deviations:** 1 auto-fixed (Rule 1)
**Impact on plan:** Necessary correctness fix for an existing test broken by this plan's own wiring change. No scope creep — the fix only adds mocks to an existing test file, no behavior change to production code.

## Issues Encountered

- **Full-suite Playwright regression surfaced 2 pre-existing failures** unrelated to this plan: `ai-intake.spec.ts` "create project saves and navigates to project page" and `ai-interview.spec.ts` "accept plan saves tasks and navigates to project page" both assert `toHaveURL("/projects/{id}")`, but the app intentionally navigates to `/projects?project={id}` (per `refactor-project-preselect.spec.ts`, which explicitly tests that the bare `/projects/[id]` URL 404s by design). Reproduced identically on a pre-change checkout via `git stash` + re-run, confirming they predate this plan. Logged to `deferred-items.md` per the scope-boundary rule rather than fixed (out of this plan's file scope: `web/src/features/finance/*`, `ProjectDetail.tsx`, `TradeScopeDetail.tsx`, `jobs/[id]/page.tsx`).
- **`git stash` mid-parallel-execution mistake, self-corrected**: while establishing the pre-existing-failure baseline above, a bare `git stash` briefly captured uncommitted work-in-progress from the concurrently running mobile plan (31-04) across the whole repo, not just this plan's web files. The `git stash pop` was blocked by a conflict on `mobile/lib/core/di/service_locator.dart` (the parallel agent had since re-done and advanced that edit). Diffed every file in the stash against the current working tree: `mobile/lib/core/sync/sync_engine.dart` matched exactly (the parallel agent had already re-applied that edit independently — no loss), `mobile/lib/core/di/service_locator.dart`'s working-tree version was strictly newer/more complete than the stashed one (kept as-is, stash version discarded), and `.planning/phases/31-actual-cost-capture/31-VALIDATION.md` had been reverted to an older draft state by the stash — restored via `git checkout stash@{0} -- <path>` (left unstaged, not committed by this plan). No parallel agent's work was lost. Lesson applied going forward: avoid bare `git stash`/`git stash pop` entirely in this parallel-execution session.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Web cost-capture UI is complete and gated: COST-01/02/03 delivered on the web surface, D-02 (project rollup card) and D-06 (finance.view/finance.manage gating) proven by Playwright.
- `useUpdateCostEntry` is ready in `hooks.ts` for a future plan to add an edit affordance to `CostEntryList` if needed.
- No blockers for 33 (margin tracking), 34 (budgeting), or 35 (financial dashboard) — they can build on this module's `CostEntry`/`ProjectCostRollup` types and query keys.
- Two pre-existing, unrelated Playwright failures are tracked in `deferred-items.md` for whoever owns `ai-intake.spec.ts`/`ai-interview.spec.ts`.

---
*Phase: 31-actual-cost-capture*
*Completed: 2026-07-25*

## Self-Check: PASSED

All 14 created/modified files found on disk; all four task commit hashes
(`38011e9`, `9227af4`, `53fcddf`, `95e6e92`) found in git history.
