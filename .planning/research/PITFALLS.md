# Pitfalls Research

**Domain:** Offline-first multi-tenant contractor management SaaS (Flutter + Python/FastAPI)
**Researched:** 2026-03-04
**Confidence:** MEDIUM-HIGH (core patterns well-documented; some Flutter-specific offline gotchas from community sources)

---

## Critical Pitfalls

### Pitfall 1: Offline-First Retrofitted Instead of Architected From Day One

**What goes wrong:**
The team starts building online-first (API calls on every user action, UI driven by server state), then tries to bolt on offline support later. This requires complete re-architecture of the data layer, UI state management, and sync logic. The Flutter side needs a local data layer, an action queue, a conflict resolver, and a sync engine — none of which are trivially added after the fact.

**Why it happens:**
Online-first is the default mental model. Developers test on their local machines with fast WiFi, so connectivity failures feel theoretical until real users in the field report data loss.

**How to avoid:**
Treat offline-first as the foundational architecture decision, not a feature. From Phase 1, the Flutter app reads exclusively from a local SQLite database (via `sqflite` or `drift`). Network calls write to a pending action queue, not directly to the UI. The backend is a sync target, never the source of truth for the local app state.

**Warning signs:**
- Any `await http.get(...)` that directly populates a UI widget without local cache
- No local database in the project after the first sprint
- "We'll add offline later" in any planning discussion

**Phase to address:**
Foundation / Architecture phase — must be locked in before any feature work begins.

---

### Pitfall 2: Silent Data Overwrite During Sync (Last-Write-Wins Without Version Control)

**What goes wrong:**
Contractor A edits a job offline for 2 hours. Dispatcher also edits the same job on the web/another device. When contractor syncs, the app uploads without checking whether the server version has advanced. The server silently accepts the older version, discarding the dispatcher's changes. Nobody notices until the job shows up at the wrong address.

**Why it happens:**
Last-write-wins (LWW) by timestamp is easy to implement and appears to work in testing (single device, single user). The failure only surfaces under concurrent multi-device usage.

**How to avoid:**
Every entity must carry a `version` integer or `updated_at` UTC timestamp. The sync endpoint must check: if `server_version > client_version`, reject the write and return the conflict payload. The client must present a resolution UI or apply a field-level merge strategy. For scheduling data (job assignments, availability blocks), use pessimistic locking — the server rejects the update rather than silently overwriting.

**Warning signs:**
- No `version`, `etag`, or `updated_at` columns in the data model
- PUT/PATCH endpoints that accept updates without checking current server state
- "Sync" implemented as a simple `POST` of all local records

**Phase to address:**
Data sync / offline architecture phase. Conflict detection schema (version columns) must be established during database design, before any sync code is written.

---

### Pitfall 3: Missing Tenant Context on Background Tasks

**What goes wrong:**
FastAPI middleware correctly scopes all HTTP requests to the authenticated tenant. But background tasks (Celery workers, FastAPI `BackgroundTasks`, scheduled jobs) do not go through middleware. A task that sends "job completed" notifications runs without a tenant context, queries `SELECT * FROM jobs WHERE status = 'complete'` without a tenant filter, and either crashes, returns nothing, or — in the worst case — notifies the wrong company's clients.

**Why it happens:**
HTTP middleware is the standard pattern for injecting tenant context. Developers assume this coverage extends to all async work. Async task queues (Celery, ARQ, FastAPI background tasks) are called from within a request but execute outside it, stripping the request-scoped context variable.

**How to avoid:**
Serialize `tenant_id` explicitly into every task payload. At task execution start, explicitly set the tenant context (via a `ContextVar` or SQLAlchemy session scoping) before any database access. Create a decorator or base task class that enforces this contract — tasks that don't receive `tenant_id` in their kwargs should fail loudly at startup. Never rely on global or request-scoped context inside workers.

