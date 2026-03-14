# Phase 9: Sync Engine Gap Closure - Research

**Researched:** 2026-03-14
**Domain:** Flutter offline sync engine — Dart/Drift/SyncEngine + FastAPI backend sync endpoint
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Entity processing order**
- Process in FK dependency order: companies → users → user_roles → jobs → bookings/job_sites/job_notes/time_entries/attachments/client_profiles/job_requests → quotes → quote_line_items → invoices → invoice_line_items
- Guarantees parent rows exist before children are inserted
- Per-type commits (not all-or-nothing transaction) — each entity type is processed and committed independently

**pullDelta() refactor to loop**
- Refactor from copy-paste blocks to a loop over a list of (responseKey, handlerName) tuples in dependency order
- Eliminates 14+ explicit blocks, makes adding future entity types trivial, centralizes error handling and logging

**Line item handling**
- quote_line_items and invoice_line_items are separate entity types with their own handlers and processing in pullDelta()
- Server returns them as flat top-level arrays (not nested in parent objects)
- Each line item has its own FK (quote_id / invoice_id)

**Pull failure handling**
- Individual entity failures: wrap each applyPulled() call in try/catch, skip and continue on failure
- No retry — skip on first failure; next pullDelta() cycle re-delivers the entity since cursor updates are idempotent
- Errors logged via debugPrint only (entity type + ID), not surfaced to user via sync status
- Top-level DioException handling unchanged — network failures remain non-fatal and silent
- Unknown entity type keys in response: debugPrint warning for forward-compatibility awareness

**Cursor behavior**
- Update cursor (server_timestamp) after all types are attempted, even if some failed
- Failed types get re-delivered on next pull since server includes all changes since cursor

**Logging**
- Per-type entity count via debugPrint after processing each type
- Aggregate summary after all types processed: "pullDelta: N pulled, M skipped, T types processed"
- Debug-only — no-op in release builds per existing convention

**JobSyncHandler field mapping**
- Add 5 missing fields to applyPulled(): gpsLatitude, gpsLongitude, gpsAddress, quoteId, invoiceId
- Server always wins: null values from server overwrite existing local values (consistent with existing applyPulled() pattern)

**Sync scope**
- Client processes everything the server sends — no client-side role filtering
- Server-side RLS and role filtering is the authority
- Backend returns empty arrays for entity types filtered by role (consistent shape, no null checks needed)

**Backend endpoint**
- Extend existing /api/v1/sync endpoint with 7 new entity type arrays
- Backwards-compatible: new keys default to empty arrays
- No v2 endpoint needed

### Claude's Discretion
- Exact handler implementations for new entity types (follow existing handler patterns)
- Test structure and assertion specifics
- Any necessary Drift migration details for missing columns

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INFRA-04 | Background sync engine with conflict resolution | pullDelta() loop refactor + per-entity try/catch = complete conflict-skip strategy; server-wins on all fields |
| SCHED-03 | Drag-and-drop calendar scheduling with color coding | Bookings sync via BookingSyncHandler already implemented; pullDelta() must call it — gap closure wires booking cross-device propagation |
| FIELD-02 | GPS-based address capture for property locations | gpsLatitude, gpsLongitude, gpsAddress missing from JobSyncHandler.applyPulled() — fields exist in Drift schema (v5 migration) but are not mapped from server response |
| BIZ-01 | Digital quoting/estimates with line items | QuoteSyncHandler + QuoteLineItemSyncHandler (new) must be wired into pullDelta(); quote_line_items arrive as flat top-level arrays |
| BIZ-03 | Digital invoicing generated from completed jobs | InvoiceSyncHandler + InvoiceLineItemSyncHandler (new) must be wired into pullDelta(); invoice_line_items arrive as flat top-level arrays |
</phase_requirements>

---

## Summary

