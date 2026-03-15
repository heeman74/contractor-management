# Phase 11: Integration Polish - Research

**Researched:** 2026-03-14
**Domain:** Flutter sync handler field names, Drift provider patterns, calendar blocked interval wiring
**Confidence:** HIGH

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SCHED-06 | Travel time awareness in scheduling (buffer between jobs) | `TravelTimeBlock` widget fully implemented. `ContractorLane._buildBookingWidgets()` already looks for `travel_buffer` `BlockedInterval` entries. `calendar_day_view.dart` `_buildLaneWidgets()` only ever adds `outside_working_hours` intervals — never `travel_buffer`. Fix is in `calendar_day_view.dart`: add `travel_buffer` `BlockedInterval` entries between consecutive bookings using each booking's `travelBufferMinutes` field (if populated) or the scheduling API endpoint. |
| SCHED-08 | Overdue task warnings when jobs miss scheduled completion | `OverduePanel` is fully wired (Phase 10). `overdue_providers.dart` `_toOverdueJobInfo()` passes `job.clientId` (a UUID) and `job.contractorId` (a UUID) as `clientName` and `contractorName`. Fix: look up `UserEntity` from `db.userDao.getUserById(job.clientId)` and `db.userDao.getUserById(job.contractorId)` for display names. |

</phase_requirements>

## Summary

Phase 11 closes three cross-phase wiring gaps identified by the v1.0 milestone audit. All three are surgical fixes to existing code — no new features and no new dependencies required.

**INT-01** is a one-line field name mismatch. `job_site_sync_handler.dart` lines 41–42 read `data['lat']`/`data['lng']`, but the backend `JobSiteResponse` schema (confirmed at `backend/app/features/sync/schemas.py` lines 36–37) sends `latitude`/`longitude`. Changing these two field name strings makes job site coordinates populate correctly after sync.

**INT-02** is a missing data-population step. `ContractorLane._buildBookingWidgets()` (lines 208–237 of `contractor_lane.dart`) correctly looks for `travel_buffer` `BlockedInterval` entries to render `TravelTimeBlock` widgets. The problem is upstream: `calendar_day_view.dart` `_buildLaneWidgets()` only creates `outside_working_hours` intervals and never produces `travel_buffer` ones. The `BookingEntity` struct needs a `travelBufferMinutes` field (check if it exists), or the calendar must derive travel buffers from the scheduling API or from job site distance. The most practical fix for a gap-closure phase is to produce synthetic `travel_buffer` intervals from the bookings' existing travel time metadata if available, or fetch them from the `/api/v1/scheduling/availability` endpoint.

**INT-03** is a display quality fix. `overdue_providers.dart` `_toOverdueJobInfo()` passes `job.clientId` (a UUID string) directly as `clientName` and `job.contractorId` (a UUID string) as `contractorName`. Both `UserDao.getUserById()` and `JobDao.watchClientProfiles()` are already available in the codebase. The fix is to resolve names from the local Drift tables: `db.userDao.getUserById(job.clientId)` for client and contractor display names.

**Primary recommendation:** Three independent single-task fixes. Plan as three tasks in one wave with a shared E2E test file.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Flutter + Riverpod | 3.32+ / 3.2 | Widget rendering + state | Already used throughout codebase |
| Drift | 2.32 | Local database + reactive streams | All data access goes through Drift DAOs |
| GetIt | Current | Service locator for DAO access | `getIt<AppDatabase>()` pattern used in all providers |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| UserDao | Internal | `getUserById(id)` for name lookup | INT-03 name resolution |
| JobDao | Internal | `watchClientProfiles(companyId)` | Optional — `getUserById` is simpler for this case |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `getUserById` for name lookup | `watchClientProfiles` + filter | `getUserById` is a one-shot Future — simpler in a sync `Provider`. ClientProfiles don't store display names; they live in the `Users` table via `userId` FK |
| Local computed travel buffers | Scheduling API call per day | API call is async and adds latency; local computation from `BookingEntity.travelBufferMinutes` (if present) avoids HTTP. See INT-02 investigation below |

