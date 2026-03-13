---
phase: 07-client-portal-and-notifications
verified: 2026-03-13T00:00:00Z
status: human_needed
score: 5/5 must-haves verified
re_verification: false
human_verification:
  - test: "Build and run the Flutter app on an Android device/emulator; log in as a client user and check the portal list shows active jobs with ETA dates and orange warning icons on delayed jobs."
    expected: "Job cards display status chip, ETA date, and orange warning icon (for delayed jobs). Completed/invoiced jobs appear at 60% opacity with a green checkmark."
    why_human: "Opacity, color values, and icon rendering require visual inspection on device."
  - test: "From the client portal list, tap an active job to open ClientJobDetailScreen. Verify the 5-step progress stepper is visible and the current stage is highlighted."
    expected: "Horizontal step bar with 5 stages (Quote, Scheduled, In Progress, Complete, Invoiced). Current stage shows a filled circle; future stages show grey outlined circles."
    why_human: "Stepper visual layout and color coding cannot be asserted without rendering."
  - test: "For a job with uploaded photos (remoteUrl set), tap the Photos tab in ClientJobDetailScreen and verify a 3-column photo grid is visible. Tap a photo to open PhotoViewerScreen."
    expected: "Photos grid with thumbnails; tapping opens full-screen viewer with pinch-to-zoom (InteractiveViewer) and swipe navigation (PageView). 'X of Y' counter updates on swipe."
    why_human: "Photo grid rendering, pinch-to-zoom gesture, and swipe navigation are device interactions."
  - test: "For a delayed job, verify the orange delay banner in ClientJobDetailScreen shows reason and original vs new ETA. If there are 2+ delays, tap 'View previous delays (N)' to expand."
    expected: "Amber/orange banner with reason text, 'Original ETA: X -> New ETA: Y' comparison. Expandable history visible on tap."
    why_human: "Banner color and expand/collapse animation require visual verification."
  - test: "Set GOOGLE_APPLICATION_CREDENTIALS to a valid Firebase service account JSON and run the backend. Apply migration 0010 (`cd backend && uv run alembic upgrade head`). Log in on mobile and check backend logs for a POST to /api/v1/notifications/token."
    expected: "Backend logs show a 204 response for the device token registration. Migration 0010 applies cleanly."
    why_human: "Firebase connectivity and real device token registration require a live Firebase project and backend environment."
  - test: "Download google-services.json from Firebase Console and place it at mobile/android/app/google-services.json. Build and run the app, trigger a job status transition to 'scheduled' via the admin, and verify the client receives a push notification."
    expected: "A push notification appears with text referencing the job description. Tapping it navigates to /client/jobs/:id."
    why_human: "Real FCM delivery requires a live Firebase project. Cannot be automated without real Firebase credentials."
---

# Phase 7: Client Portal and Notifications Verification Report

**Phase Goal:** Clients can view live job status, progress photos, and delay reasons through the client-facing portal, and receive push notifications at every significant job milestone
**Verified:** 2026-03-13
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | Client opening the app sees the current status of their job with a progress indicator and the latest ETA | VERIFIED | `JobProgressStepper` widget (164 lines) renders 5-stage horizontal bar; `_JobCard` in `ClientPortalScreen` shows ETA date and delay warning icon; E2E tests `test_portal_shows_eta_on_cards`, `test_detail_shows_progress_stepper` pass |
| 2 | Client can scroll through a chronological photo timeline of their job's progress — photos added by contractors appear here | VERIFIED | `PhotoTimeline` widget (171 lines) renders 3-column `GridView.builder` with only `uploaded` attachments having `remoteUrl`; `PhotoViewerScreen` (159 lines) provides full-screen view; `photosForJobProvider` in `client_providers.dart` filters and sorts by chronological order; E2E tests `test_detail_photos_tab_count_badge`, `test_detail_photos_tab_empty_state`, `test_detail_photos_tab_only_uploaded` pass |
| 3 | When a contractor delays a job, the delay reason and updated ETA are visible to the client in the portal within one sync cycle | VERIFIED | `DelayBanner` widget (217 lines) parses `statusHistory` for `type=='delay'` entries and displays reason + ETA comparison; `ClientNotesTab` merges delay events into activity log; sync delta filtering (`client_user_id`) ensures client sees their own jobs' data on next sync; E2E tests `test_detail_delay_banner`, `test_detail_delay_banner_hidden_when_complete`, `test_detail_multiple_delays_expandable` pass |
| 4 | Client receives a push notification when their job is scheduled, when work starts, and when the job is marked complete | VERIFIED | `JobService.transition_status()` calls `NotificationService.send_job_notification()` on `scheduled`, `in_progress`, and `complete` transitions; `JobService.report_delay()` sends delayed event; `FcmService` registers token on every login/session-restore; backend integration tests verify notification dispatch on all 4 transitions (20 tests pass); real FCM delivery requires human verification (no live Firebase in test) |
| 5 | The client portal is gated by role — no contractor or admin data is accessible from the client view | VERIFIED | Sync router adds `client_user_id` filter for client-role users so delta sync returns only client's own jobs, notes, bookings, and attachments; `ClientPortalScreen` navigates to `/client/jobs/:id` not admin `/jobs/:id`; E2E role-gating tests `test_client_portal_screen_renders_for_client_role`, `test_client_detail_screen_accessible`, `test_client_detail_no_edit_actions` pass |

