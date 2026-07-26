---
phase: 31-actual-cost-capture
verified: 2026-07-26T06:00:40Z
status: human_needed
score: 5/5 must-haves verified
human_verification:
  - test: "On an emulator/physical device, log in as Owner/PM, add a cost entry with a receipt photo (camera or gallery), reopen the entry, and confirm the receipt thumbnail actually renders (loads pixels, not just a configured NetworkImage/auth header)."
    expected: "Receipt thumbnail displays the captured/selected image after upload completes; local-file fallback shows immediately before upload, then swaps to the authenticated remote URL."
    why_human: "Widget/E2E tests assert the NetworkImage/Image.file widget is configured with the correct URL + auth headers, not that pixels actually paint on a real renderer — this is explicitly called out as a Manual-Only Verification in 31-VALIDATION.md."
---

# Phase 31: Actual Cost Capture Verification Report

**Phase Goal:** Owner/PM can record real project costs as they occur, with supporting documentation, scoped to the job or trade scope they belong to
**Verified:** 2026-07-26T06:00:40Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth | Status | Evidence |
| --- | ----- | ------ | -------- |
| 1 | Owner/PM can record a materials cost entry (amount, category, date, vendor, note) against a job or trade scope | ✓ VERIFIED | Backend: `test_create_materials_cost_entry_on_job` + `test_create_materials_cost_entry_on_trade_scope` pass. Web: `AddCostDialog` posts via `useAddCostEntry`→`createCostEntry`; Playwright asserts captured POST payload + list render. Mobile: `AddCostSheet`→`CostEntryDao.insertCostEntry`, E2E asserts offline persistence + sync-queue enqueue + server push on drain. |
| 2 | Owner/PM can record a subcontractor or other cost entry the same way, against a job or trade scope | ✓ VERIFIED | Backend: `test_create_subcontractor_cost_entry`, `test_create_other_category_cost_entry` pass (category_id path). Same UI/mobile flow as truth 1 — category is a dropdown populated from `/cost-categories/`, not a separate code path. |
| 3 | Owner/PM can attach a receipt photo to any cost entry | ✓ VERIFIED (upload/serve/multi automated; pixel-render manual) | Backend: `test_upload_and_fetch_cost_receipt`, `test_multiple_receipts_per_cost_entry` pass; RLS-scoped `cost-receipts` serve branch confirmed in `serve_router.py`. Web: Playwright asserts captured `POST /cost-entries/{id}/receipts`. Mobile: `AddCostSheet` uses `ImagePicker` (camera+gallery), E2E confirms local `pending_upload` → `uploaded` transition with `remoteUrl` on reconnect drain. Actual pixel rendering on a device is a documented Manual-Only Verification in 31-VALIDATION.md — not automatable. |
| 4 | A user without finance.* permission cannot view or create cost entries — attempting to do so returns a 403 | ✓ VERIFIED | Backend: `test_non_finance_role_403_on_every_cost_endpoint` and `test_non_finance_role_403_on_every_receipt_endpoint` both pass — admin (non-finance) role gets 403 on create/list/get/patch/delete + receipts upload/list/delete + rollup + categories. Web: Playwright asserts the Costs section is entirely absent without `finance.view`; `CostEntryList` gates delete behind `finance.manage`. Mobile: `financePermissionProvider` (GET /me/permissions-backed) gates all three Costs sections; E2E widget test asserts section absent/present based on `finance.view`. |
| 5 | Data is correctly scoped to job XOR trade scope, with soft-delete and cross-tenant isolation preserved | ✓ VERIFIED | Backend: `test_cost_entry_rejects_both_or_neither_anchor` (422), `test_soft_deleted_cost_entry_excluded_from_lists_and_rollup`, `test_project_rollup_combines_scope_and_job_costs` (single-query rollup), `test_cost_entry_api_rls_isolation`, `test_other_tenant_cannot_fetch_cost_receipt` all pass. |