## Architecture Patterns

### INT-01: Field Name Fix (job_site_sync_handler.dart)

**What:** Change `data['lat']`/`data['lng']` to `data['latitude']`/`data['longitude']` to match the backend `JobSiteResponse` schema.

**Files touched:** `mobile/lib/features/schedule/data/job_site_sync_handler.dart` — lines 41–42 only.

**Before (lines 40–43):**
```dart
// Parse lat/lng — backend stores as Numeric(9,6), JSON serializes as number.
final lat = data['lat'] is num ? (data['lat'] as num).toDouble() : null;
final lng = data['lng'] is num ? (data['lng'] as num).toDouble() : null;
```

**After:**
```dart
// Parse latitude/longitude — backend JobSiteResponse sends these field names.
// Numeric(9,6) → JSON number; use 'is num' guard per Phase 9 GPS field pattern.
final lat = data['latitude'] is num ? (data['latitude'] as num).toDouble() : null;
final lng = data['longitude'] is num ? (data['longitude'] as num).toDouble() : null;
```

**Backend evidence:** `backend/app/features/sync/schemas.py` line 36–37:
```python
latitude: Decimal | None = None
longitude: Decimal | None = None
```

**Comment update required:** Line 40's comment `// Parse lat/lng` should be updated to `// Parse latitude/longitude` to eliminate the misleading hint that caused the original bug.

### INT-02: Travel Buffer Intervals (calendar_day_view.dart)

**What:** Add `travel_buffer` `BlockedInterval` entries to the `blockedIntervals` list passed to each `ContractorLane`, so that `ContractorLane._buildBookingWidgets()` can render `TravelTimeBlock` widgets between consecutive bookings.

**Root cause:** `calendar_day_view.dart` `_buildLaneWidgets()` (lines 204–245) builds `blockedIntervals` with only two static `outside_working_hours` entries. `ContractorLane._buildBookingWidgets()` at lines 208–237 already has fully working logic to find `travel_buffer` intervals and render `TravelTimeBlock` — it just never receives any.

**BookingEntity travel buffer field investigation:** Check whether `BookingEntity` already carries `travelBufferMinutes`:

```dart
// Check mobile/lib/features/schedule/domain/booking_entity.dart
```

**If `travelBufferMinutes` exists on `BookingEntity`:** Generate synthetic `travel_buffer` intervals locally in `_buildLaneWidgets()` from consecutive booking pairs where `booking.travelBufferMinutes != null && booking.travelBufferMinutes! > 0`. This is purely local — no HTTP, no new data needed.

**If `travelBufferMinutes` does NOT exist on `BookingEntity`:** Two options:
1. Add `travelBufferMinutes` field to `BookingEntity` and map it from the backend `BookingResponse` (check backend `app/features/scheduling/schemas.py` for whether `BookingResponse` includes travel buffer data)
2. Use a fixed default buffer (e.g., 15 minutes) between consecutive bookings as a visual indicator — lower fidelity but immediate

The planner must check `BookingEntity` fields before choosing the implementation path.

**Pattern for local interval computation (if field exists):**
```dart
// In _buildLaneWidgets(), after creating outside_working_hours intervals:
// Add travel_buffer intervals between consecutive bookings for this contractor
final sortedBookings = List<BookingEntity>.from(contractorBookings)
  ..sort((a, b) => a.timeRangeStart.compareTo(b.timeRangeStart));

for (var i = 0; i < sortedBookings.length - 1; i++) {
  final current = sortedBookings[i];
  final bufferMinutes = current.travelBufferMinutes;
  if (bufferMinutes != null && bufferMinutes > 0) {
    final bufferEnd = current.timeRangeEnd.add(Duration(minutes: bufferMinutes));
    if (bufferEnd.isBefore(sortedBookings[i + 1].timeRangeStart) ||
        bufferEnd.isAtSameMomentAs(sortedBookings[i + 1].timeRangeStart)) {
      blockedIntervals.add(BlockedInterval(
        start: current.timeRangeEnd,
        end: bufferEnd,
        reason: 'travel_buffer',
      ));
    }
  }
}
```