**Score:** 5/5 truths verified (automated evidence complete; FCM live delivery needs human confirmation)

### Required Artifacts

| Artifact | Lines | Status | Details |
|----------|-------|--------|---------|
| `backend/migrations/versions/0010_device_tokens.py` | — | VERIFIED | Migration creates `device_tokens` table with `user_id` FK, `platform` CHECK constraint, UNIQUE on `(user_id, token)`, RLS policy on `app.current_user_id` |
| `backend/app/features/notifications/service.py` | 214 | VERIFIED | `NotificationService(BaseService[DeviceToken])` with `upsert_token()` and `send_job_notification()`; graceful degradation when `GOOGLE_APPLICATION_CREDENTIALS` absent |
| `backend/app/features/notifications/router.py` | 39 | VERIFIED | `POST /api/v1/notifications/token` endpoint (status 204); registered in `main.py` |
| `backend/app/features/notifications/models.py` | 54 | VERIFIED | `DeviceToken` model inherits from `Base` (not `TenantScopedModel`); user-scoped |
| `backend/app/features/notifications/repository.py` | 70 | VERIFIED | `NotificationRepository(BaseRepository[DeviceToken])` with `get_tokens_for_user`, `upsert_token`, `delete_token` |
| `mobile/lib/features/client/presentation/screens/client_job_detail_screen.dart` | 361 | VERIFIED | Full client detail with `JobProgressStepper`, `DelayBanner`, 3 tabs (Photos, Notes, Details), pull-to-refresh |
| `mobile/lib/features/client/presentation/screens/photo_viewer_screen.dart` | 159 | VERIFIED | `InteractiveViewer` pinch-to-zoom + `PageView` swipe; "X of Y" counter; caption overlay |
| `mobile/lib/features/client/presentation/widgets/job_progress_stepper.dart` | 164 | VERIFIED | 5-stage horizontal bar with filled/outlined circles and connecting lines |
| `mobile/lib/features/client/presentation/widgets/delay_banner.dart` | 217 | VERIFIED | Amber banner with reason, ETA comparison, expandable prior delays |
| `mobile/lib/features/client/presentation/widgets/photo_timeline.dart` | 171 | VERIFIED | 3-column grid; only `uploaded` attachments with `remoteUrl`; empty state |
| `mobile/lib/features/client/presentation/widgets/client_notes_tab.dart` | 267 | VERIFIED | Merges contractor notes + delay events + status transitions; sorted newest-first |
| `mobile/lib/features/client/presentation/providers/client_providers.dart` | 97 | VERIFIED | `photosForJobProvider`, `clientJobProvider`, `clientPendingRequestsProvider` |
| `mobile/lib/core/notifications/fcm_service.dart` | 170 | VERIFIED | `registerToken()`, `setupMessageHandlers()`, `getInitialRoute()`; background handler with `@pragma('vm:entry-point')`; deep-links to `clientJobDetailPath` |
| `backend/tests/test_phase_7_e2e.py` | 486 | VERIFIED | 13 integration tests all passing |
| `backend/tests/test_notification_service.py` | 274 | VERIFIED | 7 unit tests all passing |
| `mobile/test/e2e/phase_7_client_portal_e2e_test.dart` | 643 | VERIFIED | 24 widget E2E tests all passing |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `backend/app/features/jobs/service.py` | `backend/app/features/notifications/service.py` | `NotificationService.send_job_notification()` called in `transition_status` and `report_delay` | WIRED | Both call sites confirmed at lines ~287-310 and ~463-475; wrapped in `try/except` for fire-and-forget |
| `backend/app/features/sync/service.py` | `Job.client_id` filter | `client_user_id` keyword param adds `WHERE Job.client_id == user_id` | WIRED | Parameter added to `get_jobs_since`, `get_bookings_since`, `get_job_notes_since`, `get_attachments_since`; subquery pattern for related entities |
| `backend/app/features/sync/router.py` | `SyncService` with `client_user_id` | Role check passes `client_user_id` when `"client" in current_user.roles` | WIRED | Confirmed at lines ~88-108 in sync router |
| `backend/app/main.py` | `POST /api/v1/notifications/token` | `include_router(notifications_router, prefix="/api/v1")` | WIRED | Confirmed at line 109 in `main.py` |
| `mobile/lib/features/client/presentation/screens/client_portal_screen.dart` | `ClientJobDetailScreen` | `context.push(RouteNames.clientJobDetailPath(job.id))` on card tap | WIRED | Confirmed at line 290 in portal screen |
| `mobile/lib/features/client/presentation/screens/client_portal_screen.dart` | `JobDao.watchRequestsForClient` | `clientPendingRequestsProvider` via `client_providers.dart` | WIRED | `watchRequestsForClient(clientId)` confirmed in `job_dao.dart` line 325 |
| `mobile/lib/core/notifications/fcm_service.dart` | `POST /api/v1/notifications/token` | `dioClient.instance.post('/notifications/token', ...)` | WIRED | Confirmed at line 99-101 in `fcm_service.dart` |
| `mobile/lib/core/notifications/fcm_service.dart` | `mobile/lib/core/routing/app_router.dart` | `router.go(RouteNames.clientJobDetailPath(jobId))` on notification tap | WIRED | Confirmed at line 168 in `fcm_service.dart` |
| `mobile/lib/features/auth/presentation/providers/auth_provider.dart` | `FcmService.registerToken()` | `_registerFcmToken()` called in login, register, and `_restoreSession()` | WIRED | Confirmed — fire-and-forget, does not block auth transitions |
| `mobile/lib/core/routing/app_router.dart` | `/client/jobs/:id` | `GoRoute(path: '/client/jobs/:id', builder: ClientJobDetailScreen)` | WIRED | Branch 6 route confirmed |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| CLNT-02 | 07-01, 07-03, 07-04 | Client notifications (job scheduled, started, completed, delayed) | SATISFIED | `NotificationService.send_job_notification()` wired into `JobService`; `FcmService` registers tokens on login; backend tests verify all 4 dispatch events; real FCM delivery needs human confirmation |
| CLNT-03 | 07-02, 07-04 | Client portal with live job status and progress photos | SATISFIED | `ClientPortalScreen` (enhanced) + `ClientJobDetailScreen` + `PhotoTimeline` fully implemented; 24 Flutter E2E tests pass |
| CLNT-05 | 07-01, 07-02, 07-04 | Delay reasons and updated ETAs visible to clients in portal | SATISFIED | `DelayBanner` renders delay reason + ETA comparison; `SyncService` client_user_id filtering ensures client receives their own delayed job data; backend sync filtering integration tests pass |

