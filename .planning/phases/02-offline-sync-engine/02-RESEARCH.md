# Phase 2: Offline Sync Engine - Research

**Researched:** 2026-03-05
**Domain:** Flutter offline-first sync, Drift SQLite outbox pattern, FastAPI delta sync, WorkManager background tasks
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Conflict Resolution:**
- Server always wins on all entity types — uniform strategy, no per-entity exceptions
- Silent overwrite — no notification to user when server version replaces local changes
- Client UUID idempotency key for create deduplication — server returns existing record if same UUID pushed twice
- Server-wins regardless of version number — no optimistic locking / no 409 Conflict responses
- Version number still incremented on every server write for audit trail and change detection
- Multi-device conflicts treated same as cross-user — server wins, no special case for same user on multiple devices

**Sync Failure & Retry:**
- Exponential backoff: 1s → 2s → 4s → 8s → 16s, max 5 retries per attempt cycle
- After max retries exhausted: item stays in queue, retries from scratch on next connectivity change
- 4xx errors (validation/bad data): park immediately, don't retry — retrying won't help
- 5xx errors and timeouts: standard retry with backoff
- FIFO queue ordering — items sync in creation order, respects causality

**Sync Status Indicator:**
- App bar subtitle: "All synced" / "3 items pending" / "Syncing 2 of 5..." / "Offline"
- Count + state detail level — enough to know what's happening without noise
- Always visible — "All synced" stays on screen, does not fade
- Offline transition: subtitle changes to "Offline" with subtle icon only — no toast, no banner
- No "last synced" timestamp shown — subtitle is sufficient

**Background Sync Triggers:**
- Foreground: immediate sync on every local write when online; queue when offline; drain queue on connectivity restore
- Background: periodic WorkManager sync every 15 minutes (Android minimum)
- Pull-to-refresh available on Home, Jobs, Schedule screens as manual trigger
- Cursor-based delta sync: GET /sync?cursor=<last_timestamp> returns all changed entities since cursor

**Sync Scope & Entity Types:**
- Phase 2 syncs companies, users, roles only — entities that exist from Phase 1
- Registry pattern for sync engine — each entity type registers its serializer, endpoint, and conflict strategy; future phases just add entries
- Bidirectional from the start — push local changes AND pull server changes
- Single delta endpoint returns all changed entity types in one response; client sorts by type locally
- Individual requests per queue item (not batched) — simpler error handling, per-item status tracking

**Data Freshness:**
- No "last synced" timestamp shown to user
- Show cached data immediately on app open, sync in background — UI updates reactively via Drift streams when new data arrives
- No loading spinner on app open

**Offline Data Limits:**
- No queue limit — contractor working offline for a week should never lose data
- Only current user's company data cached locally — aligns with RLS tenant isolation

**Soft Delete & Tombstones:**
- Soft delete with deleted_at timestamp — sync tombstone to other devices
- Enables undo, audit trail, and delete propagation across devices

**Sync Queue Persistence:**
- Queue stored as a Drift table (SQLite) — survives app kills, reboots, updates
- If killed mid-upload: item stays as "pending", re-sent on restart — idempotency key handles server-side dedup
- No special "in-flight" state needed

**Version Tracking:**
- Version incremented on every server write
- Server-wins regardless of version mismatch — version is for audit, not locking

**First Launch:**
- Full company dataset downloaded on first sync — typical contractor company (5-50 people) is small
- App works fully offline from first launch onward

**Testing Strategy:**
- Unit tests: mock Dio for sync engine logic (queue drain, retry, conflict resolution)
- Integration tests: real FastAPI + PostgreSQL (same pattern as Phase 1 RLS tests) for delta sync endpoint and idempotency
- Core scenarios: create offline → sync → server, server change → pull → local, duplicate push → idempotency, conflict → server wins, retry after failure
- Edge cases: concurrent edits from 2 devices, queue order preservation, sync after long offline period (100+ items), 4xx vs 5xx error handling

### Claude's Discretion
- Exact sync queue table schema design
- Delta sync response format (JSON structure)
- WorkManager configuration details
- Connectivity detection implementation (connectivity_plus package choice)
- Exact retry timing jitter
- Sync engine internal architecture (Isolate vs main thread)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INFRA-03 | Offline-first mobile app with local data storage | Drift outbox pattern, sync_queue table, sync_cursor table, deleted_at columns on existing tables, full local-first read pattern |
| INFRA-04 | Background sync engine with conflict resolution | SyncEngine service, WorkManager background periodic task, connectivity_plus for trigger, exponential backoff retry, server-wins conflict resolution, delta pull endpoint |
</phase_requirements>

---

## Summary