**IMPORTANT:** `ContractorLane._buildBookingWidgets()` checks `interval.end.isAtSameMomentAs(nextBooking.timeRangeStart)` — so the computed buffer end must not extend past the next booking's start time.

### INT-03: Overdue Panel Name Resolution (overdue_providers.dart)

**What:** Replace UUID passthrough with actual display name lookup from `UserDao`.

**Root cause:** `_toOverdueJobInfo()` lines 138–148 sets:
```dart
clientName: job.clientId,      // UUID string, not a name
contractorName: job.contractorId,  // UUID string, not a name
```
Both have `// TODO: resolve from ClientProfile/User in future plan` comments confirming they were intentional stubs.

**Name resolution approach:**

`job.clientId` and `job.contractorId` are both `User.id` values. `UserDao.getUserById(id)` returns `Future<UserEntity?>`. `UserEntity` has `firstName`, `lastName`, and `email` fields.

The current `overdueJobsProvider` is a synchronous `Provider<List<OverdueJobInfo>>` that derives from `jobListNotifierProvider`. Switching to async lookup for each job would require changing it to a `FutureProvider` or performing a separate watch on the user table.

**Recommended approach — watch the user list once, build a lookup map:**

```dart
// In overdue_providers.dart — new provider that builds a companyId-scoped name map
// Step 1: Get companyId from auth state
// Step 2: Watch companyUsersProvider(companyId) from user_providers.dart
// Step 3: Build Map<String, String> userId -> displayName
// Step 4: Pass the map into _toOverdueJobInfo()
```

The cleanest implementation replaces `overdueJobsProvider` with a version that also watches `companyUsersProvider`:

```dart
// Revised overdueJobsProvider — companyId-scoped, resolves names from Users table
final overdueJobsProvider = Provider<List<OverdueJobInfo>>((ref) {
  final authState = ref.watch(authNotifierProvider);
  final companyId = authState is AuthAuthenticated ? authState.companyId : null;

  final jobsAsync = ref.watch(jobListNotifierProvider);
  final jobs = jobsAsync.maybeWhen(
    data: (jobs) => jobs.where(
      (job) => OverdueService.isOverdue(job.status, job.scheduledCompletionDate),
    ).toList(),
    orElse: () => <JobEntity>[],
  );

  // Build user name lookup map from synced Users table
  final Map<String, String> userNames = {};
  if (companyId != null) {
    final usersAsync = ref.watch(companyUsersProvider(companyId));
    usersAsync.maybeWhen(
      data: (users) {
        for (final u in users) {
          final name = _displayName(u);
          userNames[u.id] = name;
        }
      },
      orElse: () {},
    );
  }

  return jobs.map((job) => _toOverdueJobInfo(job, userNames)).toList()
    ..sort((a, b) {
      final severityCompare = _severityOrder(b.severity) - _severityOrder(a.severity);
      if (severityCompare != 0) return severityCompare;
      return b.daysOverdue.compareTo(a.daysOverdue);
    });
});

String _displayName(UserEntity user) {
  final first = user.firstName ?? '';
  final last = user.lastName ?? '';
  if (first.isNotEmpty && last.isNotEmpty) return '$first $last';
  if (first.isNotEmpty) return first;
  return user.email.split('@').first;
}
```

**Import required:** `companyUsersProvider` from `features/users/presentation/providers/user_providers.dart`. `AuthAuthenticated` from `features/auth/domain/auth_state.dart`. Both already exist.