**Warning signs:**
- Background tasks that take `job_id` but not `tenant_id` as a parameter
- No tenant-scoping tests for async notification paths
- Workers that use a `db` session without setting tenant context first

**Phase to address:**
Multi-tenant foundation phase. The pattern must be established when the first background task is written, not after.

---

### Pitfall 4: Scheduling Race Condition — Double-Booking Under Concurrent Requests

**What goes wrong:**
Two dispatchers at the same company simultaneously assign different jobs to contractor Hana. Both read her availability, see she's free at 10am Tuesday, and write the booking. Without database-level locking, both transactions succeed, and Hana has two jobs at 10am Tuesday. The conflict detection logic in the application layer checked availability before writing, but the check and the write are not atomic.

**Why it happens:**
Application-level checks are not a substitute for database-level serialization. "Check then act" patterns fail under concurrent load. This is subtle in development (single-user testing) but surfaces immediately in production with multiple dispatchers or when the mobile app and the web dashboard write simultaneously.

**How to avoid:**
Use PostgreSQL advisory locks or row-level pessimistic locking (`SELECT ... FOR UPDATE`) when reading a contractor's schedule slots before writing a new booking. The availability check and the insert must be in the same database transaction with the lock held. Alternatively, use a unique constraint on `(contractor_id, time_slot_start)` as a last-resort guard that makes duplicate bookings fail loudly rather than silently.

**Warning signs:**
- Scheduling endpoints that do `SELECT availability`, then `INSERT booking` as two separate database calls without a transaction
- No database-level unique constraints on contractor time slots
- Load tests not included in scheduling feature tests

**Phase to address:**
Scheduling engine phase. Must be addressed during initial scheduler design, not after.

---

### Pitfall 5: Multi-Tenant Data Leak via Missing WHERE Clause

**What goes wrong:**
A developer writes `SELECT * FROM jobs WHERE id = $1` instead of `SELECT * FROM jobs WHERE id = $1 AND tenant_id = $2`. An admin from Company A can retrieve Company B's job by guessing or iterating the ID. This is a catastrophic trust violation in a SaaS context — it can end the product.

**Why it happens:**
Developers add `tenant_id` to the schema but forget to include it in individual query filters, especially on admin/internal endpoints, bulk export queries, or reporting queries added under deadline. Even one missed filter is a full data breach.

**How to avoid:**
Enable PostgreSQL Row Level Security (RLS) on all tenant-scoped tables. RLS policies act as invisible, mandatory `WHERE tenant_id = current_setting('app.current_tenant_id')` clauses that the database enforces regardless of what the application sends. This is a defense-in-depth backstop — even a buggy query cannot cross tenant boundaries. Set `app.current_tenant_id` at the start of every request via a middleware that pulls it from the authenticated user's JWT claims or session.

