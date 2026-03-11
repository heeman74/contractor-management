---
phase: 06-field-workflow
plan: 04
subsystem: mobile-presentation
tags: [flutter, drawing-pad, gps, permissions, landscape, offline-first]
dependency_graph:
  requires: [06-02]
  provides: [drawing-pad-screen, gps-capture-button, job-entity-gps-fields]
  affects: [06-05, 06-06]
tech_stack:
  added: []
  patterns: [SystemChrome orientation lock, CustomPaint grid overlay, Geolocator permission flow, transactional outbox GPS update]
key_files:
  created:
    - mobile/lib/features/jobs/presentation/screens/drawing_pad_screen.dart
    - mobile/lib/features/jobs/presentation/widgets/gps_capture_button.dart
  modified:
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/core/routing/route_names.dart
    - mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart
    - mobile/android/app/src/main/AndroidManifest.xml
    - mobile/lib/features/jobs/domain/job_entity.dart
    - mobile/lib/features/jobs/data/job_dao.dart
decisions:
  - "DrawingPadScreen uses _Tool enum for UI highlighting; DrawingController manages the active paint content internally"
  - "Grid overlay is a separate CustomPaint layer on the Stack — excluded from DrawingController canvas and therefore from PNG export"
  - "GpsCaptureButton is ConsumerStatefulWidget (not ConsumerWidget) — manages isLoading state for button feedback during async GPS acquisition"
  - "GPS fields (gpsLatitude, gpsLongitude, gpsAddress) added to JobEntity — missing from Plan 02 generated files; manually updated .freezed.dart and .g.dart since build_runner unavailable"
metrics:
  duration: 35min
  completed: "2026-03-11"
  tasks: 2
  files: 8
---

# Phase 6 Plan 4: Drawing Pad and GPS Capture Summary

Full-screen landscape drawing pad with pen/shapes/PNG export and one-tap GPS coordinate capture with offline storage and reverse-geocode-pending display.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | DrawingPadScreen with landscape lock, toolbar, grid, PNG export, route | b0d390c | 3 files |
| 2 | GpsCaptureButton with permission flow, overwrite guard, Details tab integration | 2e51a1f | 5 files |

## What Was Built

### DrawingPadScreen (Plan FIELD-03)

- `drawing_pad_screen.dart`: Full-screen landscape StatefulWidget
- **Orientation:** `SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight])` in `initState()`, always restores to `portraitUp` in `dispose()`
- **Tools:** Pen, Eraser, Text, Line, Rectangle, Circle, Arrow via `_Tool` enum + `DrawingController.setPaintContent()`
- **Colors:** 8 preset swatches (black, red, blue, green, orange, purple, brown, white) — circle tap targets
- **Thickness:** 3 ChoiceChip presets (Thin 1px, Med 3px, Thick 6px)
- **Text tool:** font size `Slider` (8–72) shown only when Text tool is active
- **Grid:** `CustomPaint` with `_GridPainter` on a separate `Stack` layer — NOT part of `DrawingController` canvas, excluded from PNG export
- **PNG export:** `_controller.getImageData()` → write to `{appSupportDirectory}/drawings/{uuid}.png` → `Navigator.pop(context, filePath)`
- **Discard guard:** `AlertDialog` with Cancel/Discard if `_controller.getHistory.isNotEmpty` on close
- **Route:** `GoRoute(path: '/drawing-pad', name: RouteNames.drawingPad)` added as top-level push route

### GpsCaptureButton (Plan FIELD-02)

- `gps_capture_button.dart`: `ConsumerStatefulWidget` — manages `_isLoading` for UI feedback
- **Permission flow:**
  - Location services disabled → SnackBar "Enable location services in Settings."
  - Permission denied → `Geolocator.requestPermission()`; if still denied, silently abort
  - Permission `deniedForever` → `AlertDialog` with "Open Settings" calling `Geolocator.openAppSettings()`
- **Overwrite guard:** `AlertDialog` "Replace existing location?" shown when any GPS data already exists
- **Loading state:** `CircularProgressIndicator` in button + disabled while acquiring
- **Storage:** `JobDao.updateJobGps(jobId, lat, lng)` — transactional outbox dual-write sets `gps_address=null` to trigger backend geocode on sync
- **Display:** `_GpsDisplay` widget — geocoded address string if available; lat/lng + "(address pending sync)" in italic gray if only coordinates; hidden if no GPS data
- **Android permissions:** `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION` in `AndroidManifest.xml`
- **Integration:** Added as a `GpsCaptureButton(job: job)` card below the job details card in `_DetailsTab`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] Added GPS fields to JobEntity**
- **Found during:** Task 2 — GpsCaptureButton needs to read `gpsLatitude`, `gpsLongitude`, `gpsAddress` from the job entity for display logic and overwrite guard
- **Issue:** `JobEntity` in `job_entity.dart` was missing the three GPS fields that were added to the `Jobs` Drift table in Plan 02. The generated `.freezed.dart` and `.g.dart` files were also out of sync. The `_rowToJobEntity` mapper in `job_dao.dart` didn't map the GPS columns.
- **Fix:** Added `double? gpsLatitude`, `double? gpsLongitude`, `String? gpsAddress` to the `JobEntity` factory constructor, manually updated both generated files (`.freezed.dart` for mixin/class/copyWith/equality/toString, `.g.dart` for fromJson/toJson), and updated `JobDao._rowToJobEntity` to map the three columns from the Drift row.
- **Files modified:** `job_entity.dart`, `job_entity.freezed.dart` (gitignored), `job_entity.g.dart` (gitignored), `job_dao.dart`
- **Commits:** 2e51a1f

## Self-Check: PASSED

- [x] `drawing_pad_screen.dart` exists at expected path
- [x] `gps_capture_button.dart` exists at expected path
- [x] Commits b0d390c and 2e51a1f exist in git log
- [x] `RouteNames.drawingPad` added to route_names.dart
- [x] `/drawing-pad` route in app_router.dart
- [x] Location permissions in AndroidManifest.xml
- [x] `GpsCaptureButton` imported and used in job_detail_screen.dart
- [x] GPS fields in JobEntity
- [x] `_rowToJobEntity` mapper updated in job_dao.dart