**Pattern note:** `ref.watch(companyUsersProvider(companyId))` inside a synchronous `Provider` is valid in Riverpod 3 — the provider re-evaluates when users stream emits. This means name resolution is reactive: as users sync in, the panel updates with real names automatically.

### Anti-Patterns to Avoid

- **Using `getUserById` (Future) in a synchronous Provider:** Do NOT call `await db.userDao.getUserById()` inside `overdueJobsProvider` — it is a synchronous `Provider`, not `FutureProvider`. Use `ref.watch(companyUsersProvider(companyId))` which is a StreamProvider already available.
- **Extending travel buffer past next booking start:** `ContractorLane._buildBookingWidgets()` checks `interval.end.isAtSameMomentAs(nextBooking.timeRangeStart)`. If the travel buffer would exceed the gap between bookings, skip or clamp it — never create overlapping intervals.
- **Mutating the `blockedIntervals` list after passing to ContractorLane:** Build the full list before the `ContractorLane(...)` constructor call. `ContractorLane` uses the list during `build()` via `_buildBookingWidgets()` — late mutations won't affect the rendered widget.
- **The `lat`/`lng` Drift column names are correct:** The Drift table (`job_sites.dart`) uses `lat` and `lng` column names (lines 24, 27). The `JobSitesCompanion` constructor uses `lat:` and `lng:` parameter names. Only the JSON field names read from `data[...]` need to change — not the Companion field names.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| User display names | Custom lookup service | `ref.watch(companyUsersProvider(companyId))` | Already a Riverpod StreamProvider over Drift; reactive, offline-first |
| Travel buffer rendering | New rendering layer | Existing `TravelTimeBlock` widget + `BlockedInterval('travel_buffer')` | `ContractorLane` already has full rendering logic waiting for data |
| JSON field name validation | Custom type-checking | Same `'is num'` pattern used for GPS fields in Phase 9 (per STATE.md) | Handles int vs double JSON ambiguity with backend Numeric(9,6) type |

**Key insight:** All rendering and data access infrastructure for Phase 11 already exists. The only work is: (1) two string literals, (2) a loop that populates an existing list, (3) two provider watches replacing two UUID passthrough assignments.

## Common Pitfalls

### Pitfall 1: Changing Drift Companion field names for INT-01
**What goes wrong:** Developer changes `lat:` and `lng:` in the `JobSitesCompanion(...)` call, causing a compile error because those are the correct Drift column names.
**Why it happens:** The Drift table columns are named `lat`/`lng` (from `job_sites.dart`). Only the JSON dictionary key strings on lines 41–42 are wrong.
**How to avoid:** Change only `data['lat']` → `data['latitude']` and `data['lng']` → `data['longitude']`. Leave `lat: Value(lat)` and `lng: Value(lng)` in the Companion call unchanged.
**Warning signs:** Compile error `The named parameter 'latitude' isn't defined`.

### Pitfall 2: Travel buffer extending past next booking
**What goes wrong:** `travelInterval.end` is placed after `nextBooking.timeRangeStart`, so `ContractorLane._buildBookingWidgets()` does not match the interval (it checks `isAtSameMomentAs`).
**Why it happens:** The gap between two bookings might be shorter than the configured travel buffer (back-to-back scheduling).
**How to avoid:** Clamp the buffer end: `final bufferEnd = min(current.timeRangeEnd + buffer, nextBooking.timeRangeStart)`. If `bufferEnd == current.timeRangeEnd`, skip (no room for a travel block).
**Warning signs:** TravelTimeBlock never renders even after the fix.

### Pitfall 3: `overdueJobsProvider` companyId before auth is ready
**What goes wrong:** If `authNotifierProvider` is in `AuthLoading` state (app startup), `companyId` is null, `companyUsersProvider(null)` is called, which either crashes or returns empty.
**Why it happens:** `overdueJobsProvider` is typically watched before the schedule screen fully loads.
**How to avoid:** Guard with `if (companyId == null) return []` before calling `companyUsersProvider`. When companyId is null, fall back to empty names (UUID passthrough is acceptable as a loading state) rather than crashing.
**Warning signs:** `null check operator used on a null value` error on cold launch.

