---
phase: 04-job-lifecycle
plan: "06"
subsystem: mobile-ui
tags: [flutter, riverpod, drift, kanban, wizard, screens, offline-first]
dependency_graph:
  requires: [04-05]
  provides: [job-pipeline-screens, job-wizard, job-detail, contractor-screens]
  affects: [mobile-routing, mobile-ui]
tech_stack:
  added: []
  patterns: [StreamProvider.autoDispose.family, StateProvider (riverpod/legacy), kanban-board, offline-first-stepper]
key_files:
  created:
    - mobile/lib/features/jobs/presentation/providers/job_providers.dart
    - mobile/lib/features/jobs/presentation/providers/crm_providers.dart
    - mobile/lib/features/jobs/presentation/widgets/job_card.dart
    - mobile/lib/features/jobs/presentation/widgets/kanban_board.dart
    - mobile/lib/features/jobs/presentation/widgets/client_card.dart
    - mobile/lib/features/jobs/presentation/screens/jobs_pipeline_screen.dart
    - mobile/lib/features/jobs/presentation/screens/job_wizard_screen.dart
    - mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart
    - mobile/lib/features/jobs/presentation/screens/contractor_jobs_screen.dart
    - mobile/lib/features/jobs/presentation/screens/client_crm_screen.dart
    - mobile/lib/features/jobs/presentation/screens/client_detail_screen.dart
    - mobile/lib/features/jobs/presentation/screens/request_review_screen.dart
  modified:
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/core/routing/route_names.dart
decisions:
  - "StreamProvider.autoDispose.family used for job detail instead of FamilyAsyncNotifier (does not exist in Riverpod 3)"
  - "StateProvider imported from package:riverpod/legacy.dart (moved out of flutter_riverpod main export in Riverpod 3)"
  - "InternetConnection().hasInternetAccess used directly in wizard for one-shot check — ConnectivityService is designed for streaming background sync, not synchronous queries"
  - "Cancelled status excluded from kanban columns per RESEARCH.md Pattern 7 — shown in list view only"
  - "Step 3 (contractor/scheduling) skipped offline per locked project decision in CONTEXT.md"
metrics:
  duration_minutes: 90
  completed_date: "2026-03-09"
  tasks_completed: 2
  tasks_total: 2
  files_created: 12
  files_modified: 2
---

# Phase 4 Plan 06: Job UI Screens Summary

**One-liner:** Kanban pipeline + 4-step offline-aware wizard + tabbed detail + contractor quick-action screen, all streaming from local Drift DB via Riverpod providers.

## What Was Built

### Task 1: Riverpod Providers, Widgets, and Routes

**Providers (`job_providers.dart`):**
- `JobListNotifier` (AsyncNotifier) — watches `jobDao.watchJobsByCompany(companyId)` from Drift
- `ContractorJobsNotifier` (AsyncNotifier) — watches `jobDao.watchJobsByContractor(userId)`
- `jobDetailNotifierProvider` — `StreamProvider.autoDispose.family` for single job by ID
- `StateProvider` instances for: kanban/list toggle, status filter, trade filter, priority filter, contractor filter, client filter, batch mode, selected job IDs

**Widgets:**
- `KanbanBoard` — horizontally scrollable, 280px columns for 5 lifecycle stages (Quote, Scheduled, InProgress, Complete, Invoiced). Cancelled excluded. Column headers show count badge.
- `JobCard` — color-coded status chip, priority badge, trade type, client/contractor info (UUID shown until CRM join in Plan 07), tags (up to 3), relative date. Batch multi-select checkbox overlay.
- `ClientCard` — inline expandable card with AnimatedCrossFade. Shows tags, admin notes, referral source, recent jobs, saved properties count. Action buttons: View Profile + Create Job.

**Routes added:**
- `/jobs/new` → `JobWizardScreen` (declared before `/jobs/:id` to prevent "new" matching as jobId)
- `/jobs/:id` → `JobDetailScreen`
- `/admin/clients` → `ClientCrmScreen`
- `/admin/clients/:id` → `ClientDetailScreen`
- `/admin/requests` → `RequestReviewScreen`
- `/contractor/jobs` → `ContractorJobsScreen`

### Task 2: Job Screens

**JobsPipelineScreen** — Admin pipeline hub:
- `SegmentedButton` toggles between `KanbanBoard` and `ListView`
- Filter chips for status, trade type, priority (list view only)
- Long-press activates batch multi-select mode with floating "Bulk Transition" action bar
- `RefreshIndicator` triggers `SyncEngine.syncNow()` for manual sync
- Empty state with "Create your first job" prompt

**JobWizardScreen** — 4-step `Stepper`:
- Step 1: Client selector (placeholder for Plan 07 CRM lookup) + description (min 10 chars)
- Step 2: Address + trade type dropdown (10 trade categories)
- Step 3: Contractor assignment + date picker + estimated duration (SKIPPED if offline)
- Step 4: Review card + priority SegmentedButton + optional notes + Submit
- Offline banner shown in Step 4 explaining scheduling deferral
- All steps tappable (experienced admin fast-path)
- Submits via `JobDao.insertJob` which atomically writes Drift + sync_queue

**JobDetailScreen** — Tabbed ConsumerStatefulWidget:
- Details tab: all fields (description, trade, priority, client, contractor, PO, tags, notes)
- Schedule tab: completion date, duration estimate (placeholder for Phase 5 bookings)
- History tab: `statusHistory` JSON rendered newest-first as a timeline list

**ContractorJobsScreen** — Field-optimized job list:
- Groups: Today / Upcoming / Completed
- Large tap targets per CONTEXT.md specification
- Quick-action buttons: "Start Job" (Scheduled→InProgress) and "Complete Job" (InProgress→Complete)
- Transitions call `dao.updateJobStatus()` with cascade history append + version bump
- Status transition dialog confirms before committing