Phase 9 is **pure gap closure** — the backend sync endpoint already returns all 14 entity types (confirmed in `backend/app/features/sync/router.py` and `service.py`). The Drift schema already has all required tables and columns (schema v6 includes quotes, quote_line_items, invoices, invoice_line_items; schema v5 added gpsLatitude/gpsLongitude/gpsAddress to jobs). All 12 sync handler files already exist on disk. The SyncRegistry in `service_locator.dart` already registers 12 handlers. The gap is that `pullDelta()` in `sync_engine.dart` only processes 7 entity types via copy-paste blocks, leaving 7 handlers registered but never invoked during pull.

The two distinct work items are: (1) **Refactor pullDelta()** from 7 copy-paste blocks into a loop over `(responseKey, handlerType)` tuples covering all 14 entity types, with per-entity try/catch and logging. (2) **Fix JobSyncHandler.applyPulled()** to map the 5 missing fields (gpsLatitude, gpsLongitude, gpsAddress, quoteId, invoiceId) that exist in the Drift Jobs table schema but are absent from the companion construction.

Additionally, two new handlers must be created for line items — **QuoteLineItemSyncHandler** and **InvoiceLineItemSyncHandler** — since these are flat top-level arrays in the server response (not nested inside their parent handlers), and no handler file exists for them yet. Both QuoteSyncHandler and InvoiceSyncHandler currently delegate to `upsertFromSync()` on the DAO, implying they handle parent+children together when called via quote/invoice pull. The CONTEXT.md decision states line items are separate entity types in pullDelta(), so new handlers are needed.

**Primary recommendation:** Refactor pullDelta() into a loop, fix JobSyncHandler, create two line item handlers, register them in the service locator, then write E2E tests proving cross-device propagation for bookings and quotes/invoices.

---

## Standard Stack

### Core (Already In Place — No New Dependencies)

| Component | Version | Purpose | Status |
|-----------|---------|---------|--------|
| Drift | 2.32 | Local SQLite ORM for Flutter | Already integrated |
| Riverpod | 3.2 | State management | Already integrated |
| Dio | (existing) | HTTP client for sync requests | Already integrated |
| FastAPI | 0.115.12 | Backend sync endpoint | Already complete |
| SQLAlchemy 2.0 async | (existing) | Backend ORM | Already complete |

No new packages are needed. This phase is entirely mechanical — wiring existing handlers into existing infrastructure.

---

## Architecture Patterns

### Existing pullDelta() Pattern (7 types — to be replaced)

The current implementation in `sync_engine.dart` (lines 296–387) uses explicit copy-paste blocks:

```dart
// CURRENT PATTERN (to be replaced with loop):
final List<dynamic>? companies = data['companies'] as List<dynamic>?;
if (companies != null) {
  final handler = _registry.getHandler('company');
  for (final entity in companies) {
    await handler.applyPulled(entity as Map<String, dynamic>);
  }
}
// ... 6 more identical blocks for users, user_roles, jobs, job_notes,
//     time_entries, attachments
```

### Target pullDelta() Pattern (loop over 14 types)

```dart
// Source: CONTEXT.md locked decision — loop with (responseKey, handlerType) tuples
// Dependency order: companies → users → user_roles → jobs →
//   bookings/job_sites/job_notes/time_entries/attachments/client_profiles/job_requests →
//   quotes → quote_line_items → invoices → invoice_line_items

const entityTypes = [
  ('companies', 'company'),
  ('users', 'user'),
  ('user_roles', 'user_role'),
  ('jobs', 'job'),
  ('bookings', 'booking'),
  ('job_sites', 'job_site'),
  ('job_notes', 'job_note'),
  ('time_entries', 'time_entry'),
  ('attachments', 'attachment'),
  ('client_profiles', 'client_profile'),
  ('job_requests', 'job_request'),
  ('quotes', 'quote'),
  ('quote_line_items', 'quote_line_item'),
  ('invoices', 'invoice'),
  ('invoice_line_items', 'invoice_line_item'),
];

int totalPulled = 0;
int totalSkipped = 0;

for (final (responseKey, handlerType) in entityTypes) {
  final entities = data[responseKey] as List<dynamic>?;
  if (entities == null) {
    debugPrint('pullDelta: unknown key "$responseKey" in response (forward-compat)');
    continue;
  }
  int typePulled = 0;
  int typeSkipped = 0;
  try {
    final handler = _registry.getHandler(handlerType);
    for (final entity in entities) {
      try {
        await handler.applyPulled(entity as Map<String, dynamic>);
        typePulled++;
      } catch (e) {
        typeSkipped++;
        final id = (entity as Map<String, dynamic>)['id'] ?? 'unknown';
        debugPrint('pullDelta: skip $handlerType $id — $e');
      }
    }
  } catch (e) {
    // Handler not registered — skip entire type
    debugPrint('pullDelta: no handler for "$handlerType" — $e');
  }
  debugPrint('pullDelta: $handlerType — $typePulled pulled, $typeSkipped skipped');
  totalPulled += typePulled;
  totalSkipped += typeSkipped;
}

debugPrint('pullDelta: $totalPulled pulled, $totalSkipped skipped, ${entityTypes.length} types processed');
```

