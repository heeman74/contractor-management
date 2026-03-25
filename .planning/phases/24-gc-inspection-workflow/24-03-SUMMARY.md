---
phase: 24-gc-inspection-workflow
plan: "03"
subsystem: mobile-ui
tags: [flutter, inspection, punch-list, site-walk, approval-workflow]
dependency_graph:
  requires: [24-01, 24-02]
  provides: [inspection-ui, flag-capture-ui, punch-list-ui]
  affects: [task-detail-screen, project-detail-screen, trade-scope-detail-screen]
tech_stack:
  added: []
  patterns:
    - InspectionChecklist StatefulWidget with per-item checkbox state
    - showRejectionSheet modal bottom sheet pattern
    - showFlagCaptureFlow camera-first async flow (D-09)
    - PunchListCard with orange left edge differentiator
    - StreamProvider.autoDispose.family for _tradeScopeByIdProvider
key_files:
  created:
    - mobile/lib/features/projects/presentation/widgets/inspection_checklist.dart
    - mobile/lib/features/projects/presentation/widgets/rejection_bottom_sheet.dart
    - mobile/lib/features/projects/presentation/widgets/flag_capture_sheet.dart
    - mobile/lib/features/projects/presentation/widgets/site_walk_flag_section.dart
    - mobile/lib/features/projects/presentation/widgets/punch_list_card.dart
  modified:
    - mobile/lib/features/projects/presentation/screens/task_detail_screen.dart
    - mobile/lib/features/projects/presentation/screens/project_detail_screen.dart
    - mobile/lib/features/projects/presentation/screens/trade_scope_detail_screen.dart
    - mobile/lib/features/projects/data/trade_scope_dao.dart
decisions:
  - "UserRole.gc does not exist in the enum — GC role is UserRole.admin in this codebase. isGcOrAdmin uses admin role check."
  - "intl package not in pubspec — date formatting done with manual string interpolation using month name array."
  - "tradeScopeId in convertFlag punch item defaults to empty string; full scope picker deferred to follow-up (noted in code comment)."
  - "watchScopeById added to TradeScopeDao to support _tradeScopeByIdProvider for loading inspection checklist from scope."
metrics:
  duration: ~20 minutes
  completed: "2026-03-25"
  tasks: 3
  files_modified: 9
  files_created: 5
---

# Phase 24 Plan 03: GC Inspection Workflow Mobile UI Summary

Complete mobile UI for the GC inspection workflow — inspect bottom bar with checklist/time-summary/timeline on TaskDetailScreen, camera-first site walk flag capture with annotation flow on ProjectDetailScreen, and punch list item rendering with orange badge in TradeScopeDetailScreen.

## What Was Built

### Task 1: Inspection UI on TaskDetailScreen

**`inspection_checklist.dart`** — `InspectionChecklist` StatefulWidget:
- `kDefaultInspectionChecklist` with 4 universal items (quality, materials, cleanliness, safety)
- Per-item `CheckboxListTile` with `activeColor: colorScheme.primary`
- `onAllCheckedChanged` callback (enables/disables Approve button)
- `onResultsChanged` callback (emits `[{"item": ..., "checked": ...}]` for JSON storage)

**`rejection_bottom_sheet.dart`** — `showRejectionSheet` function:
- 6-item reason `DropdownButtonFormField` (rework_needed, quality_issue, wrong_materials, incomplete, safety_concern, other)
- Optional comment TextField (3 lines)
- Photo evidence via camera → `PhotoAnnotationScreen` → 64x64 thumbnail preview
- "Confirm Rejection" `ElevatedButton` disabled until reason selected

**`task_detail_screen.dart`** extended:
- `isGcOrAdmin` = `authState.roles.contains(UserRole.admin)` (GC = admin role)
- `showInspectBar` = task.status == 'complete' && isGcOrAdmin
- `showReworkBar` = task.status == 'rejected' && !isGcOrAdmin
- Total Time Logged section (D-02): shows estimated hours as reference
- Status Timeline section (D-02): Created / In Progress / Complete with timestamps
- Inspection Checklist section: loads `scope.inspectionChecklist` JSON or `kDefaultInspectionChecklist`
- Bottom bar: Reject (error color) + Approve (disabled until all checked) for GC; Start Rework for contractor
- `_handleApprove`: creates `TaskInspection` with decision='approved' via `taskInspectionDaoProvider`
- `_handleReject`: creates `TaskInspection` with decision='rejected' + updates task status to 'rejected'
- `_handleStartRework`: updates task status from 'rejected' → 'in_progress'
- `rejected` status badge color: `0xFFB71C1C` (deep red)

### Task 2a: Flag Capture + SiteWalkFlagSection on ProjectDetailScreen

**`flag_capture_sheet.dart`** — `showFlagCaptureFlow` function:
- Immediately calls `ImagePicker().pickImage(source: ImageSource.camera)` on entry (D-09 locked decision)
- If photo taken: pushes `PhotoAnnotationScreen` for optional annotation, pre-populates form
- If camera cancelled: opens flag form directly (description-only "skip photo" fallback)
- Flag form: description, severity dropdown (low/medium/high), optional location
- "Remove photo" TextButton in form to discard photo after capture
- On submit: calls `siteWalkFlagDaoProvider.createFlag(...)` with outbox dual-write