**Score:** 5/5 truths verified (4/5 fully automated; 1 partially automated with a documented, non-blocking manual pixel-render check)

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `backend/migrations/versions/0034_cost_receipts.py` | `cost_receipts` table + RLS, down_revision 0033 | ✓ VERIFIED | 56 lines. Contains `cost_receipts`, `tenant_isolation_cost_receipts`, `FORCE ROW LEVEL SECURITY`. `down_revision = "0033_project_quotes"` — matches the codebase's actual full-name revision-ID convention (verified against 0032/0033's own revision strings), not the plan's shorthand `"0033"`. |
| `backend/app/features/finance/repository.py` | FinanceRepository, deleted_at-filtered queries | ✓ VERIFIED | 126 lines. 7 occurrences of `deleted_at.is_(None)`, `rollup_for_project` single-query join, `joinedload(CostEntry.category)` present. |
| `backend/app/features/finance/service.py` | FinanceService, no manual commits | ✓ VERIFIED | 110 lines. `class FinanceService(TenantScopedService[CostEntry])`; the only `db.commit()`-adjacent match is a docstring line ("No db.commit() — get_db handles..."), not an actual call — zero real commit calls. |
| `backend/app/features/finance/router.py` | Gated cost-entry + receipt + rollup + category endpoints | ✓ VERIFIED | 235 lines. `require_permission("finance.manage")` and `require_permission("finance.view")` both present; plain `APIRouter` (the one `CRUDRouter` match is a docstring explicitly saying "NOT CRUDRouter"); receipt routes, `_save_cost_receipt_file`, 413 size guard all present. |
| `backend/tests/test_phase_31_e2e.py` | Full cost-entry + receipt E2E suite | ✓ VERIFIED | 572 lines, 13 tests — all pass (see Behavioral Spot-Checks). |
| `backend/app/features/files/serve_router.py` | RLS-scoped `cost-receipts` serve branch | ✓ VERIFIED | Contains `cost-receipts` branch, imports `CostReceipt`, RLS-scoped existence query (not a UUID-shape check). |
| `web/src/features/finance/api.ts` | Finance API client incl. receipt upload | ✓ VERIFIED | 168 lines. `uploadCostReceipt` + `apiUpload` present (no hand-rolled fetch). |
| `web/src/features/finance/hooks.ts` | TanStack Query hooks + mutations | ✓ VERIFIED | 104 lines. `useAddCostEntry`, `useProjectCostRollup`, `invalidateQueries` all present. |
| `web/tests/cost-capture.spec.ts` | Playwright E2E for gated cost capture | ✓ VERIFIED | 227 lines, 3/3 passing (see Behavioral Spot-Checks). |
| `mobile/lib/core/database/tables/cost_entries.dart` / `cost_receipts.dart` | Drift v16 schema | ✓ VERIFIED | `schemaVersion => 16`, `from < 16` migration branch, `RealColumn` money, `uploadStatus` lifecycle column all present. |
| `mobile/lib/core/sync/handlers/cost_entry_sync_handler.dart` | Outbound push handler, entityType 'cost_entry' | ✓ VERIFIED | 66 lines. Registered in `service_locator.dart`; confirmed absent from `sync_engine.dart`'s `pullDelta` `entityTypes` list (Pitfall 2 closed). |
| `mobile/lib/features/finance/services/cost_receipt_upload_service.dart` | Retry/backoff receipt upload | ✓ VERIFIED | 184 lines. `uploadPending` present; wired via `setCostReceiptUploadService` immediately after `_attachmentUploadService!.uploadPending()` in `pullDelta` (correct text-before-binary ordering). |
| `mobile/lib/features/finance/data/finance_repository.dart` | On-demand fetch + Drift upsert | ✓ VERIFIED | 174 lines. `cost-entries/` on-demand fetch paths present. |
| `mobile/lib/features/finance/presentation/widgets/add_cost_sheet.dart` | Offline cost-entry form + camera/gallery receipt | ✓ VERIFIED | 413 lines. `insertCostEntry` + `ImagePicker` both present. |
| `mobile/test/e2e/phase_31_cost_capture_e2e_test.dart` | Offline create + receipt upload E2E | ✓ VERIFIED | 347 lines, 4/4 tests passing within the 16-test finance run (see Behavioral Spot-Checks). |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `backend/app/main.py` | `finance_router` | `include_router(finance_router, prefix=/api/v1)` | ✓ WIRED | `finance_router` grep-confirmed in `main.py`. |
| `backend/app/features/finance/service.py` | `FinanceRepository` | service delegates all queries to repository | ✓ WIRED | Router handlers call `FinanceService(db)` methods which delegate to repository; no direct DB access in router. |
| `backend/app/features/finance/repository.py` | `TradeScope + Job` | rollup joins on `project_id` | ✓ WIRED | `rollup_for_project` single LEFT OUTER JOIN confirmed. |
| `backend/app/features/files/serve_router.py` | `CostReceipt` | RLS-scoped existence query on `remote_url` | ✓ WIRED | `CostReceipt.remote_url == f"/files/{file_path}"` pattern confirmed, mirrors `task-attachments` template exactly. |
| `web/src/features/finance/components/AddCostDialog.tsx` | `web/src/features/finance/api.ts` | `useAddCostEntry` → `createCostEntry` | ✓ WIRED | Confirmed via passing Playwright test asserting captured POST payload. |
| `web/src/app/(dashboard)/projects/components/ProjectDetail.tsx` | `ProjectCostsCard` | gated render behind `can('finance.view')` | ✓ WIRED | `can("finance.view")` gate confirmed at render site. |
| `mobile/lib/core/di/service_locator.dart` | `CostEntrySyncHandler` | `registry.register(CostEntrySyncHandler(...))` | ✓ WIRED | Confirmed registered. |
| `mobile/lib/core/sync/sync_engine.dart` | `CostReceiptUploadService` | `setCostReceiptUploadService` + `uploadPending()` in `pullDelta` after attachments | ✓ WIRED | Confirmed correct ordering (line 421 after line 414). |
| `mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart` | `CostListSection` | gated section using cost providers | ✓ WIRED | `CostListSection` + `financePermissionProvider`/`canView` gate both confirmed. |
| `mobile/lib/features/finance/presentation/widgets/add_cost_sheet.dart` | `CostEntryDao + CostReceiptDao` | insert entry then insert local receipt (pending_upload) | ✓ WIRED | `insertCostEntry` confirmed in widget; DAO-level `pending_upload` transition confirmed by passing E2E test. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | -------------- | ------ | ------------------- | ------ |
| `ProjectCostsCard.tsx` | `total`, `entries` (rollup) | `useProjectCostRollup(projectId)` → `GET /projects/{id}/cost-entries` → `FinanceRepository.rollup_for_project` (SQLAlchemy JOIN over `cost_entries`/`trade_scopes`/`jobs`) | Yes | ✓ FLOWING |
| `CostEntryList.tsx` | entries list | `useCostEntriesForJob`/`ForTradeScope` → DB query via `FinanceRepository.list_for_job`/`list_for_trade_scope` | Yes | ✓ FLOWING |
| `cost_entry_card.dart` | amount/category/receipts | `costEntriesForJobProvider`/`ForTradeScope` → `CostEntryDao.watchByJob` (real Drift query, reactive stream, populated by on-demand `FinanceRepository` fetch) | Yes | ✓ FLOWING |
| `_ProjectCostRollupSection` (project_detail_screen.dart) | rollup total + entries | `costRollupForProjectProvider` → `FinanceRepository.fetchProjectRollup` → authoritative backend total (not locally summed) | Yes | ✓ FLOWING |