### JobSyncHandler.applyPulled() Fix Pattern

The 5 missing fields must be added to the `JobsCompanion` construction in `job_sync_handler.dart`. Current implementation (lines 68–116) is missing:

```dart
// ADD THESE to the existing JobsCompanion(...) construction:
gpsLatitude: Value(data['gps_latitude'] != null
    ? (data['gps_latitude'] as num).toDouble()
    : null),
gpsLongitude: Value(data['gps_longitude'] != null
    ? (data['gps_longitude'] as num).toDouble()
    : null),
gpsAddress: Value(data['gps_address'] as String?),
quoteId: Value(data['quote_id'] as String?),
invoiceId: Value(data['invoice_id'] as String?),
```

Pattern note: `gpsLatitude`/`gpsLongitude` are `RealColumn` (nullable real/double) in Drift. Server sends them as JSON numbers. Use `(data['gps_latitude'] as num).toDouble()` — same pattern as `JobSiteSyncHandler` uses for `lat`/`lng`. `quoteId`/`invoiceId` are `TextColumn` (nullable string) — direct cast `as String?`.

### New Handler Pattern — QuoteLineItemSyncHandler

Quote and Invoice handlers currently use `_db.quoteDao.upsertFromSync(data)` and `_db.invoiceDao.upsertFromSync(data)` for pull — these handle parent+children together via DAO. But CONTEXT.md specifies that `quote_line_items` and `invoice_line_items` are separate entries in the pullDelta loop. This means:

**Option A (delegate to DAO):** QuoteLineItemSyncHandler calls `_db.quoteDao.upsertLineItemFromSync(data)` — keeps all Drift logic in DAO layer.

**Option B (inline Companion):** QuoteLineItemSyncHandler constructs `QuoteLineItemsCompanion` directly and calls `insertOnConflictUpdate`.

Per Claude's Discretion, follow the existing handler pattern. Most handlers use the inline Companion approach. QuoteDao.upsertFromSync handles nested line items — the new handler should handle a FLAT line item (one at a time), consistent with how all other handlers work.

```dart
// Source: established pattern from booking_sync_handler.dart, job_sync_handler.dart
class QuoteLineItemSyncHandler extends SyncHandler {
  final AppDatabase _db;
  QuoteLineItemSyncHandler(this._db);

  @override
  String get entityType => 'quote_line_item';

  @override
  Future<void> push(SyncQueueData item) async {
    // Line items are not pushed independently — mutations go through the quote handler
    throw StateError('QuoteLineItemSyncHandler: push not supported');
  }

  @override
  Future<void> applyPulled(Map<String, dynamic> data) async {
    final companion = QuoteLineItemsCompanion(
      id: Value(data['id'] as String),
      quoteId: Value(data['quote_id'] as String),
      // ... map remaining fields from QuoteLineItems table schema
      deletedAt: Value(data['deleted_at'] != null
          ? DateTime.parse(data['deleted_at'] as String)
          : null),
    );
    await _db.into(_db.quoteLineItems).insertOnConflictUpdate(companion);
  }
}
```

InvoiceLineItemSyncHandler follows the identical pattern.

### Handler Registration in service_locator.dart

Two new handlers added after the existing registrations:

