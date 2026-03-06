---
phase: 02-offline-sync-engine
verified: 2026-03-05T23:55:00Z
status: passed
score: 9/9 must-haves verified
re_verification:
  previous_status: passed
  previous_score: 7/7
  gaps_closed:
    - "GET /api/v1/sync?cursor= now returns populated user_roles array (migration 0003 backfills updated_at = created_at for NULL rows)"
    - "Sync status subtitle now shows 'Syncing 1 of N...' before 'All synced' on connectivity restore (race condition eliminated)"
  gaps_remaining: []
  regressions: []
  notes:
    - "ROADMAP.md checkbox for 02-07-PLAN.md remains [ ] (unchecked) — documentation lag only. The plan was executed and all four artifacts are confirmed in the codebase. ROADMAP should be updated to [x]."
human_verification:
  - test: "Launch app offline, create a company, restore network"
    expected: "Company appears immediately in UI; after connectivity restore, sync status transitions through 'N items pending' -> 'Syncing 1 of 1...' -> 'All synced'; company visible in backend"
    why_human: "Full offline-to-online round-trip requires real device, network toggle, and backend running"
  - test: "Turn off network mid-sync (5xx simulation) and verify retry"
    expected: "Queue item is retried with increasing delay up to 5 attempts, then stays pending with attemptCount reset to 0"
    why_human: "Backoff timing (1s/2s/4s/8s/16s) and network condition simulation cannot be verified programmatically"
  - test: "App bar subtitle always visible across all tabs"
    expected: "All synced / N items pending / Syncing X of Y... / Offline states render with icons as tab is switched; 'All synced' with green check visible at rest"
    why_human: "Visual rendering and animated rotation icon require a running Flutter app"
  - test: "WorkManager fires every 15 minutes in background"
    expected: "After app is backgrounded, background sync runs automatically when network is connected; no data loss"
    why_human: "Background task scheduling requires a real Android device and cannot be verified from source code alone"
  - test: "Login flow: tap any login button on OnboardingScreen, confirm navigation to Home"
    expected: "Tapping Admin/Contractor/Client login button sets AuthAuthenticated state; GoRouter redirect fires immediately; user lands on /home with bottom nav and sync status subtitle visible"
    why_human: "GoRouter redirect is logic-correct by inspection but visual confirmation of navigation and AppShell render requires a running Flutter app"
  - test: "GET /api/v1/sync with all three cursor cases and verify user_roles populated"
    expected: "Absent cursor returns 200 full payload with non-empty user_roles; empty cursor (?cursor=) returns 200 full payload with non-empty user_roles; valid ISO8601 cursor returns 200 delta payload; invalid non-empty cursor returns 422. Requires running 'alembic upgrade head' first."
    why_human: "Requires running backend with real PostgreSQL and migration 0003 applied. Code logic verified; HTTP response and row count can only be confirmed by live test."
  - test: "Sync status subtitle shows 'Syncing 1 of 1...' before 'All synced' on connectivity restore"
    expected: "On connectivity restore with one pending item, subtitle displays 'Syncing 1 of 1...' for at least one visible frame before transitioning to 'All synced'"
    why_human: "Frame-level rendering behavior requires a running Flutter app — the Future<void>.delayed(Duration.zero) yield is confirmed in code but the visual effect cannot be verified programmatically"
---

# Phase 2: Offline Sync Engine Verification Report

**Phase Goal:** The Flutter app stores all data locally first and reliably synchronizes to the backend when connectivity is available, with no data loss or duplication
**Verified:** 2026-03-05T23:55:00Z
**Status:** PASSED
**Re-verification:** Yes — after 02-07 gap closure (final two UAT-diagnosed bugs fixed)

---

## Re-Verification Context

This is the third verification pass for Phase 2.

- **Initial verification (2026-03-05T22:45:00Z):** Passed 5/5 original truths.
- **Second verification (2026-03-05T23:30:00Z):** Added 2 new truths for 02-06 gap closure (empty cursor 422 fix, GoRouter redirect fix). Passed 7/7.
- **This verification (2026-03-05T23:55:00Z):** Adds 2 new truths for 02-07 gap closure. UAT Test 1 (user_roles empty array) and UAT Test 7 (sync status race condition) were the two remaining diagnosed failures. Plan 02-07 was executed and completed on 2026-03-06. This pass confirms all four 02-07 artifacts are in the codebase and correct.