**CRM Screens (additional — implemented ahead of Plan 07):**
- `ClientCrmScreen` — searchable list with `SearchBar`, inline expandable `ClientCard` widgets, pending request badge in AppBar, FAB guidance dialog
- `ClientDetailScreen` — TabBar with Profile (editable admin notes), Jobs (history), Ratings
- `RequestReviewScreen` — Pending queue with Accept/Decline/Request Info actions via `DioClient`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] FamilyAsyncNotifier does not exist in Riverpod 3**
- **Found during:** Task 1
- **Issue:** `class JobDetailNotifier extends FamilyAsyncNotifier<JobEntity?, String>` caused "Classes can only extend other classes" — `FamilyAsyncNotifier` is not a real Riverpod 3 class
- **Fix:** Replaced with `StreamProvider.autoDispose.family<JobEntity?, String>((ref, jobId) { ... })` which is the correct Riverpod 3 pattern for parameterized stream providers
- **Files modified:** `job_providers.dart`
- **Commit:** 4772640

**2. [Rule 1 - Bug] StateProvider not in flutter_riverpod 3 main export**
- **Found during:** Task 1
- **Issue:** `StateProvider` was removed from `package:flutter_riverpod` main export in Riverpod 3; causes `undefined_identifier` at runtime
- **Fix:** Added `import 'package:riverpod/legacy.dart';` with `// ignore: depend_on_referenced_packages` comment explaining why
- **Files modified:** `job_providers.dart`, `crm_providers.dart`
- **Commit:** 4772640

**3. [Rule 1 - Bug] withOpacity deprecated in Flutter 3.27+**
- **Found during:** Task 1
- **Issue:** `color.withOpacity(0.15)` shows deprecation warning; causes analysis noise
- **Fix:** Replaced all occurrences with `.withValues(alpha: 0.15)`
- **Files modified:** `job_card.dart`, `kanban_board.dart`
- **Commit:** 4772640

**4. [Rule 1 - Bug] ConnectivityService.isConnected getter does not exist**
- **Found during:** Task 2
- **Issue:** `ConnectivityService` only exposes `isOnlineStream` (a broadcast stream); `isConnected` was never defined. Using `getIt<ConnectivityService>().isConnected` would crash at runtime.
- **Fix:** Use `InternetConnection().hasInternetAccess` directly for a one-shot check. `InternetConnection` is a lightweight stateless utility — instantiating it once is appropriate. Also removed unused `service_locator.dart` import.
- **Files modified:** `job_wizard_screen.dart`
- **Commit:** 0620756

**5. [Rule 2 - Missing critical functionality] CRM screens required by router**
- **Found during:** Task 1 (router wiring)
- **Issue:** `app_router.dart` referenced `ClientCrmScreen`, `ClientDetailScreen`, and `RequestReviewScreen` which were placeholders in admin/screens/. Plan 06 adds the routes but Plan 07 was meant to implement the screens.
- **Fix:** Implemented complete CRM screens (ClientCrmScreen, ClientDetailScreen, RequestReviewScreen) ahead of Plan 07, since the router cannot reference undefined classes. These are pre-implemented for Plan 07 to build on.
- **Files created:** `client_crm_screen.dart`, `client_detail_screen.dart`, `request_review_screen.dart`, `crm_providers.dart`, `client_card.dart`
- **Commits:** 4772640, 0620756

### Pre-existing Blockers (Not Fixed)

The following errors exist in ALL job-layer files from Plan 05 and are NOT caused by this plan:

- Missing `job_entity.freezed.dart`, `client_profile_entity.freezed.dart`, `job_request_entity.freezed.dart` — Freezed code generation requires `build_runner` which cannot run without Flutter SDK installed
- `JobsCompanion` class not in `app_database.g.dart` — Jobs table was added in Plan 05 but `build_runner` has not regenerated the Drift database file
- All `undefined_getter` errors on `JobEntity` and `ClientProfileEntity` fields (id, description, tradeType, etc.) are from these missing generated files

**Root cause:** Flutter SDK not installed on this machine — confirmed in STATE.md as a known blocker.
**Resolution:** Run `flutter pub run build_runner build --delete-conflicting-outputs` once Flutter SDK is installed.

## Self-Check

### Files Exist
- `mobile/lib/features/jobs/presentation/providers/job_providers.dart` — FOUND
- `mobile/lib/features/jobs/presentation/providers/crm_providers.dart` — FOUND
- `mobile/lib/features/jobs/presentation/widgets/job_card.dart` — FOUND
- `mobile/lib/features/jobs/presentation/widgets/kanban_board.dart` — FOUND
- `mobile/lib/features/jobs/presentation/widgets/client_card.dart` — FOUND
- `mobile/lib/features/jobs/presentation/screens/jobs_pipeline_screen.dart` — FOUND
- `mobile/lib/features/jobs/presentation/screens/job_wizard_screen.dart` — FOUND
- `mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart` — FOUND
- `mobile/lib/features/jobs/presentation/screens/contractor_jobs_screen.dart` — FOUND
- `mobile/lib/features/jobs/presentation/screens/client_crm_screen.dart` — FOUND
- `mobile/lib/core/routing/app_router.dart` — FOUND (modified)
- `mobile/lib/core/routing/route_names.dart` — FOUND (modified)

### Commits Exist
- 4772640: feat(04-06): Riverpod providers, kanban/list widgets, and GoRouter routes — FOUND
- 0620756: feat(04-06): job pipeline, wizard, detail, and contractor screens — FOUND

## Self-Check: PASSED