**`site_walk_flag_section.dart`** — `SiteWalkFlagSection` widget:
- `ConsumerWidget` watching `flagsForProjectProvider(projectId)`
- `ExpansionTile` with flag count `Chip`
- Per-flag `ListTile` with 8px severity dot (high=red, medium=amber, low=grey)
- "Convert to Punch Item" `TextButton` for GC/admin on open flags
- `convertFlag` call performs 4 atomic Drift writes via `SiteWalkFlagDao.convertFlag`
- Empty state: "No flags yet" + hint text

**`project_detail_screen.dart`** extended:
- `isGcOrAdmin` check from auth state
- "Flag Issue" `FloatingActionButton.extended` (red, only for GC/admin)
- `SiteWalkFlagSection` added below trade scope cards in ListView
- Two FABs stacked: Flag Issue (top) + Add Trade Scope (bottom)

### Task 2b: PunchListCard + Inline Punch List in TradeScopeDetailScreen

**`punch_list_card.dart`** — `PunchListCard` widget:
- `Card(elevation: 0)` with grey border
- `IntrinsicHeight` > `Row` with 4px orange left edge (`0xFFE65100`)
- Punch `Chip` (orange background), `_PriorityChip`, `_StatusChip` in `Wrap`
- Priority colors: urgent=`0xFFD32F2F`, high=`0xFFF57C00`, medium=`0xFF1565C0`, low=`0xFF9E9E9E`
- Status colors: open=grey, in_progress=`0xFF1565C0`, resolved=`0xFF388E3C`, verified=`0xFF1B5E20`
- Optional due date below badges

**`trade_scope_detail_screen.dart`** extended:
- Watches `punchItemsByScopeProvider(scopeId)` alongside `tasksProvider`
- "Punch List" section header rendered only when punch items exist
- `PunchListCard` for each item, tappable → `_PunchItemDetailSheet`
- `_PunchItemDetailSheet`: full description, status update dropdown
  - Contractor: open/in_progress/resolved
  - GC/admin: also verified
- Task rows now navigate to `TaskDetailScreen` via `RouteNames.taskDetailPath`

### Supporting Change

**`trade_scope_dao.dart`**: Added `watchScopeById(String scopeId)` stream method for single-scope lookup in TaskDetailScreen's `_tradeScopeByIdProvider`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] UserRole.gc does not exist**
- **Found during:** Task 1 compilation
- **Issue:** Plan specified `UserRole.gc` but the enum only has `admin`, `contractor`, `client`. GC = admin in this codebase.
- **Fix:** Replaced `UserRole.gc` check with `UserRole.admin` throughout all new files
- **Files modified:** task_detail_screen.dart, project_detail_screen.dart, trade_scope_detail_screen.dart

**2. [Rule 3 - Blocking] `intl` package not in pubspec**
- **Found during:** Task 1 compilation
- **Issue:** Plan specified `DateFormat.yMMMd().add_jm()` from `intl` package, not a project dependency
- **Fix:** Replaced with manual date formatting using month name array — no new dependency needed
- **Files modified:** task_detail_screen.dart

**3. [Rule 3 - Blocking] `watchScopeById` missing from TradeScopeDao**
- **Found during:** Task 1 provider implementation
- **Issue:** `_tradeScopeByIdProvider` required a single-scope stream but `TradeScopeDao` only had `watchScopesByProject`
- **Fix:** Added `watchScopeById(String scopeId)` stream method using `watchSingleOrNull()`
- **Files modified:** trade_scope_dao.dart

**4. [Rule 1 - Bug] `DropdownButtonFormField.value` deprecated**
- **Found during:** Task 2a compilation
- **Issue:** `value:` parameter deprecated after Flutter v3.33 — should use `initialValue:`
- **Fix:** Changed to `initialValue:` in both rejection_bottom_sheet.dart and flag_capture_sheet.dart

## Verification

All 3 tasks passed dart analyze with 0 errors. Only info-level style lints (prefer_single_quotes, prefer_const_constructors) remain — not blocking.

```
dart analyze lib/features/projects/presentation/
→ No errors
```

## Self-Check: PASSED

Files exist:
- mobile/lib/features/projects/presentation/widgets/inspection_checklist.dart ✓
- mobile/lib/features/projects/presentation/widgets/rejection_bottom_sheet.dart ✓
- mobile/lib/features/projects/presentation/widgets/flag_capture_sheet.dart ✓
- mobile/lib/features/projects/presentation/widgets/site_walk_flag_section.dart ✓
- mobile/lib/features/projects/presentation/widgets/punch_list_card.dart ✓

Commits:
- 9e35445 feat(24-03): GC inspection bottom bar... ✓
- 9294476 feat(24-03): Camera-first flag capture flow... ✓
- 1e3b72d feat(24-03): PunchListCard and inline punch list... ✓