**ROADMAP discrepancy noted:** ROADMAP.md still shows `- [ ] 02-07-PLAN.md` (unchecked). The 02-07-SUMMARY.md exists, both commits are documented (4f78ee7, 993d60c), and all four artifacts are verified in the actual codebase. This is a documentation lag — the ROADMAP checkbox was not updated after 02-07 completed. The codebase is correct; the ROADMAP metadata should be updated to `[x]`.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | All reads in Flutter stream from local Drift database — no UI widget awaits HTTP directly | VERIFIED | `watchAllCompanies()` and `watchUsersByCompany()` return `Stream<List<...>>`. AppShell, HomeScreen, JobsScreen consume Drift streams. No `await http` calls in UI widgets. |
| 2 | User can create a record while offline; appears immediately in UI and syncs when connectivity is restored | VERIFIED | `insertCompany()` writes to `companies` table + `sync_queue` in single `db.transaction()`. Drift stream auto-notifies UI. `ConnectivityService.startListening(_onConnectivityRestored)` wires connectivity restore to `drainQueue()` + `pullDelta()`. |
| 3 | Record created offline and retried multiple times appears exactly once in backend (idempotency via UUID) | VERIFIED | `sync_queue.id` is UUID v4 used as `Idempotency-Key` header in `pushWithIdempotency()`. Backend `create_company_idempotent()` uses `INSERT ON CONFLICT DO NOTHING`. Integration test `test_duplicate_company_uuid_returns_existing` confirms. |
| 4 | App displays visible sync status indicator at all times | VERIFIED | `SyncStatusSubtitle` ConsumerWidget watches `syncStatusProvider`, renders 4 states (allSynced, pending, syncing, offline) with icons. Included in `AppShell.build()` `AppBar` `Column` — always visible across all tabs. |
| 5 | Sync conflict resolves predictably — server always wins — with no silent data loss | VERIFIED | `CompanySyncHandler.applyPulled()` uses `insertOnConflictUpdate`. `update_company_server_wins()` exists in backend service. All handlers propagate tombstones (non-null `deleted_at`). |
| 6 | GET /api/v1/sync?cursor= returns 200 with valid SyncResponse (empty cursor treated as epoch) | VERIFIED | `router.py` line 32: `cursor: str \| None = Query(default=None, ...)`. Lines 53-62: three-branch parse — None/empty -> `_EPOCH_START`; valid ISO8601 -> `datetime.fromisoformat(cursor)`; invalid non-empty -> `HTTPException(422)`. |
| 7 | Authenticated users on /splash or /onboarding are redirected to /home | VERIFIED | `app_router.dart` lines 76-79: `AuthAuthenticated(:final roles) => (location == RouteNames.splash \|\| location == RouteNames.onboarding) ? RouteNames.home : _checkRoleAccess(location, roles)`. Prefix check fires before role-access delegation. |
| 8 | GET /api/v1/sync returns populated user_roles when role records exist (updated_at non-NULL) | VERIFIED | Migration 0003 executes `UPDATE user_roles SET updated_at = created_at WHERE updated_at IS NULL` then `op.alter_column("user_roles", "updated_at", nullable=False)`. `UserRole.updated_at` in `models.py` is `Mapped[datetime]` / `nullable=False`. `service.py` `get_user_roles_since()` filters `UserRole.updated_at > since` — now matches all non-NULL rows. |
| 9 | Sync status subtitle shows 'Syncing N of N...' before 'All synced' on connectivity restore | VERIFIED | `sync_status_provider.dart`: connectivity-restore `else` branch is empty — no premature `yield`. `sync_engine.dart` `drainQueue()`: `await Future<void>.delayed(Duration.zero)` added between initial syncing emit (line 169) and item processing loop (line 177). `lastEngineStatus` variable removed entirely (was dead code after yield removal). |

**Score: 9/9 truths verified**