### Pitfall 4: INT-02 BlockedInterval list is currently a mutable local list
**What goes wrong:** `_buildLaneWidgets()` creates `blockedIntervals` as a `final` list literal. Adding travel buffer entries requires it to be mutable.
**Why it happens:** `final blockedIntervals = [...]` creates a `List<BlockedInterval>` literal that IS mutable (not const) — so `blockedIntervals.add(...)` works fine. No code change needed for mutability.
**Warning signs:** None — this is not actually a problem, just needs confirmation.

### Pitfall 5: BookingEntity may not have travelBufferMinutes
**What goes wrong:** Planner assumes `BookingEntity.travelBufferMinutes` exists; it may not.
**Why it happens:** The backend `BookingResponse` schema needs inspection. Phase 3 implemented travel time at the scheduling service level, but whether `travel_buffer_minutes` is serialized into the booking sync payload is unverified.
**How to avoid:** Before implementing INT-02, the planner MUST check `BookingEntity` fields and the backend `BookingResponse` schema. If the field does not exist, add it to `BookingEntity` and the sync handler, OR use a fixed 15-minute default as a visual approximation.
**Warning signs:** Compile error `The getter 'travelBufferMinutes' isn't defined` on `BookingEntity`.

## Code Examples

### INT-01: Complete fix (job_site_sync_handler.dart lines 40–43)

```dart
// Source: mobile/lib/features/schedule/data/job_site_sync_handler.dart
// BEFORE:
final lat = data['lat'] is num ? (data['lat'] as num).toDouble() : null;
final lng = data['lng'] is num ? (data['lng'] as num).toDouble() : null;

// AFTER:
// Parse latitude/longitude — backend JobSiteResponse field names (not lat/lng).
// Numeric(9,6) serializes as JSON number; 'is num' guards against int/double ambiguity.
final lat = data['latitude'] is num ? (data['latitude'] as num).toDouble() : null;
final lng = data['longitude'] is num ? (data['longitude'] as num).toDouble() : null;
```

### INT-02: Travel buffer interval generation (calendar_day_view.dart)

```dart
// Source: mobile/lib/features/schedule/presentation/widgets/calendar_day_view.dart
// Add inside _buildLaneWidgets(), after the initial blockedIntervals list:

// Generate travel_buffer intervals from consecutive bookings (SCHED-06).
// ContractorLane._buildBookingWidgets() renders TravelTimeBlock for these.
final sortedForTravel = List<BookingEntity>.from(contractorBookings)
  ..sort((a, b) => a.timeRangeStart.compareTo(b.timeRangeStart));

for (var i = 0; i < sortedForTravel.length - 1; i++) {
  final curr = sortedForTravel[i];
  final next = sortedForTravel[i + 1];
  final bufferMins = curr.travelBufferMinutes; // field must exist on BookingEntity
  if (bufferMins == null || bufferMins <= 0) continue;

  final maxEnd = next.timeRangeStart;
  final rawEnd = curr.timeRangeEnd.add(Duration(minutes: bufferMins));
  final bufferEnd = rawEnd.isAfter(maxEnd) ? maxEnd : rawEnd;

  if (bufferEnd.isAfter(curr.timeRangeEnd)) {
    blockedIntervals.add(BlockedInterval(
      start: curr.timeRangeEnd,
      end: bufferEnd,
      reason: 'travel_buffer',
    ));
  }
}
```

### INT-03: Revised _toOverdueJobInfo with name map (overdue_providers.dart)