```dart
// After existing Phase 8 registrations:
registry.register(QuoteLineItemSyncHandler(db));      // pull-only
registry.register(InvoiceLineItemSyncHandler(db));    // pull-only
```

---

## What Already Exists (HIGH confidence — verified by reading source)

| Component | Status | File |
|-----------|--------|------|
| Backend sync endpoint returns all 14 entity types | COMPLETE | `backend/app/features/sync/router.py` |
| Backend SyncService has all 14 query methods | COMPLETE | `backend/app/features/sync/service.py` |
| SyncResponse schema has all 14 keys with defaults | COMPLETE | `backend/app/features/sync/schemas.py` |
| Drift schema v6 has all 14 tables | COMPLETE | `mobile/lib/core/database/app_database.dart` |
| jobs table has gpsLatitude, gpsLongitude, gpsAddress | COMPLETE | `mobile/lib/core/database/tables/jobs.dart` (v5) |
| jobs table has quoteId, invoiceId | COMPLETE | `mobile/lib/core/database/tables/jobs.dart` (v6) |
| BookingSyncHandler file | COMPLETE | `mobile/lib/features/schedule/data/booking_sync_handler.dart` |
| JobSiteSyncHandler file | COMPLETE | `mobile/lib/features/schedule/data/job_site_sync_handler.dart` |
| ClientProfileSyncHandler file | COMPLETE | `mobile/lib/features/jobs/data/client_profile_sync_handler.dart` |
| JobRequestSyncHandler file | COMPLETE | `mobile/lib/features/jobs/data/job_request_sync_handler.dart` |
| QuoteSyncHandler file | COMPLETE | `mobile/lib/features/quotes/data/quote_sync_handler.dart` |
| InvoiceSyncHandler file | COMPLETE | `mobile/lib/features/invoices/data/invoice_sync_handler.dart` |
| SyncRegistry registers all 12 handlers | COMPLETE | `mobile/lib/core/di/service_locator.dart` |

| Component | Status | Action Needed |
|-----------|--------|---------------|
| pullDelta() processes 7 types only | GAP | Refactor to loop covering 14 types |
| JobSyncHandler missing 5 fields | GAP | Add gpsLatitude/Longitude/Address, quoteId, invoiceId |
| QuoteLineItemSyncHandler | MISSING | Create new handler file |
| InvoiceLineItemSyncHandler | MISSING | Create new handler file |
| Registry registration for 2 new handlers | MISSING | Add to service_locator.dart |

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Upsert idempotency | Custom duplicate-checking logic | `insertOnConflictUpdate()` (Drift) | Already used by all 12 existing handlers — guaranteed atomic upsert |
| Tombstone detection | Custom deleted flag logic | `Value(deletedAt)` in Companion with nullable `deleted_at` from server | All handlers already use this pattern |
| FK dependency ordering | Runtime dependency graph | Hard-coded tuple list in correct order | Dependencies are static and known; a runtime graph adds complexity without benefit |
| Handler lookup | If/else chain | `_registry.getHandler(handlerType)` | SyncRegistry already handles this; throwing StateError on unknown type is intentional |
| Per-entity error isolation | Transaction rollback / poison pill | Per-entity try/catch with continue | Matches CONTEXT.md decision exactly |

---

## Common Pitfalls

### Pitfall 1: QuoteSyncHandler.applyPulled double-writes line items
**What goes wrong:** `QuoteSyncHandler.applyPulled()` calls `_db.quoteDao.upsertFromSync(data)`, which may already write nested line items from the parent quote payload. If pullDelta() ALSO calls `QuoteLineItemSyncHandler.applyPulled()` for the same line items, they get written twice (idempotent, so no data corruption, but wasted work).
**Why it happens:** The existing QuoteSyncHandler was designed to handle parent+children in one shot. Now line items have their own separate sync entries.
**How to avoid:** Verify `QuoteDao.upsertFromSync()` behavior. If it writes line items from nested data in the quote payload, the flat `quote_line_items` array entries are additive/idempotent. The double-write is safe. Alternatively, have QuoteDao.upsertFromSync skip nested line items if empty, and rely on the separate handler. Either is acceptable since insertOnConflictUpdate is idempotent.
**Warning signs:** Line item count discrepancy in tests.