---

## Required Artifacts

### Plan 02-01 Artifacts (INFRA-03: Local storage foundation)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mobile/lib/core/database/tables/sync_queue.dart` | SyncQueue Drift table with 9 columns | VERIFIED | `class SyncQueue extends Table`. All 9 columns confirmed: `id` (UUID v4 via `clientDefault`), `entityType`, `entityId`, `operation`, `payload`, `status` (default 'pending'), `attemptCount` (default 0), `errorMessage` (nullable), `createdAt`. Primary key `{id}`. |
| `mobile/lib/core/database/app_database.dart` | Schema v2 with SyncQueue, SyncCursor, migration from v1 | VERIFIED | `schemaVersion => 2`. `@DriftDatabase(tables: [Companies, Users, UserRoles, SyncQueue, SyncCursor], daos: [...SyncQueueDao, SyncCursorDao])`. `from1To2` migration creates both sync tables, adds `deletedAt` to 3 entity tables. |
| `mobile/lib/features/company/data/company_dao.dart` | CompanyDao with transactional outbox writes | VERIFIED | `insertCompany()`, `updateCompany()`, `deleteCompany()` all wrap in `db.transaction()` with dual-write to both entity table and `sync_queue`. |

### Plan 02-02 Artifacts (INFRA-04: Backend sync infrastructure)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `backend/app/features/sync/router.py` | GET /api/v1/sync delta endpoint | VERIFIED | `@router.get("")`. Handles all 3 cursor cases (absent, empty string, valid ISO8601). Calls service functions, returns `SyncResponse` with `server_timestamp`. |
| `backend/app/features/companies/service.py` | Idempotent create with ON CONFLICT DO NOTHING | VERIFIED | `create_company_idempotent()` uses `insert(Company).values(...).on_conflict_do_nothing(index_elements=["id"])`. |

### Plan 02-03 Artifacts (SyncEngine core)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mobile/lib/core/sync/sync_engine.dart` | Queue drain, delta pull, retry logic, connectivity trigger, frame yield | VERIFIED | `drainQueue()` with `_isSyncing` guard, FIFO loop, 4xx park / 5xx exponential backoff (1/2/4/8/16s), max 5 retries then reset to 0. `pullDelta()` reads cursor, GET /sync, `applyPulled` via registry, updates cursor. `statusStream` broadcast. `await Future<void>.delayed(Duration.zero)` present between syncing emit and item loop. |
| `mobile/lib/core/sync/handlers/company_sync_handler.dart` | Company push + applyPulled with tombstone propagation | VERIFIED | `push()` via `pushWithIdempotency('/companies', payload, item.id)`. `applyPulled()` uses `insertOnConflictUpdate` with `deletedAt: Value(deletedAt)` propagation. |

### Plan 02-04 Artifacts (WorkManager + UI)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mobile/lib/shared/widgets/sync_status_subtitle.dart` | Widget showing all 4 sync states | VERIFIED | `SyncStatusSubtitle extends ConsumerWidget`. All 4 states rendered: allSynced (green check), pending (sync icon, orange), syncing (`_AnimatedSyncRow` with `RotationTransition`), offline (wifi_off). |
| `mobile/lib/shared/widgets/app_shell.dart` | AppShell with SyncStatusSubtitle in shared AppBar | VERIFIED | `AppBar(title: Column([Text(currentTab.label), const SyncStatusSubtitle()]))`. Widget present in `AppShell.build()` Column — visible on every tab. |

### Plan 02-06 Artifacts (UAT gap closure — cursor 422 + login redirect)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `backend/app/features/sync/router.py` | `str \| None` cursor param with explicit fromisoformat parsing | VERIFIED | Line 32: `cursor: str \| None = Query(default=None, ...)`. Lines 53-62: three-branch parse — None/empty -> `_EPOCH_START`; valid ISO8601 -> `datetime.fromisoformat(cursor)`; invalid non-empty -> `HTTPException(422)`. |
| `mobile/lib/core/routing/app_router.dart` | AuthAuthenticated branch redirects auth screens to /home | VERIFIED | Lines 76-79: `AuthAuthenticated(:final roles) => (location == RouteNames.splash \|\| location == RouteNames.onboarding) ? RouteNames.home : _checkRoleAccess(location, roles)`. `RouteNames.home` import present. `_checkRoleAccess` unchanged. |