```dart
// Source: mobile/lib/features/schedule/presentation/providers/overdue_providers.dart
// Replace the _toOverdueJobInfo function signature and the clientName/contractorName lines:

OverdueJobInfo _toOverdueJobInfo(JobEntity job, Map<String, String> userNames) {
  // ... existing severity + daysOverdue + delay logic unchanged ...
  return OverdueJobInfo(
    // ...
    clientName: job.clientId != null ? userNames[job.clientId] : null,
    contractorName: job.contractorId != null ? userNames[job.contractorId] : null,
    // ...
  );
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `data['lat']`/`data['lng']` in sync handler | `data['latitude']`/`data['longitude']` | Phase 11 | Job site coordinates populate correctly in Drift after sync |
| `blockedIntervals` contains only `outside_working_hours` | Includes computed `travel_buffer` intervals | Phase 11 | `TravelTimeBlock` widgets render visually on calendar between bookings |
| `clientName: job.clientId` (UUID) | `clientName: userNames[job.clientId]` (display name) | Phase 11 | OverduePanel shows human-readable names |

**Deprecated/outdated:**
- The TODO comments in `overdue_providers.dart` lines 141–142: `// TODO: resolve from ClientProfile in future plan` and `// TODO: resolve from User in future plan` — remove them when implementing INT-03.

## Open Questions

1. **Does BookingEntity have a travelBufferMinutes field?**
   - What we know: `ContractorLane._buildBookingWidgets()` already processes `travel_buffer` `BlockedInterval` entries. The scheduling service computes travel time. Whether this is propagated to the mobile `BookingEntity` is unverified.
   - What's unclear: Whether `backend/app/features/scheduling/schemas.py` `BookingResponse` includes `travel_buffer_minutes`, and whether `mobile/lib/features/schedule/domain/booking_entity.dart` has this field.
   - Recommendation: The planner MUST inspect `booking_entity.dart` and `BookingResponse` before writing the INT-02 plan. If the field is absent, the plan must include adding it. If absent from the backend schema too, a fixed 15-minute default is a valid approximation for phase closure.

2. **Should travel buffers render for all bookings or only when travelBufferMinutes > 0?**
   - What we know: `TravelTimeBlock` requires positive `height` to render (guarded by `if (travelHeight > 0)`).
   - What's unclear: Whether showing a 0-minute travel block (for adjacent offices, same building) adds visual noise.
   - Recommendation: Only generate `travel_buffer` intervals when `travelBufferMinutes > 0`. Skip zero-buffer bookings — they represent same-site consecutive jobs.

3. **Name lookup when client or contractor user is null**
   - What we know: `job.clientId` is nullable (`String?` on `JobEntity`). Jobs can exist without a client assignment.
   - What's unclear: Whether the OverduePanel should show "No client" or `null` when `clientId` is null.
   - Recommendation: Use `null` for `clientName`/`contractorName` when the ID is null. `OverduePanel` presumably handles null with fallback text — verify during implementation.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework (Flutter) | flutter_test + mocktail |