No orphaned requirements: CLNT-02, CLNT-03, CLNT-05 are the only Phase 7 requirements per REQUIREMENTS.md traceability table, and all three are claimed and verified.

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| `mobile/lib/features/client/presentation/screens/photo_viewer_screen.dart` | `always_put_required_named_parameters_first` lint (info) | Info | Style only; no functional impact |
| `mobile/lib/features/client/presentation/widgets/client_notes_tab.dart` | `always_put_required_named_parameters_first` lint (info) | Info | Style only; no functional impact |
| `mobile/lib/features/client/presentation/widgets/delay_banner.dart` | `always_put_required_named_parameters_first` lint (info) | Info | Style only; no functional impact |
| `mobile/lib/features/client/presentation/widgets/job_progress_stepper.dart` | `always_put_required_named_parameters_first` lint (info) | Info | Style only; no functional impact |
| `mobile/lib/features/client/presentation/widgets/photo_timeline.dart` | `always_put_required_named_parameters_first` lint (info) | Info | Style only; no functional impact |
| `mobile/android/app/google-services.json` | File missing — user must download from Firebase Console | Info | FCM will not work without this file; expected — documented in Plan 03 `user_setup` |

No blockers or warnings found. All dart analyze issues are `info`-level style hints. No `TODO`/`FIXME`/placeholder patterns found in Phase 7 files. No stub implementations detected.