Phase 2 implements a transactional outbox sync engine on top of Phase 1's Drift + FastAPI foundation. The core pattern: every local write atomically also writes a row to `sync_queue`; the SyncEngine drains the queue item-by-item over HTTP, using the client-generated UUID as the idempotency key. Pulls use a cursor-based delta endpoint (`GET /api/v1/sync?cursor=<ISO8601_timestamp>`) that returns all changed entities since the cursor, which the client writes directly to Drift — triggering reactive UI updates automatically through existing Drift stream providers.

The stack is well-understood and all libraries are verified current as of 2026-03-05. The WorkManager minimum interval of 15 minutes is a hard Android constraint, not a design choice. The primary sync trigger is foreground (on-write + connectivity-restore); WorkManager is the safety net. Connectivity detection requires combining `connectivity_plus ^7.0.0` (network type detection) with actual request outcomes — connectivity_plus alone cannot guarantee internet access.

The main technical risk is WorkManager's separate Dart isolate: `getIt` singletons from the main isolate are unavailable. The solution is to call `setupServiceLocator()` again at the top of `callbackDispatcher`, which is the documented approach — a lightweight re-initialization creates a new `AppDatabase` instance pointing to the same SQLite file.

**Primary recommendation:** Implement SyncEngine as a plain Dart service (not an Isolate) running on the main Flutter isolate, registered via getIt. WorkManager callbackDispatcher re-initializes service locator independently. Use `connectivity_plus` stream for trigger, `dio_smart_retry` for HTTP retry, and `postgresql` `INSERT ... ON CONFLICT DO NOTHING` for backend idempotency.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| drift | ^2.32.0 | Local SQLite ORM + reactive streams | Already in project; generates sync_queue table and stepByStep migrations |
| workmanager | ^0.9.0+3 | Android background periodic task | Flutter-community federated package; only viable background scheduler on Android |
| connectivity_plus | ^7.0.0 | Network type change stream | Flutter-community maintained; provides `onConnectivityChanged` stream for sync triggers |
| internet_connection_checker_plus | ^2.9.1+2 | Verify actual internet access | connectivity_plus only detects network type; this verifies real HTTP reachability |
| dio_smart_retry | ^7.0.1 | Retry interceptor for DioClient | Configurable per-status-code retry; integrates as Dio interceptor on existing DioClient |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| uuid | ^4.0.0 | Client-generated idempotency keys | Already in project; Uuid().v4() for sync_queue.id and as idempotency key |
| mocktail | ^1.0.4 | Mock Dio + SyncEngine in unit tests | Already in dev deps; use for queue drain, retry, conflict unit tests |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| connectivity_plus + checker | Relying on Dio errors alone | Simpler but no proactive trigger on connectivity restore — misses the key UX requirement |
| workmanager | flutter_foreground_service | WorkManager is OS-managed and battery-aware; foreground service keeps notification in tray, worse UX |
| Individual per-item HTTP requests | Batched request | Locked decision — individual per-item; simpler error tracking |

**Installation:**
```bash
# In mobile/pubspec.yaml — add to dependencies:
flutter pub add workmanager connectivity_plus internet_connection_checker_plus dio_smart_retry
```

---

## Architecture Patterns

### Recommended Project Structure
```
mobile/lib/core/sync/
├── sync_engine.dart          # Queue drain, retry loop, connectivity trigger
├── sync_registry.dart        # Entity type → serializer + endpoint map
├── connectivity_service.dart # Wraps connectivity_plus + internet checker
├── sync_status_notifier.dart # @riverpod Notifier<SyncStatus> for UI
└── workmanager_dispatcher.dart  # Top-level callbackDispatcher + re-init

mobile/lib/core/database/tables/
├── sync_queue.dart           # New: outbox table
├── sync_cursor.dart          # New: one-row cursor storage
├── companies.dart            # Modified: add deleted_at column
├── users.dart                # Modified: add deleted_at column
└── user_roles.dart           # Modified: add deleted_at column

backend/app/features/sync/
├── __init__.py
├── router.py                 # GET /api/v1/sync?cursor=<ts>
├── schemas.py                # SyncResponse Pydantic models
└── service.py                # Multi-table delta query with updated_at filter
```

### Pattern 1: Transactional Outbox (Atomic Write + Queue)

**What:** Every mutating local operation writes both to the entity table AND the sync_queue table inside a single Drift transaction. This guarantees the queue entry is never lost.

**When to use:** All local creates, updates, and soft-deletes.