### Plan 02-07 Artifacts (UAT gap closure — user_roles backfill + sync status race)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `backend/migrations/versions/0003_backfill_user_roles_updated_at.py` | Alembic migration backfilling updated_at = created_at for NULL rows, then NOT NULL | VERIFIED | `revision = "0003"`, `down_revision = "0002"`. `upgrade()`: `op.execute(text("UPDATE user_roles SET updated_at = created_at WHERE updated_at IS NULL"))` followed by `op.alter_column("user_roles", "updated_at", nullable=False)`. `downgrade()` reverses NOT NULL only. |
| `backend/app/features/users/models.py` | UserRole.updated_at is `Mapped[datetime]` / `nullable=False` | VERIFIED | Line 77-79: `updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())`. Consistent with User and Company models. |
| `mobile/lib/core/sync/sync_status_provider.dart` | Connectivity-restore else branch does not yield premature allSynced | VERIFIED | Lines 55-64: `else { // Back online — do NOT yield here. ... }` — empty else branch. No `yield lastEngineStatus` present. `lastEngineStatus` variable removed entirely. Engine drives its own syncing -> allSynced transition. |
| `mobile/lib/core/sync/sync_engine.dart` | Frame yield after initial syncing emit in drainQueue() | VERIFIED | Line 175: `await Future<void>.delayed(Duration.zero);` inserted between `_syncStatusController.add(SyncStatus(SyncState.syncing, total))` and the `for` loop. Comment explains rationale. |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `app_database.dart` | `sync_queue.dart` + `sync_queue_dao.dart` | `@DriftDatabase(tables:..., daos:...)` | VERIFIED | `tables: [Companies, Users, UserRoles, SyncQueue, SyncCursor]`, `daos: [...SyncQueueDao, SyncCursorDao]` |
| `company_dao.dart` | `sync_queue.dart` | `db.transaction()` dual-write | VERIFIED | `into(syncQueue).insert(...)` inside `db.transaction()` in insert/update/delete methods |
| `sync_engine.dart` | `sync_registry.dart` | `_registry.getHandler(entityType)` | VERIFIED | `_registry.getHandler(item.entityType)` in `drainQueue()`; `_registry.getHandler('company'/'user'/'user_role')` in `pullDelta()` |
| `sync_engine.dart` | `sync_cursor_dao.dart` | `getCursor`/`updateCursor` | VERIFIED | `_syncCursorDao.getCursor()` in `pullDelta()`, `_syncCursorDao.updateCursor()` after successful pull |
| `connectivity_service.dart` | `sync_engine.dart` | `startListening(_onConnectivityRestored)` | VERIFIED | `_connectivityService.startListening(_onConnectivityRestored)` in `initialize()`; `_onConnectivityRestored` calls `drainQueue()` then `pullDelta()` |
| `service_locator.dart` | `sync_engine.dart` | `getIt.registerSingleton(syncEngine)` + `syncEngine.initialize()` | VERIFIED | SyncEngine constructed with all dependencies, registered, then `initialize()` called |
| `app_shell.dart` | `sync_status_provider.dart` | `ref.watch(syncStatusProvider)` inside `SyncStatusSubtitle` | VERIFIED | `SyncStatusSubtitle` imported in `app_shell.dart`; watches `syncStatusProvider` in its own `build()` method |
| `sync_router.py` | `sync_service.py` | `service.get_companies_since(db, since)` | VERIFIED | `service.get_companies_since(db, since)`, `service.get_users_since(db, since)`, `service.get_user_roles_since(db, since)` — `since` derived from parsed cursor |
| `app_router.dart` | `route_names.dart` | `RouteNames.home` redirect target | VERIFIED | `RouteNames.home` used as redirect target in `AuthAuthenticated` branch |
| `migration_0003.py` | `sync_service.py` (indirect) | `updated_at = created_at` backfill enables `updated_at > since` to match all rows | VERIFIED | `service.py` `get_user_roles_since()` filters `UserRole.updated_at > since`; migration 0003 ensures all rows have non-NULL `updated_at`; `UserRole.updated_at` model is now `nullable=False` |
| `sync_engine.dart` | `sync_status_provider.dart` | `statusStream` drives syncing -> allSynced without interference from provider | VERIFIED | Provider's connectivity-restore else branch is empty; all status transitions driven exclusively by engine `_syncStatusController.add(...)` calls; frame yield ensures at least one Flutter paint cycle |