### Pitfall 2: Numeric type mismatch on GPS fields
**What goes wrong:** `gps_latitude` comes from the server as a JSON number (Python `float`), but Dart decodes it as `num` — not `double`. Direct `as double` cast throws a runtime type error.
**Why it happens:** Dart's JSON decoder produces `int` for whole numbers and `double` for decimals. `0.0` is `double`, but `0` would be `int`.
**How to avoid:** Always use `(data['gps_latitude'] as num).toDouble()` — same pattern as `JobSiteSyncHandler` uses for `lat`/`lng` (verified in source). Never use bare `as double`.

### Pitfall 3: Missing tuple entry causes silent skip
**What goes wrong:** If a new entity type is added to the loop tuples but the handler is not registered in the SyncRegistry, `_registry.getHandler()` throws `StateError`. The outer try/catch for handler lookup logs and skips. This is correct behavior but can mask forgotten registrations during development.
**Why it happens:** The loop and the registry are separate — no compile-time enforcement.
**How to avoid:** Write E2E tests that verify each of the 14 entity types appears in local Drift DB after a mock pullDelta response. Verify 14 handler registrations in `setupServiceLocator`.

### Pitfall 4: Attachment upload fires before all 14 types are processed
**What goes wrong:** The existing `pullDelta()` fires `_attachmentUploadService!.uploadPending()` between the entity processing and the cursor update (lines 374–377). The refactored loop must preserve this ordering: all 14 entity types → attachment upload → cursor update.
**Why it happens:** Copying the loop structure without checking what comes after it.
**How to avoid:** Keep `uploadPending()` call and cursor update in the same position relative to the new loop — after entity processing, before cursor save.

### Pitfall 5: Server response key naming vs handler type naming
**What goes wrong:** The server uses snake_case keys (`job_notes`, `time_entries`, `quote_line_items`) while handlers use singular forms (`job_note`, `time_entry`, `quote_line_item`). If a tuple maps the wrong pair, `getHandler()` throws StateError.
**Why it happens:** The mapping is manual — no type-safe contract between server key and handler entityType.
**How to avoid:** Cross-verify each `(responseKey, handlerType)` tuple against: (a) the SyncResponse schema in `backend/app/features/sync/schemas.py`, (b) each handler's `get entityType` getter.

**Verified tuple mapping:**

| Server Response Key | Handler entityType | Handler File |
|--------------------|--------------------|-------------|
| `companies` | `company` | company_sync_handler.dart |
| `users` | `user` | user_sync_handler.dart |
| `user_roles` | `user_role` | user_role_sync_handler.dart |
| `jobs` | `job` | job_sync_handler.dart |
| `bookings` | `booking` | booking_sync_handler.dart |
| `job_sites` | `job_site` | job_site_sync_handler.dart |
| `job_notes` | `job_note` | note_sync_handler.dart |
| `time_entries` | `time_entry` | time_entry_sync_handler.dart |
| `attachments` | `attachment` | (core/sync/handlers/attachment?) |
| `client_profiles` | `client_profile` | client_profile_sync_handler.dart |
| `job_requests` | `job_request` | job_request_sync_handler.dart |
| `quotes` | `quote` | quote_sync_handler.dart |
| `quote_line_items` | `quote_line_item` | **NEW** |
| `invoices` | `invoice` | invoice_sync_handler.dart |
| `invoice_line_items` | `invoice_line_item` | **NEW** |

Note: The attachment handler file path needs verification — `NoteSyncHandler` is in `core/sync/handlers/` but attachment handler may be elsewhere. Confirm before writing the tuple.

---

## Code Examples

### Verified: insertOnConflictUpdate upsert pattern (all existing handlers)
```dart
// Source: booking_sync_handler.dart, job_sync_handler.dart, note_sync_handler.dart
await _db.into(_db.bookings).insertOnConflictUpdate(companion);
```