**Example:**
```dart
// Source: Drift docs + offline-first pattern (geekyants.com/blog/offline-first-flutter-implementation-blueprint-for-real-world-apps)
Future<void> createCompanyLocally(CompaniesCompanion entry) async {
  await db.transaction(() async {
    // 1. Write to entity table
    await db.into(db.companies).insert(entry);

    // 2. Write to outbox — same transaction, atomic
    await db.into(db.syncQueue).insert(
      SyncQueueCompanion(
        id: Value(const Uuid().v4()),      // idempotency key
        entityType: const Value('company'),
        entityId: Value(entry.id.value),
        operation: const Value('CREATE'),
        payload: Value(jsonEncode(entry.toJson())),
        status: const Value('pending'),
        attemptCount: const Value(0),
        createdAt: Value(DateTime.now()),
      ),
    );
  });
}
```

### Pattern 2: SyncEngine Queue Drain

**What:** SyncEngine holds a lock flag (`_isSyncing`). When triggered, it queries all `status = 'pending'` rows ordered by `createdAt ASC`, processes them one at a time, and handles retry/park logic per item.

**When to use:** On every local write (if online), on connectivity restore, on pull-to-refresh, on WorkManager callback.

**Example:**
```dart
// Source: Research synthesis from flutter.dev offline-first + geekyants pattern
class SyncEngine {
  bool _isSyncing = false;
  static const _maxAttempts = 5;
  static const _backoffDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
  ];

  Future<void> drainQueue() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final items = await _db.syncQueueDao.getPendingItems(); // ORDER BY createdAt ASC
      for (final item in items) {
        await _processItem(item);
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _processItem(SyncQueueItem item) async {
    final handler = _registry.getHandler(item.entityType);
    try {
      await handler.push(item);
      await _db.syncQueueDao.markSynced(item.id);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != null && status >= 400 && status < 500) {
        // 4xx — park, don't retry
        await _db.syncQueueDao.markParked(item.id, error: e.message);
      } else {
        // 5xx / timeout — increment attempt, schedule next try
        final nextAttempt = item.attemptCount + 1;
        if (nextAttempt >= _maxAttempts) {
          // Leave as pending — will retry from scratch on next connectivity restore
          await _db.syncQueueDao.updateAttemptCount(item.id, nextAttempt);
        } else {
          await Future.delayed(_backoffDelays[nextAttempt - 1]);
          await _db.syncQueueDao.updateAttemptCount(item.id, nextAttempt);
        }
      }
    }
  }
}
```

### Pattern 3: Registry Pattern for Entity Types

**What:** A `SyncRegistry` maps entity type strings to handler objects that know the API endpoint, payload serialization, and response deserialization. Adding a new entity type in Phase 3+ = add one entry.

**Example:**
```dart
// Source: Research synthesis — registry/factory pattern
abstract class SyncHandler {
  String get entityType;
  Future<void> push(SyncQueueItem item);
}

class SyncRegistry {
  final _handlers = <String, SyncHandler>{};

  void register(SyncHandler handler) {
    _handlers[handler.entityType] = handler;
  }

  SyncHandler getHandler(String entityType) {
    final handler = _handlers[entityType];
    if (handler == null) throw StateError('No handler for $entityType');
    return handler;
  }
}

// Phase 2 registration in setupServiceLocator:
registry.register(CompanySyncHandler(dioClient));
registry.register(UserSyncHandler(dioClient));
registry.register(UserRoleSyncHandler(dioClient));
```

### Pattern 4: WorkManager Background Isolate Re-initialization

**What:** `callbackDispatcher` runs in a separate Dart isolate with its own memory. `getIt` singletons are NOT shared. Must call `setupServiceLocator()` inside `callbackDispatcher` to access `AppDatabase` and `SyncEngine`.

**Critical constraint:** `callbackDispatcher` must be a top-level function annotated with `@pragma('vm:entry-point')`.

**Example:**
```dart
// Source: workmanager docs (docs.page/fluttercommunity/flutter_workmanager)
// + GetIt isolate issue #103 (github.com/fluttercommunity/get_it/issues/103)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // CRITICAL: re-initialize all dependencies — separate isolate, fresh memory
    WidgetsFlutterBinding.ensureInitialized();
    await setupServiceLocator();

    final syncEngine = getIt<SyncEngine>();
    await syncEngine.drainQueue();
    await syncEngine.pullDelta();
    return Future.value(true);
  });
}

// In main():
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupServiceLocator();
  Workmanager().initialize(callbackDispatcher);
  Workmanager().registerPeriodicTask(
    'contractorhub-sync',
    'backgroundSync',
    frequency: const Duration(minutes: 15), // Android minimum
    constraints: Constraints(networkType: NetworkType.connected),
  );
  runApp(const App());
}
```

### Pattern 5: Delta Pull from Backend

**What:** Client sends `GET /api/v1/sync?cursor=<ISO8601>`. Server returns all entities (companies, users, user_roles) updated after the cursor, plus tombstones (deleted_at IS NOT NULL). Client upserts each entity into Drift, then updates the local cursor.

