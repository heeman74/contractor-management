---
phase: 07-client-portal-and-notifications
plan: 02
subsystem: mobile-client-portal
tags: [flutter, riverpod, client-portal, job-detail, photo-viewer, delay-visibility]
dependency_graph:
  requires:
    - 06-field-workflow (note_providers, attachment_dao, note_dao)
    - 04-job-lifecycle (JobEntity, JobStatus, JobRequestEntity)
  provides:
    - ClientJobDetailScreen (/client/jobs/:id)
    - PhotoViewerScreen (/photo-viewer)
    - ClientPortalScreen (enhanced)
  affects:
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/core/routing/route_names.dart
    - mobile/lib/features/jobs/data/job_dao.dart
tech_stack:
  added:
    - InteractiveViewer (pinch-to-zoom, Flutter built-in)
    - PageView (photo swipe navigation, Flutter built-in)
  patterns:
    - StreamProvider.autoDispose.family for clientJobProvider, photosForJobProvider
    - GetIt -> Riverpod bridge pattern (documented in providers)
    - Offline-first: all data via Drift streams, RefreshIndicator triggers syncNow()
key_files:
  created:
    - mobile/lib/features/client/presentation/screens/client_job_detail_screen.dart
    - mobile/lib/features/client/presentation/screens/photo_viewer_screen.dart
    - mobile/lib/features/client/presentation/providers/client_providers.dart
    - mobile/lib/features/client/presentation/widgets/job_progress_stepper.dart
    - mobile/lib/features/client/presentation/widgets/delay_banner.dart
    - mobile/lib/features/client/presentation/widgets/photo_timeline.dart
    - mobile/lib/features/client/presentation/widgets/client_notes_tab.dart
  modified:
    - mobile/lib/features/client/presentation/screens/client_portal_screen.dart
    - mobile/lib/features/jobs/data/job_dao.dart
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/core/routing/route_names.dart
decisions:
  - "photo_view package not used — InteractiveViewer + PageView provide pinch-to-zoom and swipe natively without an extra dependency"
  - "photosForJobProvider accesses NoteDao/AttachmentDao via GetIt directly (not via notesForJobProvider) — avoids Riverpod 3 StreamProvider.stream getter issue; documented tradeoff"
  - "Delay banner shows only for non-complete/non-invoiced jobs — resolved jobs don't need visible delay warnings"
  - "ClientPortalScreen uses clientJobDetailPath() not jobDetailPath() — client sees their read-only detail, not the admin detail screen"
metrics:
  duration: "8 min"
  completed_date: "2026-03-13"
  tasks_completed: 2
  files_modified: 11
---

# Phase 7 Plan 02: Client Portal UI Summary

Client job detail screen with progress stepper, photo timeline, activity log, delay visibility, and enhanced portal list with pending requests and ETA display.

## What Was Built

### ClientJobDetailScreen
Full client-specific job detail at `/client/jobs/:id`. Watches `clientJobProvider(jobId)` for live updates. Layout:
- Cancelled jobs: red banner instead of stepper
- `JobProgressStepper`: 5-stage horizontal bar (Quote → Scheduled → In Progress → Complete → Invoiced)
- `DelayBanner`: amber warning with reason and original→new ETA comparison; expandable prior delays
- TabBar with Photos (count badge), Notes, Details tabs
- "Last updated X ago" relative timestamp
- Pull-to-refresh via `SyncEngine.syncNow()`

### PhotoViewerScreen
Full-screen gallery at `/photo-viewer`. Uses Flutter's built-in `InteractiveViewer` (pinch-to-zoom) + `PageView` (swipe navigation). "X of Y" counter updates on swipe. Caption overlay when attachment has caption. Download button shows snackbar explaining long-press save.

### Supporting Widgets
- `JobProgressStepper`: Horizontal row with circles (filled=done, outlined=future) and connecting lines
- `DelayBanner`: Amber container; shows latest delay with expandable history via InkWell toggle
- `PhotoTimeline`: 3-column GridView; only `uploaded` attachments with `remoteUrl`; empty state with camera icon
- `ClientNotesTab`: Merges contractor notes + delay events + status transitions from `statusHistory`, sorted newest-first

### Enhanced ClientPortalScreen
- "Pending Requests" section at top (hidden when empty): shows pending/declined/request_more_info requests
- `_RequestCard`: Status badge (amber/red/blue), urgency badge, decline reason/more-info message
- `_JobCard`: ETA date below status chip, orange warning icon for delayed jobs
- Completed/invoiced jobs: 60% opacity + green checkmark trailing
- Tapping navigates to `clientJobDetailPath(job.id)` (not admin `/jobs/:id`)

### Route Changes
- `RouteNames.clientJobDetail = '/client/jobs/:id'` + `clientJobDetailPath()`
- `RouteNames.photoViewer = '/photo-viewer'`
- GoRouter Branch 6: added `/client/jobs/:id` route
- GoRouter top-level push: `/photo-viewer` route

### JobDao Additions
- `watchJobById(jobId)`: Single-job stream for `clientJobProvider`
- `watchRequestsForClient(clientId)`: Streams pending/declined/request_more_info requests by clientId (distinct from admin's `watchPendingRequestsByCompany`)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] photo_view package unavailable (no pub get in environment)**
- **Found during:** Task 1 — PhotoViewerScreen implementation
- **Issue:** `photo_view: ^0.15.0` added to pubspec.yaml triggered analyzer errors because `flutter pub get` cannot run without Flutter SDK installed
- **Fix:** Removed photo_view dependency; used Flutter's built-in `InteractiveViewer` (pinch-to-zoom) and `PageView` (swipe navigation). Provides equivalent UX without an external package.
- **Files modified:** `pubspec.yaml` (reverted), `photo_viewer_screen.dart`
- **Commit:** ea014d6

**2. [Rule 1 - Bug] Riverpod 3 StreamProvider.stream getter not available**
- **Found during:** Task 1 — `photosForJobProvider` derivation
- **Issue:** `notesForJobProvider(jobId).stream` undefined in Riverpod 3 — `StreamProvider` family instances expose `AsyncValue`, not a direct `Stream`
- **Fix:** Rewrote `photosForJobProvider` to access NoteDao and AttachmentDao directly via GetIt (same pattern as other providers in the codebase), avoiding the Riverpod 3 stream chaining limitation. Documented GetIt tradeoff per CLAUDE.md.
- **Files modified:** `client_providers.dart`
- **Commit:** ea014d6

**3. [Rule 1 - Bug] JobEntity has no `address` field**
- **Found during:** Task 1 — Details tab in `_DetailsTab`
- **Issue:** Plan spec referenced `job.address` but `JobEntity` has `gpsAddress` (reverse-geocoded), not a generic `address` field
- **Fix:** Removed address row from Details tab; kept `gpsAddress` (when available) as "Location" field
- **Files modified:** `client_job_detail_screen.dart`
- **Commit:** ea014d6

## Self-Check: PASSED

All created files verified present. Commits ea014d6 and 0c69219 verified in git log. Zero dart analyze errors in lib/features/client/ and lib/core/routing/.