### Verified: Nullable datetime parse pattern
```dart
// Source: all existing handlers
final deletedAt = data['deleted_at'] != null
    ? DateTime.parse(data['deleted_at'] as String)
    : null;
// ...
deletedAt: Value(deletedAt),
```

### Verified: Nullable numeric field pattern (from JobSiteSyncHandler)
```dart
// Source: job_site_sync_handler.dart lines 41-42
final lat = data['lat'] is num ? (data['lat'] as num).toDouble() : null;
final lng = data['lng'] is num ? (data['lng'] as num).toDouble() : null;
```

### Verified: Pull-only handler push() pattern
```dart
// Source: job_site_sync_handler.dart lines 25-30
@override
Future<void> push(SyncQueueData item) async {
  throw StateError(
    'JobSiteSyncHandler: push is not supported. '
    'Job sites are read-only on mobile — they are created by admin via backend geocoding.',
  );
}
```

### Verified: Backend SyncResponse all 14 keys with defaults
```python
# Source: backend/app/features/sync/schemas.py
class SyncResponse(BaseModel):
    companies: list[CompanyResponse]
    users: list[UserResponse]
    user_roles: list[UserRoleResponse]
    jobs: list[JobResponse] = []
    client_profiles: list[ClientProfileResponse] = []
    job_requests: list[JobRequestResponse] = []
    bookings: list[BookingResponse] = []
    job_sites: list[JobSiteResponse] = []
    job_notes: list[JobNoteResponse] = []
    time_entries: list[TimeEntryResponse] = []
    attachments: list[AttachmentResponse] = []
    quotes: list[QuoteResponse] = []
    quote_line_items: list[QuoteLineItemResponse] = []
    invoices: list[InvoiceResponse] = []
    invoice_line_items: list[InvoiceLineItemResponse] = []
    server_timestamp: str
```

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Flutter Framework | flutter_test + mocktail |
| Backend Framework | pytest + httpx AsyncClient |
| Flutter test config | `mobile/` directory, `flutter test` |
| Flutter quick run | `flutter test test/e2e/phase_9_sync_gap_closure_e2e_test.dart` |
| Flutter full suite | `flutter test test/` |
| Backend quick run | `uv run python -m pytest backend/tests/integration/test_phase_9_sync_e2e.py -x` |
| Backend full suite | `uv run python -m pytest backend/tests/` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFRA-04 | pullDelta() processes all 14 entity types | unit | `flutter test test/e2e/phase_9_sync_gap_closure_e2e_test.dart` | ❌ Wave 0 |
| INFRA-04 | Per-entity try/catch skips on failure without aborting | unit | same | ❌ Wave 0 |
| INFRA-04 | Cursor updated after all types attempted | unit | same | ❌ Wave 0 |
| FIELD-02 | gpsLatitude/Longitude/Address mapped from server to Drift | unit | same | ❌ Wave 0 |
| BIZ-01 | quoteId/invoiceId mapped from server to Drift Jobs | unit | same | ❌ Wave 0 |
| BIZ-01 | Quote created on device A appears on device B after delta pull | integration | same | ❌ Wave 0 |
| BIZ-03 | Invoice created on device A appears on device B after delta pull | integration | same | ❌ Wave 0 |
| SCHED-03 | Booking created on device A appears on device B after delta pull | integration | same | ❌ Wave 0 |
| INFRA-04 | Backend endpoint returns 14 entity type keys | backend integration | `uv run python -m pytest backend/tests/integration/test_phase_9_sync_e2e.py -x` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test test/e2e/phase_9_sync_gap_closure_e2e_test.dart`
- **Per wave merge:** `flutter test test/` and `uv run python -m pytest backend/tests/integration/`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `mobile/test/e2e/phase_9_sync_gap_closure_e2e_test.dart` — covers all INFRA-04, FIELD-02, BIZ-01, BIZ-03, SCHED-03 behaviors
- [ ] `backend/tests/integration/test_phase_9_sync_e2e.py` — backend endpoint verification (14 keys present, line items returned as flat arrays)

*(Backend integration test can leverage existing conftest.py fixtures: `tenant_a_client`, `seed_two_tenants`)*

### Flutter E2E Test Strategy
Use the established Phase 2 pattern (`phase_2_offline_sync_e2e_test.dart`):
- Real Drift in-memory DB: `AppDatabase(NativeDatabase.memory())`
- Mock DioClient returning crafted pullDelta response with all 14 entity arrays
- Mock SyncRegistry uses the real registry wired with real handlers against in-memory DB
- Assert each entity type appears in corresponding Drift table after `pullDelta()`
- Assert cursor is updated after all types processed
- Assert failure in one entity does not prevent other entities from processing
- Do NOT use `pumpAndSettle()` — not needed for non-widget sync engine tests

---

## Open Questions

1. **Attachment handler entityType string**
   - What we know: `NoteSyncHandler` has `entityType => 'job_note'`. An attachment handler must exist since `AttachmentSyncHandler` is referenced in `service_locator.dart` imports (not directly visible in the service_locator.dart we read, but service_locator.dart registers 12 handlers including one for 'attachment').
   - What's unclear: The exact file path and entityType string — verify against `_registry.getHandler('attachment')` call in current pullDelta().
   - Recommendation: Read `mobile/lib/core/sync/handlers/` directory — the attachment handler may be there, or in `features/jobs/data/`. Current pullDelta() at line 363 uses `_registry.getHandler('attachment')` confirming the entityType is `'attachment'`.

2. **QuoteDao.upsertFromSync nested line item behavior**
   - What we know: `QuoteSyncHandler.applyPulled()` calls `_db.quoteDao.upsertFromSync(data)`. The quote server payload includes nested `line_items`. The new `quote_line_items` top-level array is separate.
   - What's unclear: Whether `upsertFromSync` writes nested line items and whether this conflicts with the new flat handler.
   - Recommendation: Read `QuoteDao.upsertFromSync()` before implementing. If it writes nested line items, double-write via flat handler is idempotent and safe. If it doesn't write them, the flat handler is the only path.

---

## Sources

### Primary (HIGH confidence)
- Direct source read: `mobile/lib/core/sync/sync_engine.dart` — current pullDelta() implementation, all 7 existing entity blocks
- Direct source read: `mobile/lib/core/di/service_locator.dart` — 12 registered handlers confirmed
- Direct source read: `mobile/lib/core/database/app_database.dart` — schema v6 confirmed, all tables present
- Direct source read: `mobile/lib/core/database/tables/jobs.dart` — GPS + quote/invoice FK columns confirmed in schema
- Direct source read: `mobile/lib/features/jobs/data/job_sync_handler.dart` — 5 missing fields confirmed absent from applyPulled()
- Direct source read: `backend/app/features/sync/router.py` — all 14 entity types already in endpoint
- Direct source read: `backend/app/features/sync/service.py` — all 14 query methods confirmed
- Direct source read: `backend/app/features/sync/schemas.py` — SyncResponse schema with all 14 keys confirmed
- Direct source read: `mobile/lib/features/schedule/data/booking_sync_handler.dart` — handler complete
- Direct source read: `mobile/lib/features/quotes/data/quote_sync_handler.dart` — handler complete
- Direct source read: `mobile/lib/features/invoices/data/invoice_sync_handler.dart` — handler complete

### Secondary (MEDIUM confidence)
- Inference from QuoteSyncHandler pattern: line item handlers should use pull-only push() (same as JobSiteSyncHandler) since line items are not independently mutated from mobile
- Inference from existing test pattern: `phase_2_offline_sync_e2e_test.dart` pattern applies directly to phase 9 tests

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all verified in source
- Architecture (pullDelta refactor): HIGH — exact current code read; target pattern specified in CONTEXT.md
- JobSyncHandler fix: HIGH — gap confirmed by reading source; fix pattern verified from JobSiteSyncHandler
- New handlers (QuoteLineItem, InvoiceLineItem): HIGH for structure; MEDIUM for exact field mapping (QuoteLineItems table schema not read directly)
- Pitfalls: HIGH — all derived from actual source code patterns

**Research date:** 2026-03-14
**Valid until:** 2026-04-14 (stable codebase; no external API dependencies)