**Backend FastAPI pattern:**
```python
# Source: SQLAlchemy 2.0 docs + research synthesis
@router.get("/sync", response_model=SyncResponse)
async def delta_sync(
    cursor: datetime | None = Query(None, description="ISO8601 timestamp"),
    db: AsyncSession = Depends(get_db),
) -> SyncResponse:
    since = cursor or datetime(2000, 1, 1, tzinfo=timezone.utc)

    # Query all entity types with single filter
    companies = await service.get_companies_since(db, since)
    users = await service.get_users_since(db, since)
    user_roles = await service.get_user_roles_since(db, since)

    return SyncResponse(
        companies=companies,
        users=users,
        user_roles=user_roles,
        server_timestamp=datetime.now(timezone.utc),
    )
```

**Backend service query pattern:**
```python
# Source: SQLAlchemy 2.0 docs (docs.sqlalchemy.org/en/20/orm/queryguide/select.html)
async def get_companies_since(db: AsyncSession, since: datetime):
    result = await db.execute(
        select(Company).where(
            or_(
                Company.updated_at > since,
                Company.deleted_at > since,   # include tombstones
            )
        )
    )
    return result.scalars().all()
```

**Client cursor update:**
```dart
// After successful pull:
await db.syncCursorDao.updateCursor(response.serverTimestamp);
```

### Pattern 6: Backend Idempotent Create (INSERT ON CONFLICT DO NOTHING)

**What:** Client sends `POST /api/v1/companies` with UUID in payload. If server receives the same UUID twice, the second insert silently does nothing and returns the existing record. No 409 response.

**Example:**
```python
# Source: SQLAlchemy 2.0 PostgreSQL docs (docs.sqlalchemy.org/en/20/dialects/postgresql.html)
from sqlalchemy.dialects.postgresql import insert

async def create_company_idempotent(db: AsyncSession, data: CompanyCreate) -> Company:
    stmt = insert(Company).values(
        id=data.id,  # client-provided UUID
        name=data.name,
        # ... other fields
    ).on_conflict_do_nothing(index_elements=["id"])

    await db.execute(stmt)
    await db.flush()

    # Fetch and return (whether newly created or existing)
    result = await db.get(Company, data.id)
    return result
```

### Pattern 7: Sync Status Riverpod Notifier

**What:** A `@riverpod` class watches the sync_queue table count and the connectivity state to emit typed `SyncStatus` values for the app bar subtitle.

**Example:**
```dart
// Source: Riverpod 3.x @riverpod annotation pattern (riverpod.dev)
enum SyncState { offline, allSynced, pending, syncing }

class SyncStatus {
  final SyncState state;
  final int pendingCount;
  final int? syncingOf;  // e.g. "Syncing 2 of 5"
  const SyncStatus(this.state, this.pendingCount, {this.syncingOf});

  String get subtitle => switch (state) {
    SyncState.offline => 'Offline',
    SyncState.allSynced => 'All synced',
    SyncState.pending => '$pendingCount item${pendingCount == 1 ? '' : 's'} pending',
    SyncState.syncing => 'Syncing ${syncingOf ?? ''} of $pendingCount...',
  };
}

@riverpod
Stream<SyncStatus> syncStatus(Ref ref) {
  // Combine pending count stream (Drift) + connectivity stream
  final db = getIt<AppDatabase>();
  return db.syncQueueDao.watchPendingCount().map((count) {
    // Connectivity state injected from ConnectivityService
    return count == 0
        ? const SyncStatus(SyncState.allSynced, 0)
        : SyncStatus(SyncState.pending, count);
  });
}
```

### Anti-Patterns to Avoid

- **Separate pending/in-flight status:** The CONTEXT.md decision is: no "in-flight" state. Items are `pending` until `synced` or `parked`. If killed mid-upload, idempotency handles the duplicate on next send.
- **Timer.periodic for foreground sync:** Use the direct call from ConnectivityService stream instead. Timer.periodic leaks if widget is disposed.
- **Sharing `getIt` instance across isolates:** Impossible — isolates have separate memory. Always re-initialize inside `callbackDispatcher`.
- **`connectivity_plus` alone for "is online" check:** Only tells network type (WiFi/mobile), not actual internet reachability. Combine with try-catch on actual HTTP call or `internet_connection_checker_plus`.
- **Awaiting HTTP in UI widget:** The offline-first invariant from Phase 1. All reads must come from Drift streams.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP retry with backoff | Custom retry loop inside SyncEngine | `dio_smart_retry` interceptor | Handles 19 status codes, configurable delays, already a Dio interceptor — no state machine needed |
| Connectivity stream | `Timer.periodic` polling | `connectivity_plus` `onConnectivityChanged` stream | OS push notification, no polling cost |
| Internet reachability check | DNS lookup or manual ping | `internet_connection_checker_plus` `hasInternetAccess` | Pings multiple CDN endpoints with sub-second timeout, proven reliable |
| Background task scheduling | dart:isolate + custom wakeup | `workmanager` | Only WorkManager survives Doze mode, app kill, device restart on Android |
| PostgreSQL upsert dedup | Application-level duplicate check + transaction | `INSERT ... ON CONFLICT DO NOTHING` | Atomic, race-condition-free, single SQL statement |

