---
phase: 24-gc-inspection-workflow
verified: 2026-03-25T00:00:00Z
status: passed
score: 22/22 must-haves verified
re_verification: false
---

# Phase 24: GC Inspection Workflow Verification Report

**Phase Goal:** GCs can formally inspect completed tasks from mobile, approve or reject them with annotated photo evidence, create punch list items, and contractors are notified of decisions immediately
**Verified:** 2026-03-25
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | POST /tasks/{id}/inspect with decision=approved creates a TaskInspection record and task stays complete | VERIFIED | `test_gc_approves_complete_task` passes; InspectionService validates `task.status != 'complete'` guard at line 73 of service.py |
| 2  | POST /tasks/{id}/inspect with decision=rejected creates a TaskInspection record and sets task.status=rejected | VERIFIED | `test_gc_rejects_complete_task` passes; service sets `task.status = "rejected"` on rejection path |
| 3  | POST /tasks/{id}/inspect with decision=rejected re-blocks successor tasks | VERIFIED | `test_reject_task_reblocks_dependents` passes; `reblock_successors()` calls `DependencyService._recompute_blocked_status()` for each FS/SS/SE successor |
| 4  | POST /projects/{id}/flags creates a SiteWalkFlag record | VERIFIED | `test_create_site_walk_flag` passes; endpoint wired to `SiteWalkFlagService.create_flag()` |
| 5  | POST /projects/{id}/punch-items creates a PunchListItem record | VERIFIED | `test_create_punch_item` passes; endpoint wired to `PunchListService.create_item()` |
| 6  | PATCH /flags/{id}/convert creates a PunchListItem with source_flag_id set and flag status=converted | VERIFIED | `test_convert_flag_to_punch_item` and `test_punch_item_has_source_flag_when_converted` pass; `SiteWalkFlagService.convert_to_punch_item()` handles both writes |
| 7  | FCM notification dispatched on rejection via fire-and-forget (never blocks inspect response) | VERIFIED | `test_rejection_triggers_fcm`, `test_rejection_fcm_failure_does_not_block_inspect` pass; `asyncio.create_task()` pattern confirmed at service.py line 107 |
| 8  | Drift schema version is 12 and migration from 11 creates 3 new tables + inspectionChecklist column | VERIFIED | `app_database.dart` has `schemaVersion => 12`; migration block `if (from < 12)` creates all 3 tables and adds `inspectionChecklist` column |
| 9  | TaskInspectionDao can insert and watch inspections for a task | VERIFIED | `class TaskInspectionDao` with `watchByTaskId()` and `createInspection()` with dual-write into syncQueue |
| 10 | SiteWalkFlagDao.convertFlag wraps both flag status update and punch item creation in a single Drift transaction | VERIFIED | `db.transaction()` wraps both writes; doc comment confirms atomicity guarantee |
| 11 | All 3 DAOs write to sync queue in a Drift transaction (offline-first dual-write) | VERIFIED | Each DAO uses `into(syncQueue).insert` inside `db.transaction()` |
| 12 | Riverpod providers expose streams for inspections, flags, and punch items | VERIFIED | `inspectionsForTaskProvider`, `flagsForProjectProvider`, `punchItemsByScopeProvider` present at project_providers.dart lines 294–324 |
| 13 | GC sees Approve and Reject buttons on task detail screen when task is complete | VERIFIED | `showInspectBar` / `isGcOrAdmin` logic confirmed; Flutter E2E test `GC sees Approve and Reject buttons on complete task` passes |
| 14 | Approve button is disabled until all checklist items are checked | VERIFIED | `InspectionChecklist` widget with `onAllCheckedChanged` callback; Flutter E2E test `Approve disabled until all checklist items checked` passes |
| 15 | Reject button opens a bottom sheet with reason dropdown, comment field, and photo evidence option | VERIFIED | `showRejectionSheet()` confirmed with `DropdownButtonFormField`, `Confirm Rejection` button, `rework_needed` reason; Flutter E2E test passes |
| 16 | Contractor sees Start Rework button when task status is rejected | VERIFIED | `showReworkBar = isRejected && !isGcOrAdmin` logic at task_detail_screen.dart line 116; Flutter E2E test `Contractor sees Start Rework on rejected task` passes |
| 17 | GC sees total hours logged from task time entries on the inspection view (D-02) | VERIFIED | `Total Time Logged` section renders when `showInspectBar` at task_detail_screen.dart line 193; Flutter E2E test passes |
| 18 | GC sees status transition timeline (D-02) | VERIFIED | `_StatusTimeline` widget at line 897 shows Created, In Progress, Complete; Flutter E2E test passes |
| 19 | Tapping Flag Issue immediately opens the camera; skip-photo by cancelling camera (D-09) | VERIFIED | `showFlagCaptureFlow()` calls `picker.pickImage(source: ImageSource.camera)` as first action at flag_capture_sheet.dart line 39 |
| 20 | Punch list items appear inline in trade scope task view with orange Punch badge | VERIFIED | `punchItemsByScopeProvider` watched in trade_scope_detail_screen.dart; `PunchListCard` with `0xFFE65100` orange badge confirmed; Flutter E2E test passes |
| 21 | Site walk flags show as collapsible section on project detail with convert-to-punch option | VERIFIED | `SiteWalkFlagSection` with `ExpansionTile` embedded in project_detail_screen.dart; `convertFlag` DAO call confirmed |
| 22 | Test suite: 26 backend + 37 Flutter E2E tests all pass | VERIFIED | `26 passed` in 31.47s (pytest); `+37: All tests passed!` (flutter test) |

