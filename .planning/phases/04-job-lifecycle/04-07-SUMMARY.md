---
phase: 04-job-lifecycle
plan: "07"
subsystem: mobile-ui
tags: [flutter, riverpod, drift, go-router, crm, job-requests, offline-first]
dependency_graph:
  requires:
    - phase: 04-job-lifecycle
      provides: "Drift tables (ClientProfiles, JobRequests, Jobs), JobDao streams, sync handlers, domain entities"
  provides:
    - "ClientCrmScreen: searchable admin client list with inline expandable cards"
    - "ClientDetailScreen: tabbed client profile/job-history/ratings view"
    - "ClientCard: AnimatedCrossFade expandable card widget"
    - "CRM providers: clientListNotifier, pendingRequestsNotifier, clientJobHistoryNotifier"
    - "RequestReviewScreen: admin triage queue with Accept/Decline/Request-Info API calls"
    - "JobRequestFormScreen: offline-first in-app request form for clients"
  affects: [04-08, 05-calendar-ui, 07-client-portal]
tech-stack:
  added: []
  patterns:
    - "Admin screen re-export delegation: features/admin/ re-exports from features/jobs/ for router stability"
    - "Family provider pattern for per-client job history streams"
    - "StatefulWidget AnimatedCrossFade for inline card expand/collapse"
    - "DioException status-code switch for typed error messages"
    - "Offline-first request form: insertJobRequest writes to Drift + sync queue atomically"
key-files:
  created:
    - mobile/lib/features/jobs/presentation/providers/crm_providers.dart
    - mobile/lib/features/jobs/presentation/screens/client_crm_screen.dart
    - mobile/lib/features/jobs/presentation/screens/client_detail_screen.dart
    - mobile/lib/features/jobs/presentation/screens/request_review_screen.dart
    - mobile/lib/features/jobs/presentation/widgets/client_card.dart
    - mobile/lib/features/client/presentation/screens/job_request_form_screen.dart
    - mobile/lib/features/admin/presentation/screens/client_crm_screen.dart
    - mobile/lib/features/admin/presentation/screens/request_review_screen.dart
    - mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart
    - mobile/lib/features/jobs/presentation/screens/contractor_jobs_screen.dart
    - mobile/lib/features/jobs/presentation/providers/job_providers.dart
    - mobile/lib/features/jobs/presentation/screens/job_wizard_screen.dart
    - mobile/lib/features/jobs/presentation/screens/jobs_pipeline_screen.dart
    - mobile/lib/features/jobs/presentation/widgets/job_card.dart
    - mobile/lib/features/jobs/presentation/widgets/kanban_board.dart
  modified:
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/core/routing/route_names.dart
key-decisions:
  - "Admin screen re-export pattern: features/admin/presentation/screens/ acts as stable router import alias; real implementation lives in features/jobs/ following feature-first structure"
  - "Accept backend-only job creation: POST /api/v1/jobs/requests/{id}/review with action=accepted; no client-side job creation — backend does atomic job + request status update"
  - "image_picker deferred: photo picker stub documents intent; requires pubspec.yaml addition + native config which is out of scope for plan scope"
  - "context.go with query params for wizard pre-fill: accepted request data passed as URL query params to job wizard screen"
requirements-completed: [CLNT-01, CLNT-04]
duration: 15min
completed: 2026-03-09T02:36:55Z
---

# Phase 4 Plan 07: Client CRM Screens Summary

**Admin CRM with searchable expandable client cards, backend-integrated request review queue (Accept/Decline/Request Info), and offline-first in-app job request form completing the dual-flow unified pipeline.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-09T02:21:38Z
- **Completed:** 2026-03-09T02:36:55Z
- **Tasks:** 2
- **Files modified/created:** 15

## Accomplishments

- CRM providers watching Drift streams (`clientListNotifier`, `pendingRequestsNotifier`, `clientJobHistoryNotifier` family) — all offline-first reactive
- Searchable client list (`ClientCrmScreen`) with inline expandable `ClientCard` widgets (AnimatedCrossFade) showing tags, notes, recent jobs, and action buttons
- Full client detail screen (`ClientDetailScreen`) with Profile / Jobs / Ratings tabs streaming from Drift
- Request review queue (`RequestReviewScreen`) with Accept (calls POST /api/v1/jobs/requests/{id}/review then navigates to pre-filled wizard), Decline (preset reasons + message), and Request Info dialogs — all with typed DioException error handling
- Offline-first job request form (`JobRequestFormScreen`) with all required fields: description, property dropdown, date range picker, urgency toggle, trade type, photo picker slots (up to 5), budget range

## Task Commits

1. **Task 1: CRM providers and client management screens** - `cf064f5` (feat)
2. **Task 2: Job request review queue and in-app request form** - `42ece73` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `mobile/lib/features/jobs/presentation/providers/crm_providers.dart` - 3 Riverpod stream providers + clientSearchQueryProvider StateProvider
- `mobile/lib/features/jobs/presentation/screens/client_crm_screen.dart` - ClientCrmScreen with search bar + ClientCard list + pending badge
- `mobile/lib/features/jobs/presentation/screens/client_detail_screen.dart` - 3-tab client detail (Profile/Jobs/Ratings)
- `mobile/lib/features/jobs/presentation/widgets/client_card.dart` - ClientCard expandable widget with AnimatedCrossFade
- `mobile/lib/features/jobs/presentation/screens/request_review_screen.dart` - RequestReviewScreen with Accept/Decline/Info API actions
- `mobile/lib/features/client/presentation/screens/job_request_form_screen.dart` - JobRequestFormScreen offline-first submit
- `mobile/lib/features/admin/presentation/screens/client_crm_screen.dart` - Re-export alias for router
- `mobile/lib/features/admin/presentation/screens/request_review_screen.dart` - Re-export alias for router
- `mobile/lib/core/routing/app_router.dart` - ClientDetailScreen wired to /admin/clients/:id; unused import removed
- `mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart` - Rule 3 fix: tabbed job detail screen
- `mobile/lib/features/jobs/presentation/screens/contractor_jobs_screen.dart` - Rule 3 fix: contractor job list with status transitions
- `mobile/lib/features/jobs/presentation/providers/job_providers.dart` - Plan 06 uncommitted file committed
- `mobile/lib/features/jobs/presentation/screens/job_wizard_screen.dart` - Plan 06 uncommitted file committed
- `mobile/lib/features/jobs/presentation/screens/jobs_pipeline_screen.dart` - Plan 06 uncommitted file committed
- `mobile/lib/features/jobs/presentation/widgets/job_card.dart` - Plan 06 uncommitted file committed
- `mobile/lib/features/jobs/presentation/widgets/kanban_board.dart` - Plan 06 uncommitted file committed