**Key insight:** The Android OS aggressively kills background work. Only WorkManager (backed by Android's JobScheduler) can reliably wake up the app after an OS kill or Doze mode. Any custom background scheduling will fail under real-world conditions.

---

## Common Pitfalls

### Pitfall 1: WorkManager Isolate — getIt Not Available
**What goes wrong:** `callbackDispatcher` accesses `getIt<SyncEngine>()` and crashes with "No instance registered" because the background isolate has fresh memory — no singletons from `main()`.
**Why it happens:** Flutter isolates have separate memory heaps. WorkManager spawns a new Dart isolate for each background task.
**How to avoid:** Always call `await setupServiceLocator()` at the top of `callbackDispatcher` before accessing any `getIt` registered service.
**Warning signs:** `StateError: No instance of type T is registered inside GetIt` in background task logs.

### Pitfall 2: connectivity_plus Reports Connected But HTTP Fails
**What goes wrong:** Sync engine triggers on connectivity change, attempts HTTP, gets timeout. This happens on captive portals (hotel WiFi), weak cellular signal, or airplane mode transition.
**Why it happens:** `connectivity_plus` detects network layer (WiFi adapter connected), not IP layer reachability.
**How to avoid:** Treat `DioException` (timeout/connection error) as "will retry later" — the retry logic handles this. Optionally use `internet_connection_checker_plus.hasInternetAccess` before starting a sync cycle to skip the attempt entirely.
**Warning signs:** Sync engine spinning on connectivity events without making actual progress.

### Pitfall 3: Drift Migration schemaVersion Mismatch
**What goes wrong:** Adding `sync_queue`, `sync_cursor` tables and `deleted_at` columns to existing tables without incrementing `schemaVersion` from 1 to 2, and without running `dart run drift_dev make-migrations` to generate step files.
**Why it happens:** Drift reads `schemaVersion` to decide if `onUpgrade` runs. If version stays at 1, the new tables are never created on existing installs — only fresh installs get them.
**How to avoid:**
1. Set `schemaVersion => 2` in `app_database.dart`
2. Run `dart run drift_dev make-migrations` to generate schema snapshot + `.steps.dart`
3. Implement `from1To2` migration: `createTable(schema.syncQueue)`, `createTable(schema.syncCursor)`, `addColumn(schema.companies, schema.companies.deletedAt)`, etc.
**Warning signs:** `no such table: sync_queue` crashes on devices that were installed with schema v1.

### Pitfall 4: Soft Delete Not Included in Delta Pull Filter
**What goes wrong:** Backend delta sync query filters `WHERE updated_at > cursor` but does not include `OR deleted_at > cursor`. Deleted records never propagate to other devices.
**Why it happens:** Standard pattern is to filter on `updated_at`; tombstones require also checking `deleted_at`.
**How to avoid:** Use SQLAlchemy `or_(Model.updated_at > since, Model.deleted_at > since)` in the delta service query. Client must handle `deletedAt != null` as a delete signal — remove from Drift or mark locally deleted.
**Warning signs:** Deleted records reappear on other devices after sync.

### Pitfall 5: WorkManager 15-Minute Minimum Ignored
**What goes wrong:** Registering periodic task with `frequency: Duration(minutes: 5)` — WorkManager silently clamps to 15 minutes on Android. If the developer tests and sees "it works at 5 min" on a debug build, the OS may enforce 15 min on release or newer Android versions.
**Why it happens:** Android WorkManager enforces a minimum periodic interval of 15 minutes as a battery protection policy.
**How to avoid:** Always register with `frequency: Duration(minutes: 15)` explicitly. The primary sync mechanism (foreground on-write + connectivity-restore) handles near-realtime sync. WorkManager is the safety net.
**Warning signs:** Sync works in foreground but users report stale data after app is backgrounded.

### Pitfall 6: SQLAlchemy updated_at Not Auto-Updating on ORM Bulk Operations
**What goes wrong:** Backend uses `stmt.update()` bulk operations to apply server-wins overwrites. The `onupdate=func.now()` for `updated_at` only fires on individual ORM `session.add()` + `commit()`. Bulk statements bypass this.
**Why it happens:** SQLAlchemy's `onupdate` is an ORM-level hook, not a database trigger.
**How to avoid:** Use PostgreSQL trigger for `updated_at` (add in Alembic migration: `CREATE TRIGGER set_updated_at BEFORE UPDATE ON companies ...`) OR explicitly set `updated_at=func.now()` in all UPDATE statements.
**Warning signs:** `updated_at` timestamps not advancing after server-side updates, breaking delta sync cursor.

### Pitfall 7: First-Launch Race Condition
**What goes wrong:** App opens, Drift streams emit empty lists (no local data yet), UI shows empty state. Background pull runs and populates data, but user has already seen confusing empty state.
**Why it happens:** Full initial download is async; local DB is empty on first install.
**How to avoid:** First launch detection: check `syncCursorDao.getCursor() == null`. If null, show a lightweight "Setting up..." splash or loading state before navigating to main shell. After initial pull completes, navigate. This only happens once.
**Warning signs:** Users report empty screens on first install.

---

## Code Examples

Verified patterns from official sources:

### Drift sync_queue Table Definition
```dart
// Source: Drift docs (drift.simonbinder.eu/dart_api/tables/)
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

class SyncQueue extends Table {
  // Also serves as idempotency key — client UUID sent as Idempotency-Key header
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get entityType => text()();   // 'company' | 'user' | 'user_role'
  TextColumn get entityId => text()();     // UUID of the entity being synced
  TextColumn get operation => text()();    // 'CREATE' | 'UPDATE' | 'DELETE'
  TextColumn get payload => text()();      // JSON-encoded entity data
  // status: 'pending' | 'synced' | 'parked'
  // 'parked' = 4xx error, won't retry automatically
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### Drift sync_cursor Table Definition
```dart
// Source: Research synthesis — single-row keyed table pattern
class SyncCursor extends Table {
  // Always one row with key='main'
  TextColumn get key => text().withDefault(const Constant('main'))();
  DateTimeColumn get lastPulledAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}
```

### Drift Schema Migration (v1 → v2)
```dart
// Source: Drift migration docs (drift.simonbinder.eu/migrations/)
// app_database.dart
@DriftDatabase(
  tables: [Companies, Users, UserRoles, SyncQueue, SyncCursor],
  daos: [CompanyDao, UserDao, SyncQueueDao, SyncCursorDao],
)
class AppDatabase extends _$AppDatabase {
  @override
  int get schemaVersion => 2;  // Bumped from 1

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => await m.createAll(),
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        // Add new tables
        await m.createTable(schema.syncQueue);
        await m.createTable(schema.syncCursor);
        // Add soft-delete columns to existing tables
        await m.addColumn(schema.companies, schema.companies.deletedAt);
        await m.addColumn(schema.users, schema.users.deletedAt);
        await m.addColumn(schema.userRoles, schema.userRoles.deletedAt);
      },
    ),
  );
}
```

### Drift Table: Add deleted_at Column
```dart
// Source: Drift tables docs (drift.simonbinder.eu/dart_api/tables/)
// companies.dart — updated
class Companies extends Table {
  // ... existing columns ...
  DateTimeColumn get deletedAt => dateTime().nullable()();  // null = active record
}
```

### Connectivity Service
```dart
// Source: connectivity_plus ^7.0.0 docs + internet_connection_checker_plus ^2.9.1
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