**Score:** 22/22 truths verified

---

## Required Artifacts

### Plan 01 — Backend

| Artifact | Status | Evidence |
|----------|--------|----------|
| `backend/migrations/versions/0022_inspection_workflow.py` | VERIFIED | Contains `task_inspections`, `site_walk_flags`, `punch_list_items` tables with RLS; status constraint extended to include `'rejected'` |
| `backend/app/features/inspection/models.py` | VERIFIED | `class TaskInspection(TenantScopedModel)`, `class SiteWalkFlag(TenantScopedModel)`, `class PunchListItem(TenantScopedModel)` all present |
| `backend/app/features/inspection/service.py` | VERIFIED | `class InspectionService(TenantScopedService[TaskInspection])`; `asyncio.create_task` fire-and-forget; `reblock_successors` and `_recompute_blocked_status` present |
| `backend/app/features/inspection/router.py` | VERIFIED | `inspection_router` with 8 endpoints (7 required + 1 bonus audit trail); registered in `main.py` |
| `backend/app/features/notifications/service.py` | VERIFIED | `send_task_rejection_notification()` at line 340; `"Task Rejected"` title at line 377 |
| `backend/app/main.py` | VERIFIED | `inspection_router` imported and included at `/api/v1` |

### Plan 02 — Mobile Data Layer

| Artifact | Status | Evidence |
|----------|--------|----------|
| `mobile/lib/core/database/app_database.dart` | VERIFIED | `schemaVersion => 12`; `TaskInspections`, `SiteWalkFlags`, `PunchListItems` in tables list; `from < 12` migration block |
| `mobile/lib/features/projects/data/task_inspection_dao.dart` | VERIFIED | `class TaskInspectionDao`; `watchByTaskId()`; `into(syncQueue).insert` dual-write |
| `mobile/lib/features/projects/data/site_walk_flag_dao.dart` | VERIFIED | `class SiteWalkFlagDao`; `convertFlag()` with `db.transaction()`; `@DriftAccessor` includes `PunchListItems` |
| `mobile/lib/features/projects/data/punch_list_item_dao.dart` | VERIFIED | `class PunchListItemDao`; `watchByScopeId()`; sync queue dual-write |
| `mobile/lib/core/database/app_database.g.dart` | VERIFIED | Contains `TaskInspection` (99 matches) — generated code is current |

### Plan 03 — Mobile UI