### Human Verification Required

#### 1. Client portal visual layout

**Test:** Log in as a client user on the Flutter app. Navigate to the client portal (bottom nav tab). Verify job cards show status chip, ETA date, and orange warning icon for delayed jobs. Verify completed/invoiced jobs appear dimmed.
**Expected:** ETA date visible below the status chip on each card; orange `Icons.warning_amber_rounded` visible on delayed jobs; completed/invoiced jobs at 60% opacity with green `Icons.check_circle` trailing icon.
**Why human:** Color values, opacity, and icon rendering require visual inspection.

#### 2. Job detail progress stepper

**Test:** Tap an active job card to open `ClientJobDetailScreen`. Verify the 5-stage horizontal stepper is visible with the correct stage highlighted.
**Expected:** Five stages (Quote, Scheduled, In Progress, Complete, Invoiced) in a horizontal row. Completed stages show filled primary-color circles with check icons. Current stage shows filled circle with number. Future stages show grey outlined circles.
**Why human:** Color gradients, circle styling, and connecting-line rendering require device-level visual check.

#### 3. Photo timeline and full-screen viewer

**Test:** For a job with uploaded contractor photos, open the Photos tab in the job detail screen. Verify a grid of photo thumbnails appears. Tap a photo to open the full-screen viewer.
**Expected:** 3-column grid with `Image.network` thumbnails. Full-screen viewer with pinch-to-zoom (InteractiveViewer) and swipe navigation (PageView). "X of Y" counter updates on swipe. Caption overlay visible when attachment has caption.
**Why human:** Network image loading, pinch-to-zoom gesture, and swipe interaction require real device testing.

#### 4. Delay banner appearance and expand behavior

**Test:** Open a delayed job's detail screen. Verify the amber delay banner is shown below the stepper (only when job is not complete/invoiced). If the job has multiple delays, tap "View previous delays (N)" and verify expansion.
**Expected:** Amber/orange container with warning icon, delay reason text, and "Original ETA: X -> New ETA: Y" comparison. Tapping "View previous delays" expands to show full delay history.
**Why human:** Amber color rendering and expand/collapse animation require visual check.

#### 5. Firebase FCM live notification delivery

**Test:** (Requires Firebase project) Place `google-services.json` at `mobile/android/app/google-services.json`. Set `GOOGLE_APPLICATION_CREDENTIALS` to a valid service account JSON in the backend environment. Run `cd backend && uv run alembic upgrade head`. Build and run the app on Android. Log in as a client. Via admin, transition the client's job to "Scheduled". Check the client's device for a push notification.
**Expected:** Push notification arrives on the client's device with text referencing the job description. Tapping the notification deep-links to `/client/jobs/:id` (the client job detail screen).
**Why human:** Real FCM delivery requires a live Firebase project with valid credentials. Cannot be simulated in automated tests without real Firebase connectivity.

### Gaps Summary

No functional gaps found. All five observable truths are fully verified with passing automated tests:

- 20 backend integration tests pass (notification dispatch, sync filtering, token CRUD)
- 24 Flutter widget E2E tests pass (portal list, job detail, role gating)
- All key links confirmed wired — no orphaned artifacts
- All three requirement IDs (CLNT-02, CLNT-03, CLNT-05) satisfied

Status is `human_needed` because live FCM delivery and client portal visual correctness cannot be confirmed without a running Android device with a real Firebase project. The `google-services.json` file is intentionally absent (documented user setup step in Plan 03). All other infrastructure is in place and tested.

---

_Verified: 2026-03-13_
_Verifier: Claude (gsd-verifier)_