---

## Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| INFRA-03 | 02-01, 02-03, 02-04, 02-05, 02-06, 02-07 | Offline-first mobile app with local data storage | SATISFIED | Drift `sync_queue` outbox (02-01), `SyncEngine.drainQueue()` (02-03), WorkManager background sync (02-04), unit tests proving correctness (02-05). All reads from local Drift DB. Every mutation atomically queued. Login flow unblocked by 02-06 enables full UAT coverage. Migration 0003 (02-07) fixes user_roles sync data correctness. |
| INFRA-04 | 02-02, 02-03, 02-04, 02-05, 02-06, 02-07 | Background sync engine with conflict resolution | SATISFIED | Backend delta endpoint with tombstone support (02-02), `SyncEngine.pullDelta()` cursor-based pull (02-03), WorkManager 15-minute periodic task (02-04), integration tests proving idempotency + tenant isolation (02-05). Empty cursor bug fixed in 02-06. Sync status race and user_roles data bug fixed in 02-07. Server-wins conflict resolution confirmed. |

Both requirements claimed by Phase 2 plans are SATISFIED. No orphaned requirements found.

REQUIREMENTS.md traceability table correctly marks both INFRA-03 and INFRA-04 as Complete under Phase 2.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `home_screen.dart` | 109, 113, 120 | "coming Phase 3", "coming Phase 5" placeholder labels | INFO | Expected — placeholder cards for future-phase features, not blocking sync functionality |
| `backend/tests/integration/test_idempotency.py` | 82-129 | `test_duplicate_user_uuid_returns_existing` does not test user idempotency via a duplicate UUID | WARNING | Plan specified proving ON CONFLICT DO NOTHING for users. Test creates two different users instead. User service has `on_conflict_do_nothing` structurally, but no test proves it with a duplicate UUID. Company idempotency is fully proven with concurrent load test. Does not block goal achievement. |
| `ROADMAP.md` | 64 | `- [ ] 02-07-PLAN.md` checkbox unchecked despite plan being executed and complete | INFO | Documentation lag only. All 02-07 artifacts are in the codebase. ROADMAP.md should be updated to `[x] 02-07-PLAN.md` and Phase 2 plans count updated to 7/7. |

No BLOCKER anti-patterns. All core sync paths are substantive and wired.

---

## Human Verification Required

### 1. Offline-to-Online Round Trip

**Test:** Turn off device network, create a company via the app, turn network back on.
**Expected:** Company appears immediately in UI (from local Drift stream). After connectivity restore, app bar transitions: "N items pending" -> "Syncing 1 of 1..." -> "All synced". Company appears in backend database.
**Why human:** Requires real device, network toggle, and running backend. Cannot simulate connectivity change from source code inspection.

### 2. Exponential Backoff Retry Behavior

**Test:** Simulate 5xx from backend during sync (e.g., stop server mid-drain), verify retry delays.
**Expected:** Queue item is retried with 1s, 2s, 4s, 8s, 16s delays. After 5 failures, `attemptCount` resets to 0 and item stays pending for next connectivity cycle.
**Why human:** Timing behavior requires observing actual delay and requires the backend to be controllably failing.

### 3. Sync Status UI All 4 States

**Test:** Toggle network, create records, observe app bar subtitle across all 4 states.
**Expected:** "Offline" (wifi_off icon), "All synced" (green check), "N items pending" (sync icon), "Syncing X of Y..." (animated rotation). States update reactively without screen refresh.
**Why human:** Visual rendering, icon appearance, and animation cannot be verified from source code.

### 4. WorkManager 15-Minute Background Sync