No hardcoded/static/empty-array returns found in any data-fetching path; all rollup and list surfaces trace to real DB queries or real on-demand API fetches.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Backend cost-entry + receipt E2E (13 tests) | `pytest tests/test_phase_31_e2e.py -q` | `13 passed in 20.82s` | ✓ PASS |
| Web finance component/form Jest suite | `npx jest src/features/finance` | `3 passed, 3 total` | ✓ PASS |
| Web cost-capture Playwright spec | `npx playwright test tests/cost-capture.spec.ts` | `3 passed (6.7s)` | ✓ PASS |
| Mobile phase E2E + finance unit tests | `flutter test test/e2e/phase_31_cost_capture_e2e_test.dart test/unit/features/finance` | `+16: All tests passed!` | ✓ PASS |
| Web typecheck | `cd web && npx tsc --noEmit` | exit 0, no output | ✓ PASS |
| Mobile static analysis (finance/sync/database) | `dart analyze lib/features/finance lib/core/sync lib/core/database` | `No issues found!` | ✓ PASS |

Per the orchestrator-reported context, the fuller suites were already run and green immediately prior to this verification: backend full suite 640 passed/1 skipped, Flutter full suite green, Jest 158/158, Playwright cost-capture 3/3 — consistent with the targeted re-runs performed here.

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
| ----------- | --------------- | ----------- | ------ | -------- |
| COST-01 | 31-01, 31-03, 31-04, 31-05 | Owner/PM can record a materials cost entry (amount, category, date, vendor, note) against a job or trade scope | ✓ SATISFIED | Backend CRUD + XOR anchor validation; web `AddCostDialog`; mobile `AddCostSheet` — all wired and tested. REQUIREMENTS.md marks COST-01 `[x]` Complete, mapped to Phase 31. |
| COST-02 | 31-01, 31-03, 31-04, 31-05 | Owner/PM can record subcontractor and other cost entries the same way | ✓ SATISFIED | Same code path as COST-01, differentiated by `category_id`; `test_create_subcontractor_cost_entry`/`test_create_other_category_cost_entry` pass. REQUIREMENTS.md marks COST-02 `[x]` Complete. |
| COST-03 | 31-02, 31-03, 31-04, 31-05 | Owner/PM can attach a receipt photo to a cost entry | ✓ SATISFIED | Upload/list/delete/serve endpoints, RLS-scoped serving, web file input, mobile camera/gallery capture with offline queue + retry/backoff upload — all wired and tested (one pixel-render check is manual-only, doesn't block satisfaction of the requirement's functional contract). REQUIREMENTS.md marks COST-03 `[x]` Complete. |