class ConnectivityService {
  final _connectivity = Connectivity();
  StreamSubscription? _subscription;

  void startListening(VoidCallback onConnected) {
    _subscription = _connectivity.onConnectivityChanged.listen(
      (results) async {
        final hasNetwork = results.any((r) => r != ConnectivityResult.none);
        if (hasNetwork) {
          // Verify actual internet, not just network type
          final hasInternet = await InternetConnection().hasInternetAccess;
          if (hasInternet) onConnected();
        }
      },
    );
  }

  void dispose() => _subscription?.cancel();
}
```

### DioClient: Add Idempotency Key Header + Retry Interceptor
```dart
// Source: dio_smart_retry ^7.0.1 docs (pub.dev/packages/dio_smart_retry)
import 'package:dio_smart_retry/dio_smart_retry.dart';

class DioClient {
  late final Dio _dio;

  DioClient() {
    _dio = Dio(BaseOptions( /* ... existing config ... */ ));

    // Retry interceptor — 5xx and timeouts only; 4xx not retried
    _dio.interceptors.add(RetryInterceptor(
      dio: _dio,
      retries: 5,
      retryDelays: const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 16),
      ],
      // Do not retry 4xx client errors
      retryEvaluator: (error, attempt) {
        final status = error.response?.statusCode;
        if (status != null && status >= 400 && status < 500) {
          return false; // park, not retried at HTTP layer
        }
        return true;
      },
    ));

    // Per-request idempotency key header (set by SyncEngine before each push)
    _dio.interceptors.add(LogInterceptor( /* ... */ ));
  }

  Future<Response> pushWithIdempotency(
    String path,
    Map<String, dynamic> data,
    String idempotencyKey,
  ) {
    return _dio.post(
      path,
      data: data,
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
  }
}
```

### FastAPI Delta Sync Endpoint
```python
# Source: FastAPI docs + SQLAlchemy 2.0 or_() filter pattern
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, Query
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

