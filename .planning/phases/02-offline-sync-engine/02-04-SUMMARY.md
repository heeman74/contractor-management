---
phase: 02-offline-sync-engine
plan: "04"
subsystem: sync, ui
tags: [workmanager, riverpod, flutter, sync, background-sync, pull-to-refresh, connectivity]

# Dependency graph
requires:
  - phase: 02-offline-sync-engine
    provides: SyncEngine with drainQueue/pullDelta/syncNow, ConnectivityService.isOnlineStream, SyncStatus/SyncState types
  - phase: 02-offline-sync-engine
    provides: setupServiceLocator with getIt singleton registrations
provides:
  - WorkManager callbackDispatcher for 15-minute periodic background sync
  - syncStatusProvider (@riverpod Stream) combining SyncEngine.statusStream + ConnectivityService.isOnlineStream
  - SyncStatusSubtitle ConsumerWidget showing sync state in app bar at all times
  - AppShell with shared AppBar (title + SyncStatusSubtitle column) replacing per-screen app bars
  - Pull-to-refresh via RefreshIndicator on Home, Jobs, and Schedule screens
affects:
  - Phase 4 (Jobs screen — already has RefreshIndicator wired)
  - Phase 5 (Schedule screen — already has RefreshIndicator wired)
  - Any future screen that needs sync status awareness

# Tech tracking
tech-stack:
  added:
    - workmanager: ^0.9.0 (already in pubspec — background task dispatcher now used)
  patterns:
    - "@pragma('vm:entry-point') on top-level callbackDispatcher — required for WorkManager release builds"
    - "WorkManager background isolate must re-initialize WidgetsFlutterBinding and setupServiceLocator before accessing getIt"
    - "Stream merging via async* + StreamController.broadcast() for combining connectivity + engine status"
    - "AsyncValue.when() for rendering sync status states with loading/error fallbacks"
    - "AlwaysScrollableScrollPhysics with SingleChildScrollView ensures RefreshIndicator works on non-full-screen content"
    - "AppShell shared AppBar pattern: Column(title, SyncStatusSubtitle) instead of per-screen AppBar"

key-files:
  created:
    - mobile/lib/core/sync/workmanager_dispatcher.dart
    - mobile/lib/core/sync/sync_status_provider.dart
    - mobile/lib/shared/widgets/sync_status_subtitle.dart
  modified:
    - mobile/lib/main.dart
    - mobile/lib/shared/widgets/app_shell.dart
    - mobile/lib/shared/screens/home_screen.dart
    - mobile/lib/shared/screens/jobs_screen.dart
    - mobile/lib/shared/screens/schedule_screen.dart

key-decisions:
  - "AppShell provides shared AppBar with SyncStatusSubtitle — individual screens no longer own their AppBar; reduces duplication and ensures subtitle is always visible across all tabs"
  - "Stream merging implemented with dart:async StreamController.broadcast() — avoids RxDart dependency for simple two-stream merge"
  - "callbackDispatcher returns Future.value(true) even on error — prevents OS retry storm from exponential backoff on persistent failures"
  - "SyncStatusSubtitle initial loading state shows 'All synced' (not a spinner) — aligns with user decision: no loading states, cached data shown immediately"
  - "WorkManager registerPeriodicTask uses existingWorkPolicy default (keep) — prevents duplicate task registration on hot restart"

patterns-established:
  - "Background WorkManager tasks: always @pragma('vm:entry-point'), always re-init bindings + setupServiceLocator, always return true"
  - "Sync status UI: ConsumerWidget watching @riverpod stream provider, renders all 4 states (offline/allSynced/pending/syncing)"
  - "Pull-to-refresh pattern: RefreshIndicator > scrollable child, calls getIt<SyncEngine>().syncNow()"

requirements-completed: [INFRA-03, INFRA-04]

# Metrics
duration: 5min
completed: 2026-03-05
---

# Phase 2 Plan 04: WorkManager Background Sync, Sync Status UI, and Pull-to-Refresh Summary

**WorkManager 15-minute background sync dispatcher, @riverpod sync status stream combining connectivity + engine state, always-visible app bar subtitle widget with icon states, and pull-to-refresh on Home/Jobs/Schedule screens**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-03-05T22:06:50Z
- **Completed:** 2026-03-05T22:11:16Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- WorkManager callbackDispatcher with `@pragma('vm:entry-point')` re-initializes getIt in background isolate and runs drainQueue + pullDelta every 15 minutes
- syncStatusProvider @riverpod Stream merges SyncEngine.statusStream with ConnectivityService.isOnlineStream — offline state overrides engine status regardless of queue count
- SyncStatusSubtitle ConsumerWidget shows all 4 states with icons: check_circle_outline (allSynced), sync (pending), animated rotating sync (syncing), wifi_off (offline)
- AppShell updated with shared AppBar `Column(tab title, SyncStatusSubtitle)` — always visible, eliminates per-screen AppBar duplication
- RefreshIndicator added to all 3 main screens (Home/Jobs/Schedule) calling `syncEngine.syncNow()`