## Decisions Made

- **Admin screen re-export pattern**: `features/admin/presentation/screens/` files re-export from `features/jobs/` — router import paths remain stable while implementation follows feature-first structure
- **Backend-only job creation on Accept**: Do NOT create job client-side; backend handles atomic job + request status update. Client navigates to wizard with response data for Steps 3-4 (contractor/schedule)
- **image_picker deferred**: Photo picker stub with clear documentation; requires `pubspec.yaml: image_picker: ^1.1.2` + native config, deferred to developer setup step
- **context.go with query params**: Accepted request data (description, tradeType, clientId) passed as URL query params to `/jobs/new` route for wizard pre-fill

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Created missing Plan 06 screens referenced by router**
- **Found during:** Task 1 (setting up file structure)
- **Issue:** `app_router.dart` (from Plan 06) imports `job_detail_screen.dart`, `contractor_jobs_screen.dart` which did not exist. Without these files, the project cannot compile.
- **Fix:** Created `job_detail_screen.dart` (tabbed detail with Details/Schedule/History tabs) and `contractor_jobs_screen.dart` (contractor job list with Scheduled→InProgress→Complete transition buttons)
- **Files modified:** `mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart`, `mobile/lib/features/jobs/presentation/screens/contractor_jobs_screen.dart`
- **Committed in:** cf064f5 (Task 1 commit)

**2. [Rule 3 - Blocking] Committed Plan 06 untracked files needed for compilation**
- **Found during:** Task 1 (reviewing git status)
- **Issue:** Plan 06 created `job_providers.dart`, `job_wizard_screen.dart`, `jobs_pipeline_screen.dart`, `job_card.dart`, `kanban_board.dart` on disk but never committed them. The modified `app_router.dart` and `route_names.dart` reference these files. Without committing them, the diff is incomplete.
- **Fix:** Staged and committed all Plan 06 untracked presentation files alongside Task 1 changes
- **Files modified:** 5 Plan 06 files staged in Task 1 commit
- **Committed in:** cf064f5 (Task 1 commit)

**3. [Rule 3 - Blocking] Admin screens use re-export pattern instead of direct implementation**
- **Found during:** Task 1 (reviewing app_router.dart imports)
- **Issue:** Router imports `ClientCrmScreen` from `features/admin/presentation/screens/client_crm_screen.dart` but plan specifies implementation in `features/jobs/presentation/screens/`. Simple delegation via Dart's `export` keyword keeps both requirements satisfied.
- **Fix:** Admin files use `export '../../../../features/jobs/presentation/screens/...'` delegation; router import paths unchanged
- **Files modified:** `mobile/lib/features/admin/presentation/screens/client_crm_screen.dart`, `mobile/lib/features/admin/presentation/screens/request_review_screen.dart`
- **Committed in:** cf064f5, 42ece73

---

**Total deviations:** 3 auto-fixed (3 blocking)
**Impact on plan:** All auto-fixes necessary for compilation and correctness. No scope creep. Plan 07 artifacts created exactly as specified.

## Issues Encountered

- Plan 06 left files uncommitted on disk while modifying `app_router.dart` and `route_names.dart` (committed). This created a state where the router referenced non-committed (but existing) files. Resolved by committing all Plan 06 files alongside Plan 07 Task 1.

## Next Phase Readiness

- Complete client-facing mobile UI for Phase 4. CRM, request review, and in-app request form all built.
- Phase 4 is now functionally complete: dual-flow job creation (client-initiated → admin review → wizard + company-assigned wizard), job pipeline (kanban/list), contractor job view.
- Phase 5 (Calendar UI) can proceed — it depends on scheduling bookings which Phase 3 provided.
- Phase 7 (Client Portal) will extend `JobRequestFormScreen` and `ClientDetailScreen` for the full client-facing experience.

## Self-Check: PASSED

All 6 plan-required files verified on disk:
- `mobile/lib/features/jobs/presentation/providers/crm_providers.dart` FOUND
- `mobile/lib/features/jobs/presentation/screens/client_crm_screen.dart` FOUND
- `mobile/lib/features/jobs/presentation/screens/client_detail_screen.dart` FOUND
- `mobile/lib/features/jobs/presentation/screens/request_review_screen.dart` FOUND
- `mobile/lib/features/client/presentation/screens/job_request_form_screen.dart` FOUND
- `mobile/lib/features/jobs/presentation/widgets/client_card.dart` FOUND

Both task commits exist:
- `cf064f5` — feat(04-07): CRM providers, client screens, and job pipeline foundation
- `42ece73` — feat(04-07): request review queue and in-app job request form

---
*Phase: 04-job-lifecycle*
*Completed: 2026-03-09*