router = APIRouter(prefix="/sync", tags=["sync"])

@router.get("", response_model=SyncResponse)
async def delta_sync(
    cursor: datetime | None = Query(None, description="ISO8601 timestamp of last sync"),
    db: AsyncSession = Depends(get_db),
) -> SyncResponse:
    """Return all entities changed since cursor. Includes tombstones (deleted_at set)."""
    since = cursor or datetime(2000, 1, 1, tzinfo=timezone.utc)

    companies_result = await db.execute(
        select(Company).where(
            or_(Company.updated_at > since, Company.deleted_at > since)
        )
    )
    users_result = await db.execute(
        select(User).where(
            or_(User.updated_at > since, User.deleted_at > since)
        )
    )
    roles_result = await db.execute(
        select(UserRole).where(
            or_(UserRole.updated_at > since, UserRole.deleted_at > since)
        )
    )

    return SyncResponse(
        companies=[CompanyResponse.model_validate(c) for c in companies_result.scalars()],
        users=[UserResponse.model_validate(u) for u in users_result.scalars()],
        user_roles=[UserRoleResponse.model_validate(r) for r in roles_result.scalars()],
        server_timestamp=datetime.now(timezone.utc).isoformat(),
    )
```

### FastAPI Idempotent Upsert
```python
# Source: SQLAlchemy PostgreSQL dialect docs (docs.sqlalchemy.org/en/20/dialects/postgresql.html)
from sqlalchemy.dialects.postgresql import insert

async def upsert_company(db: AsyncSession, data: CompanyCreate) -> Company:
    """Create company if not exists. Silent no-op if UUID already present."""
    stmt = insert(Company).values(
        id=data.id,
        name=data.name,
        company_id=get_current_tenant_id(),
        version=1,
        created_at=func.now(),
        updated_at=func.now(),
    ).on_conflict_do_nothing(index_elements=["id"])

    await db.execute(stmt)
    # Fetch regardless — returns existing record on conflict
    result = await db.execute(select(Company).where(Company.id == data.id))
    return result.scalar_one()
```

### Alembic Migration: Add deleted_at + updated_at trigger
```python
# Source: Alembic docs + PostgreSQL trigger pattern
# migrations/versions/0002_soft_delete_sync.py

def upgrade() -> None:
    # Add deleted_at to all entity tables
    for table in ['companies', 'users', 'user_roles']:
        op.add_column(table, sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True))

    # PostgreSQL trigger to auto-update updated_at on UPDATE
    # Critical: SQLAlchemy onupdate= is ORM-level; bulk updates bypass it
    op.execute("""
        CREATE OR REPLACE FUNCTION set_updated_at()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.updated_at = NOW();
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
    """)
    for table in ['companies', 'users']:
        op.execute(f"""
            CREATE TRIGGER set_{table}_updated_at
            BEFORE UPDATE ON {table}
            FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        """)

def downgrade() -> None:
    for table in ['companies', 'users']:
        op.execute(f"DROP TRIGGER IF EXISTS set_{table}_updated_at ON {table};")
    op.execute("DROP FUNCTION IF EXISTS set_updated_at();")
    for table in ['companies', 'users', 'user_roles']:
        op.drop_column(table, 'deleted_at')
```

### RefreshIndicator (Pull-to-Refresh)
```dart
// Source: Flutter docs (api.flutter.dev/flutter/material/RefreshIndicator-class.html)
// Wrap existing ListView/SingleChildScrollView in RefreshIndicator
RefreshIndicator(
  onRefresh: () async {
    final syncEngine = getIt<SyncEngine>();
    await syncEngine.drainQueue();
    await syncEngine.pullDelta();
  },
  child: ListView( /* existing content */ ),
)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `connectivity` plugin | `connectivity_plus ^7.0.0` | Flutter Community Plus migration (2021+) | New API; `onConnectivityChanged` returns `List<ConnectivityResult>` not single value |
| `StateNotifier` for sync status | `@riverpod` `Notifier` | Riverpod 3.0 (Sep 2025) | `StateNotifier` moved to legacy import; use `@riverpod class` annotation instead |
| Manual migration in `onUpgrade` | `stepByStep` + `dart run drift_dev make-migrations` | Drift 2.x | Generated `.steps.dart` provides type-safe migration with schema snapshots; strongly preferred |
| SQLAlchemy 1.x `Query` API | SQLAlchemy 2.0 `select()` + `scalars()` | SQLAlchemy 2.0 (2023) | Old query API removed; use `await db.execute(select(Model).where(...))` |