No orphaned requirements found — REQUIREMENTS.md's Phase 31 mapping (COST-01/02/03) exactly matches the union of `requirements:` fields declared across all five PLAN.md frontmatters.

### Anti-Patterns Found

None. Scanned all 13 backend files and 11 web files and 11 mobile files created/modified across the 5 plans for `TODO|FIXME|XXX|HACK|PLACEHOLDER`, "coming soon", "not yet implemented", empty handler bodies (`=> {}`), and bare `return null`/`return {}`/`return []` patterns outside test files — zero matches.

### Human Verification Required

### 1. Receipt photo renders correctly on a physical device/emulator

**Test:** Log in as Owner/PM on an emulator or physical device, add a cost entry with a receipt captured from camera or picked from gallery, reopen the entry, confirm the receipt thumbnail actually loads and displays.
**Expected:** The receipt thumbnail shows the local file immediately (before upload completes), then displays the same image via the authenticated remote URL after upload finishes — no broken image icon, no infinite spinner.
**Why human:** This is explicitly documented as a Manual-Only Verification in `31-VALIDATION.md` — automated widget tests only assert that the `Image`/`NetworkImage` widget is configured with the correct URL and auth headers, not that pixels actually render on a real device compositor.

### Gaps Summary

No functional gaps found. All 5 PLAN.md must_haves (truths, artifacts, key_links) across all five plans (31-01 through 31-05) verified against the actual codebase — not just SUMMARY claims. All 13 backend E2E tests, 3 web Jest tests, 3 Playwright E2E tests, and 16 mobile tests (4 phase-E2E + 12 unit) pass on direct re-run. Requirements COST-01/COST-02/COST-03 are fully accounted for with no orphans. The single item routed to human verification (receipt thumbnail pixel-rendering on a real device) is a cosmetic/visual confirmation that cannot be automated and does not indicate a code defect — the underlying wiring (URL construction, auth headers, local-file fallback) is verified by automated widget/E2E tests. Status is set to `human_needed` rather than `passed` solely to surface this pending manual check to the user; there are no blocking gaps requiring re-planning.

---

_Verified: 2026-07-26T06:00:40Z_
_Verifier: Claude (gsd-verifier)_