**Test:** Background the app for 15+ minutes with pending queue items and network connected.
**Expected:** Items sync automatically in the background; queue is empty when app is foregrounded.
**Why human:** Background task scheduling requires a real Android device and cannot be verified programmatically.

### 5. Login Flow: OnboardingScreen to HomeScreen

**Test:** Launch the app, tap any login button (Admin / Contractor / Client) on the OnboardingScreen.
**Expected:** GoRouter fires the `AuthAuthenticated` redirect immediately. User lands on `/home` with the bottom navigation bar and sync status subtitle visible. Navigating back does not return to OnboardingScreen.
**Why human:** GoRouter redirect logic is verified by code inspection, but visual confirmation of the navigation transition and AppShell render requires a running Flutter app.

### 6. GET /api/v1/sync All Cursor Cases with Populated user_roles

**Test:** Run `alembic upgrade head` first. Then: (a) `GET /api/v1/sync` (absent), (b) `GET /api/v1/sync?cursor=` (empty string), (c) `GET /api/v1/sync?cursor=2026-01-01T00:00:00Z` (valid ISO8601), (d) `GET /api/v1/sync?cursor=notadate` (invalid). Also verify that user_roles array in responses (a) and (b) contains the seeded role records.
**Expected:** Cases a-c return HTTP 200 with valid `SyncResponse`. Case d returns HTTP 422. Cases a-b have non-empty `user_roles` (confirming migration 0003 backfill worked).
**Why human:** Requires running backend with PostgreSQL and migration 0003 applied. Code logic is verified by inspection; HTTP response and row count confirmation requires a live server.

### 7. Sync Status Shows 'Syncing 1 of 1...' Before 'All synced' on Connectivity Restore

**Test:** With one pending item in the queue, restore network connectivity and observe the app bar subtitle.
**Expected:** Subtitle shows "Syncing 1 of 1..." for at least one visible frame before transitioning to "All synced". The syncing state is visible — not skipped over.
**Why human:** The `Future<void>.delayed(Duration.zero)` frame yield is confirmed in code, but whether the Flutter rendering pipeline actually paints the syncing state as a distinct visible frame before completing requires observation on a running device.

---

## Gaps Summary

No gaps. All 9 observable truths are verified. All required artifacts exist, are substantive, and are wired.

The two remaining UAT-diagnosed runtime issues (user_roles empty array from NULL updated_at, sync status race condition preventing 'Syncing...' visibility) were closed by plan 02-07. All four 02-07 artifacts are confirmed in the actual codebase:

- `backend/migrations/versions/0003_backfill_user_roles_updated_at.py`: Migration with `UPDATE user_roles SET updated_at = created_at WHERE updated_at IS NULL` and `op.alter_column(..., nullable=False)`. Revision chain 0002 -> 0003 correct.
- `backend/app/features/users/models.py`: `UserRole.updated_at` is `Mapped[datetime]` / `nullable=False`, consistent with User and Company models.
- `mobile/lib/core/sync/sync_status_provider.dart`: Connectivity-restore `else` branch is empty — no premature `yield`. `lastEngineStatus` variable removed entirely. Engine exclusively drives the syncing -> allSynced state transition.
- `mobile/lib/core/sync/sync_engine.dart`: `await Future<void>.delayed(Duration.zero)` inserted between the initial syncing emit and the item-processing loop in `drainQueue()`.

Both INFRA-03 and INFRA-04 requirements are satisfied across all 7 plans. No regressions introduced in any previously verified truth.

One administrative action is recommended: update ROADMAP.md to mark `02-07-PLAN.md` as `[x]` and update the Phase 2 plans count from "7/7 plans complete" (which was correct for 02-06 closure) to reflect the executed state of 02-07.

The one persistent test deviation (user idempotency test weaker than specified in 02-05 plan) remains a WARNING. The structural implementation (`on_conflict_do_nothing`) is in place; only the proof-by-test is weaker than planned.

---

*Verified: 2026-03-05T23:55:00Z*
*Verifier: Claude (gsd-verifier)*
*Re-verification: Yes — after 02-07 gap closure (final two UAT-diagnosed bugs fixed)*