**Deprecated/outdated:**
- `connectivity`: Replaced by `connectivity_plus`. Do not use.
- `StateNotifierProvider`: Moved to `riverpod/legacy.dart` in Riverpod 3.0. Use `@riverpod class` Notifier.
- `workmanager` versions < 0.9: Breaking API changes. Current is 0.9.0+3.

---

## Open Questions

1. **Drift `make-migrations` workflow without Flutter SDK installed**
   - What we know: `dart run drift_dev make-migrations` requires `dart` CLI, which is part of Flutter SDK. STATE.md notes "Flutter SDK not installed".
   - What's unclear: Whether the developer environment will have Flutter installed before Phase 2 implementation begins.
   - Recommendation: Plans should document the SDK installation step before running `make-migrations`. As a fallback, the manual `onUpgrade` migration approach (without generated `.steps.dart`) works correctly — it's just less type-safe.

2. **Android manifest permissions for connectivity_plus**
   - What we know: `ACCESS_NETWORK_STATE` permission is required for `connectivity_plus`. `INTERNET` permission is needed for HTTP calls.
   - What's unclear: Whether Phase 1's `AndroidManifest.xml` already includes these (likely yes for `INTERNET`).
   - Recommendation: Plan 02-02 should verify and add `<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>` if missing.

3. **`user_roles` updated_at column absence**
   - What we know: The existing `UserRoles` table has `createdAt` but NOT `updatedAt`. The delta sync filter relies on `updated_at > cursor`.
   - What's unclear: Whether roles need an `updated_at` for delta tracking or if re-fetching all roles on every sync is acceptable.
   - Recommendation: Add `updated_at` to `user_roles` in the v2 migration. If a role's only mutation is create/delete, `updated_at = created_at` initially and `deleted_at` covers deletions — the delta filter `OR deleted_at > since` covers the delete tombstone case.

---

## Sources

### Primary (HIGH confidence)
- `drift.simonbinder.eu/migrations/` — stepByStep migration pattern, addColumn, createTable API
- `drift.simonbinder.eu/migrations/api/` — Migrator class methods with code examples
- `docs.sqlalchemy.org/en/20/dialects/postgresql.html` — `INSERT ... ON CONFLICT DO NOTHING` with asyncpg
- `pub.dev/packages/workmanager` — version 0.9.0+3, platform support, federated architecture
- `pub.dev/packages/connectivity_plus` — version 7.0.0, `onConnectivityChanged` API, limitations
- `pub.dev/packages/internet_connection_checker_plus` — version 2.9.1+2, `hasInternetAccess` API
- `pub.dev/packages/dio_smart_retry` — version 7.0.1, `RetryInterceptor` configuration
- `docs.page/fluttercommunity/flutter_workmanager` — Android setup (no AndroidManifest changes required), `callbackDispatcher` top-level requirement, `@pragma('vm:entry-point')`, 15-minute minimum
- `docs.flutter.dev/app-architecture/design-patterns/offline-first` — offline-first repository and sync patterns
- `api.flutter.dev/flutter/material/RefreshIndicator-class.html` — `RefreshIndicator` usage

### Secondary (MEDIUM confidence)
- `geekyants.com/blog/offline-first-flutter-implementation-blueprint-for-real-world-apps` — Transactional outbox pattern, SyncEngine processing loop, exponential backoff (verified against official patterns)
- `github.com/fluttercommunity/get_it/issues/103` — GetIt not available in WorkManager isolate (community-confirmed, widely documented)
- `github.com/fluttercommunity/flutter_workmanager/issues/204` — 15-minute minimum interval confirmed with OS clamping behavior

### Tertiary (LOW confidence — flagged for validation)
- `dev.to/anurag_dev/implementing-offline-first-architecture-in-flutter-part-2-...` — SyncEngine class structure (article uses simpler pattern; production implementation will differ)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries verified on pub.dev with current versions
- Architecture: HIGH — patterns verified against official Flutter and Drift docs
- Drift migrations: HIGH — verified against drift.simonbinder.eu migration docs
- WorkManager isolate re-init: HIGH — confirmed by multiple official GitHub issues and docs
- FastAPI delta sync: HIGH — SQLAlchemy 2.0 `or_()` + `on_conflict_do_nothing` from official docs
- Pitfalls: MEDIUM-HIGH — most verified via official docs; soft-delete delta filter from research synthesis

**Research date:** 2026-03-05
**Valid until:** 2026-04-05 (stable libraries; connectivity_plus and workmanager APIs are stable)