**Warning signs:**
- Queries in the codebase using only `WHERE id = $1` on tenant-scoped tables
- No RLS policies in the database schema
- No cross-tenant isolation tests (attempting to access resource from a different tenant's token and expecting 404/403)

**Phase to address:**
Multi-tenant foundation phase. RLS must be configured in the initial database schema migration, before any feature code is written.

---

### Pitfall 6: Flutter SQLite Schema Migration Breaks Existing User Data

**What goes wrong:**
The team adds a new column to the local SQLite schema in an app update. Users who already have the app installed upgrade without re-installing. If the `onUpgrade` migration in `sqflite` is not implemented, the old schema remains and the new code crashes trying to access the missing column. In the worst case, the developer drops and recreates the table (a common shortcut in tutorials) and wipes all locally stored offline data the user hasn't synced yet.

**Why it happens:**
During development, the app is repeatedly uninstalled and reinstalled, which always runs `onCreate`. The `onUpgrade` path is never exercised locally. This creates a false confidence that migrations work.

**How to avoid:**
Treat database migrations as first-class code. Every schema change requires a versioned migration function in `onUpgrade`. Write a migration test that opens a copy of the v1 database, runs the upgrade to v2, and verifies data integrity. Never use `DROP TABLE` in an upgrade migration — use `ALTER TABLE ADD COLUMN` for additive changes. For destructive changes, migrate data to a temp table first.

**Warning signs:**
- `onUpgrade` callback that calls `onCreate` (dropping all tables)
- Database version number never incremented when schema changes
- No migration tests in the test suite

**Phase to address:**
Foundation / data layer phase. The migration discipline must be established with the first schema version, and every subsequent phase that changes the schema must include a migration test.

---

### Pitfall 7: Background Sync Kills Battery / Gets Killed by OS

**What goes wrong:**
The Flutter app registers a periodic background sync task using `workmanager` or a Dart isolate. On Android, Doze mode and battery optimization kill the background process silently — the user never syncs. On iOS, apps are suspended almost immediately after backgrounding without a background fetch registration. The developer tests on a plugged-in device and assumes it works.

**Why it happens:**
Android and iOS both aggressively manage background processes. The behavior differs between manufacturers (Samsung, Xiaomi, and Huawei are notorious for aggressive killing) and OS versions. Tests on simulators and plugged-in devices don't reproduce the real-world behavior.

**How to avoid:**
Use `workmanager` (Android) and Background App Refresh (iOS) with realistic expectations about timing — these are best-effort, not guaranteed. The primary sync trigger should be foreground launch + connectivity restored, not background timer. Add a sync status indicator in the UI so users know when their data is pending. For urgent syncs (e.g., job completion), use a foreground service notification on Android to guarantee execution. Test on physical, battery-restricted, unplugged devices.

**Warning signs:**
- Background sync tested only on plugged-in emulators
- No sync status UI indicator in the app
- Sync relies solely on a periodic timer with no foreground-launch trigger

**Phase to address:**
Offline sync phase. Background sync strategy and its limitations must be designed upfront.

---

### Pitfall 8: Action Queue Not Idempotent — Duplicate Sync Creates Duplicate Records

**What goes wrong:**
The sync engine uploads a "create job" action. The server processes it, creates the job, but the network drops before the 200 response arrives. The sync engine retries the action. The server creates a second job. The contractor now has duplicate jobs in their list. If the contractor has been working offline for hours, the entire queue may be re-submitted on reconnect, creating cascading duplicates.

**Why it happens:**
Retry logic is implemented without idempotency. The developer assumes if a request got no response, the action didn't execute on the server. This assumption is wrong — the server may have fully processed the request before the network dropped.

**How to avoid:**
Every action in the queue must carry a client-generated UUID (idempotency key). The server must store this key and, on duplicate submission, return the original response (200 OK with the existing record) instead of creating a new one. The server-side deduplication table can be short-lived (e.g., 48 hours) — just long enough to cover typical offline windows. On the Flutter side, never delete an action from the queue until the server confirms acceptance.

**Warning signs:**
- Sync actions without a client-generated UUID field
- Server POST endpoints that create new records without deduplication checks
- "Sync" implemented as re-submitting all local records on reconnect

**Phase to address:**
Offline sync phase. Idempotency key design must be established during queue design.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Online-first with "offline later" plan | Faster initial velocity | Full re-architecture required; not incrementally addable | Never — for this project |
| Single shared database user (no RLS) | Simpler connection config | One missed `WHERE` clause = data breach; no defense in depth | Never in production |
| `onUpgrade` drops and recreates tables | Simple migration code | Destroys user's unsynced offline data permanently | Never in production |
| LWW sync without version check | Simple sync implementation | Silent data loss under concurrent multi-device usage | Never for scheduling data |
| Skip idempotency keys in action queue | Faster queue implementation | Duplicate records on every retry during network flakiness | Never |
| Hard-code `tenant_id` checks in app code only | Simpler than RLS setup | Single missed filter = tenant data leak | Only during development, must be replaced before any real data |
| Scheduling check + insert without transaction | Simpler query code | Double-bookings under concurrent dispatcher usage | Never |
| Sync background task via periodic timer only | Simple implementation | Silent failures on Android/iOS power management | Only supplementary; never the sole mechanism |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Flutter + FastAPI REST | Pydantic model changes break Flutter JSON deserialization silently — new required fields cause null crashes | Add `required: false` with defaults for new fields; version the API; use Freezed/json_serializable with unknown field tolerance |
| Flutter sqflite + FastAPI | Using integer timestamps (ms since epoch) on Flutter, ISO strings on Python — comparison bugs in conflict resolution | Standardize on UTC ISO 8601 strings everywhere; parse to `DateTime` on Flutter, `datetime` on Python |
| Flutter connectivity_plus | `connectivity_plus` reports network connectivity (interface UP), not actual internet access — reports "connected" on captive portals and dead WiFi | Use `internet_connection_checker` to verify actual HTTP reachability before triggering sync |
| Celery/background tasks + FastAPI middleware | Middleware sets `tenant_id` via ContextVar scoped to the request; tasks run outside request scope | Serialize `tenant_id` explicitly into every task payload; re-establish context at task start |
| PostgreSQL RLS + SQLAlchemy | SQLAlchemy connection pooling reuses connections; `SET LOCAL app.current_tenant_id` only lasts for a transaction, not the connection | Use `SET LOCAL` inside a transaction, or use `RESET` on connection return to pool; never use `SET` (session-level) with pooled connections |
| Flutter workmanager + Android | Background tasks registered with workmanager are killed on many Android OEM builds (Samsung, Xiaomi, Huawei) | Provide in-app instructions to disable battery optimization for the app; use foreground service for guaranteed critical syncs |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| N+1 queries in contractor schedule view | Schedule page takes 3-10s to load with 10+ contractors | Eager-load job assignments with contractor records; use `select_related`/joined load in SQLAlchemy | 5+ contractors per company |
| Full table scan for availability check | Scheduling becomes slow as job history grows | Index `(contractor_id, start_time, end_time)` on the schedule table from day one | ~500 job records |
| Sync uploading entire local database on reconnect | First sync after long offline period times out or OOMs | Sync only dirty/changed records using `is_dirty` flag or `pending_sync` queue table | After 4+ hours offline with active usage |
| Unindexed `tenant_id` columns | All queries slow as tenant count grows | Add index on `tenant_id` (and composite indexes where `tenant_id` is the leading column) for every tenant-scoped table | ~10 tenants / ~1000 rows |
| Travel time calculation on every scheduling request | Scheduler API latency grows with team size | Cache travel time matrix between job sites; recalculate only when new site added | 10+ contractors, 20+ active job sites |
| Flutter SQLite on main thread | UI jank and ANR (Application Not Responding) dialogs | All database operations in `compute()` or `async` with `drift`'s async API; never sync SQLite on main isolate | Any non-trivial query |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Trusting client-supplied `tenant_id` in requests | Tenant A passes Tenant B's `tenant_id` to access their data | Derive `tenant_id` exclusively from the authenticated JWT/session on the server; never accept it as a request parameter |
| Leaking `tenant_id` in sequential integer IDs | Tenant can enumerate other tenants' resources by incrementing IDs | Use UUIDs (v4) for all externally exposed IDs on tenant-scoped resources |
| Storing sensitive job data (addresses, client contacts) in plaintext SQLite on device | Device theft exposes all client data | Enable SQLite encryption (SQLCipher via `sqflite_sqlcipher` package) for sensitive fields; at minimum, store in Flutter Secure Storage |
| Raw database errors returned in API responses | Stack traces / table names / tenant context exposed to client | Catch all SQLAlchemy/psycopg2 exceptions at the API boundary; return generic error messages; log full errors server-side only |
| Background task results stored without tenant scoping | Cached results from one tenant's task visible to another | Tag all cache keys with `tenant_id` prefix; never store task results in a shared cache namespace |
| JWT without tenant claim | Auth works but tenant resolution requires extra DB lookup on every request, creating a bottleneck and a TOCTOU window | Include `tenant_id` in JWT claims at token issuance |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No sync status indicator | Contractors don't know if their field updates (job completion, photos) have been uploaded — they may retype everything thinking it was lost | Show persistent sync status: "3 items pending sync", "Syncing...", "All synced" with timestamp |
| Blocking UI during sync | App freezes while uploading large photo batch after reconnecting | Sync in background; let user continue working; show non-blocking progress indicator |
| Conflict resolved silently by server overwrite | Dispatcher edits a job; contractor's offline edit wipes it with no warning | Surface conflicts explicitly: "This record was changed on another device. Review the differences." |
| Job status transitions without offline guard | Contractor marks job "Complete" offline, client immediately sees it (cached) — but the actual server state is still "In Progress" for days | Show client a "pending confirmation" state for actions that haven't synced; only promote to definitive state after server acknowledgment |
| Scheduling view not showing travel time gaps | Dispatchers book jobs back-to-back without travel time, creating impossible schedules contractors can't meet | Visually display travel time buffers between jobs in the schedule view |
| Generic "Error" messages during sync failures | Contractors don't know whether to retry, wait, or call the office | Distinguish: "No internet — will retry when connected" vs "Server error — contact support" vs "Data conflict — needs review" |

---

## "Looks Done But Isn't" Checklist

- [ ] **Offline mode:** Works without network on initial launch (not just after first online session) — verify by installing fresh app with airplane mode on
- [ ] **Conflict resolution:** Test two devices editing the same job simultaneously offline — verify neither silently overwrites the other
- [ ] **Schema migration:** Uninstall v1 app, install v1, add data, upgrade to v2 without reinstalling — verify data intact and new columns accessible
- [ ] **Tenant isolation:** Log in as Tenant A, attempt to access Tenant B's job ID in API calls — verify 404 (not 403, which leaks existence)
- [ ] **Double-booking prevention:** Fire two concurrent booking requests for the same contractor at the same time — verify only one succeeds at the database level
- [ ] **Background task tenant context:** Trigger a notification background task — verify it only sends to the correct tenant's clients
- [ ] **Idempotent sync:** Submit the same action queue entry twice — verify server returns the original result, not a duplicate record
- [ ] **Battery-restricted sync:** Test background sync on a real Android device with battery optimization enabled for the app — verify sync still occurs on foreground return
- [ ] **Large offline session:** Go offline, create 50 records, reconnect — verify all 50 sync without timeout, crash, or duplicates
- [ ] **Multi-day job display:** Create a job spanning 3 days — verify it appears correctly on all 3 days in schedule view, not just the start day

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Online-first retrofitted to offline | HIGH | Rebuild data layer with local-first architecture; migrate UI state management; ~2-4 week rewrite |
| Silent data overwrite discovered in production | HIGH | Audit sync logs for affected records; restore from DB backups; add version check to all sync endpoints; notify affected tenants |
| Tenant data leak discovered | CRITICAL | Immediate: rotate all API keys/tokens, audit access logs, notify affected tenants; legal/compliance review; add RLS retroactively |
| Double-booking in production | MEDIUM | Detect conflicts via reporting query; notify affected contractors; add pessimistic locking to scheduling transactions |
| SQLite migration data loss | MEDIUM | If pre-synced: restore from server; if not synced yet: data is gone — cannot recover; add migration tests going forward |
| Action queue creating duplicates | MEDIUM | Write a deduplication script to identify and merge duplicate records; add idempotency keys to queue and server |
| Background sync silently failing | LOW | Add sync status telemetry (anonymous, opt-in); prompt users to disable battery optimization in onboarding |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Offline-first not architected from start | Phase 1: Foundation | Local DB exists before any API call; no direct API-to-UI bindings |
| Silent data overwrite (no versioning) | Phase 1: Foundation (schema) + Phase 2: Sync | Every entity has `version`/`updated_at`; sync endpoint rejects stale writes in tests |
| Missing tenant context in background tasks | Phase 1: Multi-tenant foundation | Background task test asserts correct tenant scoping; cross-tenant notification test |
| Scheduling race condition / double-booking | Phase 3: Scheduling engine | Concurrent request load test proves only one booking created |
| Missing WHERE clause / tenant data leak | Phase 1: Multi-tenant foundation | RLS enabled in schema migration; cross-tenant API tests in CI |
| SQLite migration breaks existing data | Every schema-change phase | Migration test opens old DB version, upgrades, verifies data integrity |
| Background sync killed by OS | Phase 2: Sync engine | Physical device test with battery optimization enabled |
| Action queue not idempotent | Phase 2: Sync engine | Duplicate submission test returns original record, not duplicate |
| Noisy neighbor performance degradation | Phase 4: Scale hardening | Per-tenant query time monitored; RLS indexes verified in DB plan |
| Travel time not in scheduling UI | Phase 3: Scheduling engine | Dispatcher schedule view shows buffer zones between jobs |

---

## Sources

- AppMaster: Offline-First Background Sync — Conflicts, Retries, UX (https://appmaster.io/blog/offline-first-background-sync-conflict-retries-ux)
- Android Developers: Build an Offline-First App (https://developer.android.com/topic/architecture/data-layer/offline-first)
- Flutter Official Docs: Offline-First Support (https://docs.flutter.dev/app-architecture/design-patterns/offline-first)
- DEV Community: Offline-First Architecture in Flutter Parts 1 & 2 (https://dev.to/anurag_dev/implementing-offline-first-architecture-in-flutter-part-1-local-storage-with-conflict-resolution-4mdl)
- Sachith Dassanayake: Offline Sync & Conflict Resolution Patterns (Feb 2026) (https://www.sachith.co.uk/offline-sync-conflict-resolution-patterns-architecture-trade%E2%80%91offs-practical-guide-feb-19-2026/)
- DZone: Conflict Resolution — LWW vs CRDTs (https://dzone.com/articles/conflict-resolution-using-last-write-wins-vs-crdts)
- AWS: Multi-Tenant Data Isolation with PostgreSQL RLS (https://aws.amazon.com/blogs/database/multi-tenant-data-isolation-with-postgresql-row-level-security/)
- permit.io: Postgres RLS Implementation Guide — Best Practices and Common Pitfalls (https://www.permit.io/blog/postgres-rls-implementation-guide)
- Medium: Multi-Tenant Architecture with FastAPI — Design Patterns and Pitfalls (https://medium.com/@koushiksathish3/multi-tenant-architecture-with-fastapi-design-patterns-and-pitfalls-aa3f9e75bf8c)
- HackerNoon: How to Solve Race Conditions in a Booking System (https://hackernoon.com/how-to-solve-race-conditions-in-a-booking-system)
- Medium: Flutter SQLite Common Mistakes (https://medium.com/@sparkleo/common-sqlite-mistakes-flutter-devs-make-and-how-to-avoid-them-1102ab0117d5)
- Medium: Background Sync Issue in Flutter — Debugging (https://dev.to/linwood_matthews_221/debugging-nightmare-fixing-a-background-sync-issue-in-flutter-15nl)
- Medium: Flutter Background Tasks Struggles (https://medium.com/@fourstrokesdigital/why-flutter-apps-struggle-with-background-tasks-18918f1b1b98)
- Neon: The Noisy Neighbor Problem in Multitenant Architectures (https://neon.com/blog/noisy-neighbor-multitenant)
- Security Boulevard: Tenant Isolation in Multi-Tenant Systems (https://securityboulevard.com/2025/12/tenant-isolation-in-multi-tenant-systems-architecture-identity-and-security/)

---
*Pitfalls research for: Offline-first multi-tenant contractor management SaaS (Flutter + FastAPI)*
*Researched: 2026-03-04*