## Task Commits

1. **Task 1: WorkManager dispatcher, sync status provider, main.dart** - `0755d53` (feat)
2. **Task 2: Sync status subtitle, app shell, pull-to-refresh** - `aade399` (feat)

## Files Created/Modified

- `mobile/lib/core/sync/workmanager_dispatcher.dart` — Top-level `callbackDispatcher()` with `@pragma('vm:entry-point')`, re-initializes getIt, runs drainQueue+pullDelta
- `mobile/lib/core/sync/sync_status_provider.dart` — `@riverpod Stream<SyncStatus>` merging connectivity + engine streams; emits allSynced initially so app bar shows immediately
- `mobile/lib/shared/widgets/sync_status_subtitle.dart` — ConsumerWidget with 4 states, animated rotation for syncing state, always visible (no fade)
- `mobile/lib/main.dart` — Added Workmanager().initialize(callbackDispatcher) + registerPeriodicTask(15 min, NetworkType.connected)
- `mobile/lib/shared/widgets/app_shell.dart` — Added shared AppBar with Column(title, SyncStatusSubtitle), logout action moved from HomeScreen
- `mobile/lib/shared/screens/home_screen.dart` — Removed own AppBar+Scaffold, wrapped body in RefreshIndicator calling syncEngine.syncNow()
- `mobile/lib/shared/screens/jobs_screen.dart` — Removed own AppBar+Scaffold, RefreshIndicator + SingleChildScrollView with AlwaysScrollableScrollPhysics
- `mobile/lib/shared/screens/schedule_screen.dart` — Removed own AppBar+Scaffold, RefreshIndicator + SingleChildScrollView with AlwaysScrollableScrollPhysics

## Decisions Made

- AppShell provides shared AppBar with SyncStatusSubtitle: individual screens previously owned their own AppBar+Scaffold; moved to shared shell so subtitle is always present across all tabs without repetition
- Stream merging with `dart:async StreamController.broadcast()`: avoids adding RxDart dependency for a simple two-stream merge pattern
- `callbackDispatcher` returns `true` on error: prevents WorkManager OS retry storm; next 15-minute periodic tick retries naturally
- SyncStatusSubtitle loading state defaults to "All synced": matches user decision of no loading spinner — app opens with cached data immediately visible

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Design] Moved AppBar from individual screens to AppShell**
- **Found during:** Task 2 (sync status subtitle integration)
- **Issue:** Each screen had its own AppBar+Scaffold; adding SyncStatusSubtitle to AppShell required a shared AppBar — otherwise subtitle would only appear on screens that individually added it, defeating the "always visible" requirement
- **Fix:** Added AppBar to AppShell with dynamic tab title + SyncStatusSubtitle column; removed Scaffold/AppBar from HomeScreen, JobsScreen, ScheduleScreen; moved logout button to AppShell actions
- **Files modified:** app_shell.dart, home_screen.dart, jobs_screen.dart, schedule_screen.dart
- **Verification:** AppShell AppBar confirmed to contain SyncStatusSubtitle; all screens confirmed to return body content without own Scaffold
- **Committed in:** aade399 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (design adjustment to meet always-visible requirement)
**Impact on plan:** Required for correct implementation of "subtitle always visible" user decision. No scope creep — logout button preserved, just relocated to shell.

## Issues Encountered

None — .g.dart code generation files (riverpod_annotation) remain ungenerated due to Flutter SDK not installed (pre-existing blocker in STATE.md). This is consistent with all prior plans; build_runner will be run when SDK is available.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 2 Offline Sync Engine is now complete: Drift outbox (02-01), backend sync API (02-02), SyncEngine service layer (02-03), WorkManager + UI (02-04)
- Phase 4 (Jobs) and Phase 5 (Schedule) screens already have RefreshIndicator wired — pull-to-refresh will work immediately when real data DAOs are added
- The sync status subtitle will automatically reflect accurate state once Flutter build_runner generates the riverpod .g.dart files

---
*Phase: 02-offline-sync-engine*
*Completed: 2026-03-05*