| Artifact | Status | Evidence |
|----------|--------|----------|
| `mobile/lib/features/projects/presentation/widgets/inspection_checklist.dart` | VERIFIED | `class InspectionChecklist`; `kDefaultInspectionChecklist` with `"Quality of work is acceptable"` |
| `mobile/lib/features/projects/presentation/widgets/rejection_bottom_sheet.dart` | VERIFIED | `showRejectionSheet()`; `DropdownButtonFormField`; `rework_needed`; `Confirm Rejection` |
| `mobile/lib/features/projects/presentation/widgets/punch_list_card.dart` | VERIFIED | `class PunchListCard`; `0xFFE65100` orange left edge; `Punch` badge |
| `mobile/lib/features/projects/presentation/widgets/flag_capture_sheet.dart` | VERIFIED | `showFlagCaptureFlow()`; `ImagePicker`; `ImageSource.camera` called immediately |
| `mobile/lib/features/projects/presentation/widgets/site_walk_flag_section.dart` | VERIFIED | `class SiteWalkFlagSection`; `ExpansionTile`; `convertFlag`; `flagsForProjectProvider` |
| `mobile/lib/features/projects/presentation/screens/task_detail_screen.dart` | VERIFIED | `showInspectBar`; `isGcOrAdmin`; `InspectionChecklist`; `showRejectionSheet`; `Start Rework`; `Total Time Logged`; `0xFFB71C1C` rejected badge |
| `mobile/lib/features/projects/presentation/screens/project_detail_screen.dart` | VERIFIED | `SiteWalkFlagSection`; `showFlagCaptureFlow`; `Flag Issue` button |
| `mobile/lib/features/projects/presentation/screens/trade_scope_detail_screen.dart` | VERIFIED | `punchItemsByScopeProvider`; `PunchListCard`; `Punch List` section header |

### Plan 04 — E2E Tests

| Artifact | Status | Evidence |
|----------|--------|----------|
| `backend/tests/test_phase_24_inspection.py` | VERIFIED | `test_gc_approves_complete_task`, `test_gc_rejects_complete_task`, `test_reject_task_reblocks_dependents`, `test_reject_non_complete_task_returns_422` — all 8 tests pass |
| `backend/tests/test_phase_24_site_walk.py` | VERIFIED | `test_create_site_walk_flag`, `test_convert_flag_to_punch_item` — all 7 tests pass |
| `backend/tests/test_phase_24_punch_list.py` | VERIFIED | `test_create_punch_item`, `test_update_punch_item_status` — all 6 tests pass |
| `backend/tests/test_phase_24_fcm_rejection.py` | VERIFIED | `test_rejection_triggers_fcm`, `test_rejection_fcm_no_creds_graceful` — all 5 tests pass |
| `mobile/test/e2e/phase_24_inspection_e2e_test.dart` | VERIFIED | 12 tests covering approve/reject UI, checklist, time summary, timeline, Start Rework — all pass |
| `mobile/test/e2e/phase_24_site_walk_e2e_test.dart` | VERIFIED | 9 tests covering flags section, count chip, Convert to Punch visibility — all pass |
| `mobile/test/e2e/phase_24_punch_list_e2e_test.dart` | VERIFIED | 16 tests covering PunchListCard widget rendering, colors, badges — all pass |

---

## Key Link Verification

| From | To | Via | Status | Evidence |
|------|----|-----|--------|----------|
| `inspection/service.py` | `notifications/service.py` | `asyncio.create_task(send_task_rejection_notification(...))` | WIRED | Line 107 in service.py; `test_rejection_triggers_fcm` passes |
| `inspection/service.py` | `projects/service.py` | `DependencyService._recompute_blocked_status()` | WIRED | Line 151 in service.py; `test_reject_task_reblocks_dependents` passes |
| `inspection/router.py` | `inspection/service.py` | `Depends` injection of `InspectionService` | WIRED | `inspection_router` wired to all 3 service classes |
| `app_database.dart` | `tables/task_inspections.dart` | `TaskInspections` in `@DriftDatabase(tables:)` | WIRED | Line 127 in app_database.dart |
| `task_inspection_dao.dart` | `sync_queue` | `into(syncQueue).insert` in Drift transaction | WIRED | Dual-write confirmed; 3 new sync handlers registered in service_locator.dart |
| `site_walk_flag_dao.dart` | `punch_list_item_dao.dart` | `convertFlag()` wraps both in `db.transaction()` | WIRED | `@DriftAccessor(tables: [SiteWalkFlags, PunchListItems, SyncQueue])` confirmed |
| `task_detail_screen.dart` | `inspection_checklist.dart` | `InspectionChecklist` in `SliverToBoxAdapter` | WIRED | Line 1059 in task_detail_screen.dart |
| `task_detail_screen.dart` | `rejection_bottom_sheet.dart` | `showRejectionSheet(context)` on Reject tap | WIRED | Line 584 in task_detail_screen.dart |
| `trade_scope_detail_screen.dart` | `punch_list_card.dart` | `punchItemsByScopeProvider` stream rendering | WIRED | Lines 40, 117 in trade_scope_detail_screen.dart |
| `flag_capture_sheet.dart` | `ImagePicker` | `pickImage(source: ImageSource.camera)` at entry | WIRED | Line 39 in flag_capture_sheet.dart — no intermediate dialog |
| `backend/tests/test_phase_24_inspection.py` | `inspection/router.py` | ASGI client POST `/api/v1/tasks/{id}/inspect` | WIRED | All 8 tests use `tenant_a_client.post(f"/api/v1/tasks/{task_id}/inspect")` |
| `mobile/test/e2e/phase_24_inspection_e2e_test.dart` | `task_detail_screen.dart` | `ProviderScope` overrides + `TaskDetailScreen` widget | WIRED | Fake DAOs injected via `ProviderScope.overrideWith()` |
| `service_locator.dart` | new sync handlers | `registry.register(TaskInspectionSyncHandler(...))` etc. | WIRED | Lines 104–106 in service_locator.dart; all 3 handlers registered |

