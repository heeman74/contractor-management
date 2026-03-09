---
phase: 04-job-lifecycle
plan: "09"
subsystem: ui
tags: [flutter, image_picker, go_router, client-portal, job-request]

# Dependency graph
requires:
  - phase: 04-job-lifecycle
    provides: JobRequestFormScreen with offline-first Drift submission, client portal placeholder screen, app_router GoRouter with role-gated branches

provides:
  - image_picker ^1.1.2 dependency for device gallery photo selection
  - Functional _pickPhoto() using ImagePicker.pickImage(gallery) replacing SnackBar stub
  - Image.file() ClipRRect thumbnails showing actual selected photos
  - RouteNames.jobRequestForm = '/client/request' constant
  - GoRoute for /client/request registered in Branch 6 (client) of StatefulShellRoute
  - ClientPortalScreen "Submit a Job Request" FilledButton.icon navigating to jobRequestForm
affects: [phase-05-calendar-ui, CLNT-04 requirement]

# Tech tracking
tech-stack:
  added: [image_picker ^1.1.2]
  patterns: [ImagePicker.pickImage for gallery selection, Image.file with ClipRRect for file-based thumbnails]

key-files:
  created: []
  modified:
    - mobile/pubspec.yaml
    - mobile/lib/features/client/presentation/screens/job_request_form_screen.dart
    - mobile/lib/core/routing/route_names.dart
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/features/client/presentation/screens/client_portal_screen.dart

key-decisions:
  - "image_picker ^1.1.2 added as production dependency (not dev) — required at runtime for gallery access"
  - "No try/catch around ImagePicker.pickImage — errors propagate naturally per CLAUDE.md error handling rules"
  - "jobRequestForm route placed as sibling (not child) of clientPortal in Branch 6 — both are top-level /client/* paths"
  - "context.go() used for portal-to-form navigation — replaces current shell route, appropriate for non-nested navigation"

patterns-established:
  - "Gap closure pattern: replace SnackBar stubs with real plugin implementations once dependency is added to pubspec.yaml"

requirements-completed: [CLNT-04]

# Metrics
duration: 2min
completed: 2026-03-09
---

# Phase 4 Plan 09: Gap Closure — Photo Picker and Route Registration Summary

**image_picker ^1.1.2 integrated with real gallery picker and Image.file thumbnails; /client/request GoRoute registered with FilledButton entry point from ClientPortalScreen**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-09T04:40:26Z
- **Completed:** 2026-03-09T04:42:58Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Closed CLNT-04 gap 1: replaced SnackBar stub in `_pickPhoto()` with real `ImagePicker().pickImage(source: ImageSource.gallery)` and `Image.file()` thumbnails showing actual selected photos
- Closed CLNT-04 gap 2: registered `/client/request` GoRoute in Branch 6, added `RouteNames.jobRequestForm` constant, and added "Submit a Job Request" `FilledButton.icon` to `ClientPortalScreen`
- All 7 plan verification checks pass; role gating for `/client/*` is automatic via existing `_checkRoleAccess`

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement functional photo picker in JobRequestFormScreen** - `ef98c09` (feat)
2. **Task 2: Register GoRoute for JobRequestFormScreen and add navigation entry point** - `0c0e459` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `mobile/pubspec.yaml` - Added `image_picker: ^1.1.2` to dependencies
- `mobile/lib/features/client/presentation/screens/job_request_form_screen.dart` - Added `dart:io` and `image_picker` imports; replaced stub `_pickPhoto()` with real `ImagePicker.pickImage(gallery)`; replaced `Icon` placeholder thumbnails with `Image.file()` `ClipRRect` widgets
- `mobile/lib/core/routing/route_names.dart` - Added `jobRequestForm = '/client/request'` constant under Client-only routes section
- `mobile/lib/core/routing/app_router.dart` - Added `JobRequestFormScreen` import; added `GoRoute(path: RouteNames.jobRequestForm)` in Branch 6 routes list
- `mobile/lib/features/client/presentation/screens/client_portal_screen.dart` - Added `go_router` and `RouteNames` imports; added `FilledButton.icon` "Submit a Job Request" with `context.go(RouteNames.jobRequestForm)`

## Decisions Made
- image_picker ^1.1.2 added as a production dependency — required at runtime for gallery access, not a dev-only tool
- No try/catch around `ImagePicker.pickImage` — errors propagate naturally per CLAUDE.md error handling rules (no silent swallowing)
- `jobRequestForm` route placed as a sibling (not child) of `clientPortal` in Branch 6 — both are top-level `/client/*` paths with their own full-screen presence
- `context.go()` used for portal-to-form navigation — replaces current shell route location, consistent with how other top-level routes are navigated

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- CLNT-04 is fully satisfied: backend + web form + admin review (Plans 01-08) + in-app mobile flow (Plan 09) all verified
- Phase 4 gap closure complete — all VERIFICATION.md truths 1-5 can now be marked VERIFIED
- Phase 5 (Calendar UI) can proceed; client portal branch structure is now established with proper routing

## Self-Check: PASSED

All files verified present. All task commits verified in git history.

---
*Phase: 04-job-lifecycle*
*Completed: 2026-03-09*