| Framework (Backend) | N/A — Phase 11 is Flutter-only fixes (no backend changes) |
| Config file | none — flutter test auto-discovers |
| Quick run command | `flutter test mobile/test/e2e/phase_11_integration_polish_e2e_test.dart` |
| Full suite command | `flutter test mobile/test/` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCHED-06 (INT-01) | After sync with `latitude`/`longitude` data, `lat`/`lng` are non-null in Drift | unit | `flutter test mobile/test/e2e/phase_11_integration_polish_e2e_test.dart -N int01_field_names` | ❌ Wave 0 |
| SCHED-06 (INT-02) | `CalendarDayView` passes `travel_buffer` `BlockedInterval` to `ContractorLane` when bookings have travel buffer | widget/E2E | `flutter test mobile/test/e2e/phase_11_integration_polish_e2e_test.dart -N int02_travel_block` | ❌ Wave 0 |
| SCHED-06 (INT-02) | `TravelTimeBlock` widget renders between two consecutive bookings with travel data | widget/E2E | `flutter test mobile/test/e2e/phase_11_integration_polish_e2e_test.dart -N int02_travel_renders` | ❌ Wave 0 |
| SCHED-08 (INT-03) | `overdueJobsProvider` returns human-readable names, not UUIDs | unit | `flutter test mobile/test/e2e/phase_11_integration_polish_e2e_test.dart -N int03_display_names` | ❌ Wave 0 |
| SCHED-08 (INT-03) | `OverduePanel` displays client display name in overdue job card | widget/E2E | `flutter test mobile/test/e2e/phase_11_integration_polish_e2e_test.dart -N int03_panel_names` | ❌ Wave 0 |
| SCHED-06 (E2E flow) | Full flow: sync payload with `latitude`/`longitude` → Drift upsert → `lat`/`lng` non-null | E2E | `flutter test mobile/test/e2e/phase_11_integration_polish_e2e_test.dart -N e2e_coordinate_flow` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test mobile/test/e2e/phase_11_integration_polish_e2e_test.dart`
- **Per wave merge:** `flutter test mobile/test/`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `mobile/test/e2e/phase_11_integration_polish_e2e_test.dart` — covers INT-01, INT-02, INT-03 with unit + widget tests

*(No new framework installs needed — mocktail, flutter_test, Drift in-memory already present)*

## Sources

### Primary (HIGH confidence)
- Direct code inspection: `mobile/lib/features/schedule/data/job_site_sync_handler.dart` lines 41–42 — confirmed reads `data['lat']`/`data['lng']`
- Direct code inspection: `backend/app/features/sync/schemas.py` lines 36–37 — confirmed sends `latitude`/`longitude`
- Direct code inspection: `backend/app/features/scheduling/models.py` lines 155–157 — `JobSite.latitude`/`JobSite.longitude` column names
- Direct code inspection: `mobile/lib/features/schedule/presentation/widgets/calendar_day_view.dart` lines 216–227 — confirmed only `outside_working_hours` intervals generated
- Direct code inspection: `mobile/lib/features/schedule/presentation/widgets/contractor_lane.dart` lines 208–237 — confirmed `travel_buffer` detection logic exists and is correct
- Direct code inspection: `mobile/lib/features/schedule/presentation/widgets/travel_time_block.dart` — widget is fully implemented
- Direct code inspection: `mobile/lib/features/schedule/presentation/providers/overdue_providers.dart` lines 141–142 — confirmed UUID passthrough with TODO comments
- Direct code inspection: `mobile/lib/features/users/presentation/providers/user_providers.dart` — `companyUsersProvider` exists as `StreamProvider.autoDispose.family`
- Direct code inspection: `mobile/lib/features/users/data/user_dao.dart` — `getUserById(id)` method exists returning `Future<UserEntity?>`
- Direct code inspection: `.planning/v1.0-MILESTONE-AUDIT.md` — INT-01, INT-02, INT-03 gap definitions and evidence

### Secondary (MEDIUM confidence)
- `mobile/lib/core/database/tables/job_sites.dart` — Drift table uses `lat`/`lng` column names (correct; only JSON keys need changing)
- `mobile/lib/features/jobs/presentation/providers/crm_providers.dart` — `clientListNotifierProvider` for alternative name lookup approach
- `mobile/lib/core/database/app_database.dart` — schema v6 confirmed, all tables including `job_sites`, `client_profiles`, `users` present

## Metadata

**Confidence breakdown:**
- INT-01 fix: HIGH — field names confirmed by direct inspection of both handler and backend schema
- INT-02 fix: MEDIUM — ContractorLane rendering logic confirmed HIGH, BookingEntity.travelBufferMinutes existence UNVERIFIED (planner must check)
- INT-03 fix: HIGH — provider pattern, UserDao method, and existing providers all confirmed

**Research date:** 2026-03-14
**Valid until:** 2026-04-14 (stable codebase; all findings based on actual file contents)