---

## Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| INSP-01 | 01, 02, 03, 04 | GC can inspect completed tasks and approve or reject them with comments | SATISFIED | Backend API + mobile UI + 8 backend tests + 12 Flutter E2E tests covering full approve/reject flow including reblock_successors |
| INSP-02 | 01, 02, 03, 04 | GC can flag issues discovered during site walks with photos and annotations | SATISFIED | `SiteWalkFlag` model/service/endpoint + `SiteWalkFlagSection` widget + camera-first capture + 7 backend tests + 9 Flutter E2E tests |
| INSP-03 | 01, 02, 03, 04 | GC can create punch list items assigned to specific trades | SATISFIED | `PunchListItem` model/service/endpoint + `PunchListCard` widget + inline rendering in trade scope view + 6 backend tests + 16 Flutter E2E tests |
| INSP-04 | 01, 04 | Rejected tasks trigger notification to the trade contractor with GC's feedback | SATISFIED | `send_task_rejection_notification()` in NotificationService; `asyncio.create_task` fire-and-forget; 5 backend tests including FCM mock verification |

---

## Anti-Patterns Found

None. No TODOs, FIXMEs, placeholder returns, or stub implementations found in any phase 24 files.

---

## Human Verification Required

The following items cannot be fully verified programmatically and may benefit from manual review, though they are not blocking:

### 1. Camera-first flag capture on a real device

**Test:** Tap "Flag Issue" button on a real device on the ProjectDetailScreen.
**Expected:** Camera viewfinder opens immediately with no intermediate dialog or prompt.
**Why human:** `ImagePicker.pickImage(source: ImageSource.camera)` is mocked in Flutter tests; actual camera hardware behavior can only be confirmed on a physical device.

### 2. Photo annotation in rejection sheet

**Test:** Tap "Add Photo Evidence" in the rejection bottom sheet, take a photo, annotate it.
**Expected:** Annotation screen opens, allows drawing, and annotation JSON is carried back to the rejection form with thumbnail preview.
**Why human:** `PhotoAnnotationScreen` integration relies on camera hardware and the Navigator result round-trip; widget tests mock this path.

### 3. FCM push notification delivery to contractor

**Test:** Reject a task assigned to a contractor who has a real FCM device token registered.
**Expected:** The contractor's device receives a push notification titled "Task Rejected" with the rejection reason in the body.
**Why human:** FCM is mocked in all tests; actual push delivery requires a Firebase project with credentials and a real device.

### 4. Rejected status badge visual appearance

**Test:** Navigate to a task with `status: 'rejected'` on the TaskDetailScreen.
**Expected:** Status badge shows deep red (`#B71C1C`) distinct from other status colors.
**Why human:** Color rendering can only be confirmed visually on screen.

---

## Gaps Summary

No gaps found. All 22 must-have truths are verified. The phase goal is fully achieved:

- GCs can formally inspect completed tasks from mobile: DONE (approve/reject with checklist, time summary, status timeline)
- GCs can approve or reject with annotated photo evidence: DONE (rejection sheet with photo evidence + annotation, Approve requires full checklist)
- GCs can create punch list items: DONE (directly via POST /punch-items and via flag conversion; renders inline in trade scope view)
- Contractors are notified of decisions immediately: DONE (FCM fire-and-forget via asyncio.create_task, never blocks inspect response)

Test coverage: 26 backend integration tests (all pass) + 37 Flutter E2E widget tests (all pass) = 63 total tests.

---

_Verified: 2026-03-25_
_Verifier: Claude (gsd-verifier)_
