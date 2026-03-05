# Phase 2: Offline Sync Engine - Context

**Gathered:** 2026-03-05
**Status:** Ready for planning

<domain>
## Phase Boundary

The Flutter app stores all data locally first (Drift SQLite) and reliably synchronizes to the FastAPI backend when connectivity is available. No data loss, no duplication, predictable conflict resolution. Covers: sync queue (outbox), sync engine service, backend delta sync endpoint, background sync, sync status UI, and conflict resolution tests.

Requirements: INFRA-03, INFRA-04

</domain>

<decisions>
## Implementation Decisions

### Conflict Resolution
- Server always wins on all entity types — uniform strategy, no per-entity exceptions
- Silent overwrite — no notification to user when server version replaces local changes
- Client UUID idempotency key for create deduplication — server returns existing record if same UUID pushed twice
- Server-wins regardless of version number — no optimistic locking / no 409 Conflict responses
- Version number still incremented on every server write for audit trail and change detection
- Multi-device conflicts treated same as cross-user — server wins, no special case for same user on multiple devices

### Sync Failure & Retry
- Exponential backoff: 1s → 2s → 4s → 8s → 16s, max 5 retries per attempt cycle
- After max retries exhausted: item stays in queue, retries from scratch on next connectivity change
- 4xx errors (validation/bad data): park immediately, don't retry — retrying won't help
- 5xx errors and timeouts: standard retry with backoff
- FIFO queue ordering — items sync in creation order, respects causality

### Sync Status Indicator
- App bar subtitle: "All synced" / "3 items pending" / "Syncing 2 of 5..." / "Offline"
- Count + state detail level — enough to know what's happening without noise
- Always visible — "All synced" stays on screen, does not fade
- Offline transition: subtitle changes to "Offline" with subtle icon only — no toast, no banner
- No "last synced" timestamp shown — subtitle is sufficient

### Background Sync Triggers
- Foreground: immediate sync on every local write when online; queue when offline; drain queue on connectivity restore
- Background: periodic WorkManager sync every 15 minutes (Android minimum)
- Pull-to-refresh available on Home, Jobs, Schedule screens as manual trigger
- Cursor-based delta sync: GET /sync?cursor=<last_timestamp> returns all changed entities since cursor

### Sync Scope & Entity Types
- Phase 2 syncs companies, users, roles only — entities that exist from Phase 1
- Registry pattern for sync engine — each entity type registers its serializer, endpoint, and conflict strategy; future phases just add entries
- Bidirectional from the start — push local changes AND pull server changes
- Single delta endpoint returns all changed entity types in one response; client sorts by type locally
- Individual requests per queue item (not batched) — simpler error handling, per-item status tracking

### Data Freshness
- No "last synced" timestamp shown to user
- Show cached data immediately on app open, sync in background — UI updates reactively via Drift streams when new data arrives
- No loading spinner on app open

### Offline Data Limits
- No queue limit — contractor working offline for a week should never lose data
- Only current user's company data cached locally — aligns with RLS tenant isolation

### Soft Delete & Tombstones
- Soft delete with deleted_at timestamp — sync tombstone to other devices
- Enables undo, audit trail, and delete propagation across devices

### Sync Queue Persistence
- Queue stored as a Drift table (SQLite) — survives app kills, reboots, updates
- If killed mid-upload: item stays as "pending", re-sent on restart — idempotency key handles server-side dedup
- No special "in-flight" state needed

### Version Tracking
- Version incremented on every server write
- Server-wins regardless of version mismatch — version is for audit, not locking

### First Launch
- Full company dataset downloaded on first sync — typical contractor company (5-50 people) is small
- App works fully offline from first launch onward

### Testing Strategy
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

</decisions>

<specifics>
## Specific Ideas

- Sync should feel invisible — contractors shouldn't think about syncing, it just works
- The app must feel instant: show cached data, never block on network
- Queue must never lose data, even if the phone dies mid-sync
- Registry pattern so adding new entity types in Phase 3+ is a one-file change, not a refactor

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- Drift AppDatabase with Companies, Users, UserRoles tables — sync writes target these
- CompanyDao and UserDao with Stream-based reads — UI already reacts to local DB changes
- DioClient singleton via getIt — add retry interceptor for sync
- UUID client-generated PKs — natural idempotency keys for sync dedup

### Established Patterns
- Stream-based Riverpod providers (companiesProvider, companyUsersProvider) — sync writes to Drift, UI reacts automatically
- getIt service locator — register SyncEngine, ConnectivityService
- TenantMiddleware + X-Company-Id header — sync requests must include tenant header
- Feature-first directory structure — sync lives in mobile/lib/core/sync/ or mobile/lib/features/sync/

### Integration Points
- Drift tables need: sync_queue table (outbox), deleted_at column on existing tables, sync_cursor metadata table
- DioClient needs: retry interceptor, idempotency key header
- Backend needs: GET /api/v1/sync delta endpoint, idempotent mutation support (UUID dedup)
- service_locator.dart: register SyncEngine and ConnectivityService
- AppShell app bar: add sync status subtitle from syncStatusProvider
- Main screens (Home, Jobs, Schedule): add pull-to-refresh triggering sync

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-offline-sync-engine*
*Context gathered: 2026-03-05*
