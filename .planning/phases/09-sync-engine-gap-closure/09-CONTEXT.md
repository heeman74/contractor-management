# Phase 9: Sync Engine Gap Closure - Context

**Gathered:** 2026-03-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Complete pullDelta() to process all 14 entity types from the server and fix JobSyncHandler to map all fields — enabling multi-device sync for bookings, quotes, invoices, and CRM data. This is gap closure from the v1.0 milestone audit, not new functionality.

</domain>

<decisions>
## Implementation Decisions

### Entity processing order
- Process in FK dependency order: companies → users → user_roles → jobs → bookings/job_sites/job_notes/time_entries/attachments/client_profiles/job_requests → quotes → quote_line_items → invoices → invoice_line_items
- Guarantees parent rows exist before children are inserted
- Per-type commits (not all-or-nothing transaction) — each entity type is processed and committed independently

### pullDelta() refactor to loop
- Refactor from copy-paste blocks to a loop over a list of (responseKey, handlerName) tuples in dependency order
- Eliminates 14+ explicit blocks, makes adding future entity types trivial, centralizes error handling and logging

### Line item handling
- quote_line_items and invoice_line_items are separate entity types with their own handlers and processing in pullDelta()
- Server returns them as flat top-level arrays (not nested in parent objects)
- Each line item has its own FK (quote_id / invoice_id)

### Pull failure handling
- Individual entity failures: wrap each applyPulled() call in try/catch, skip and continue on failure
- No retry — skip on first failure; next pullDelta() cycle re-delivers the entity since cursor updates are idempotent
- Errors logged via debugPrint only (entity type + ID), not surfaced to user via sync status
- Top-level DioException handling unchanged — network failures remain non-fatal and silent
- Unknown entity type keys in response: debugPrint warning for forward-compatibility awareness

### Cursor behavior
- Update cursor (server_timestamp) after all types are attempted, even if some failed
- Failed types get re-delivered on next pull since server includes all changes since cursor

### Logging
- Per-type entity count via debugPrint after processing each type
- Aggregate summary after all types processed: "pullDelta: N pulled, M skipped, T types processed"
- Debug-only — no-op in release builds per existing convention

### JobSyncHandler field mapping
- Add 5 missing fields to applyPulled(): gpsLatitude, gpsLongitude, gpsAddress, quoteId, invoiceId
- Server always wins: null values from server overwrite existing local values (consistent with existing applyPulled() pattern)

### Sync scope
- Client processes everything the server sends — no client-side role filtering
- Server-side RLS and role filtering is the authority (already filters quotes to sent/viewed/approved/declined for clients)
- Backend returns empty arrays for entity types filtered by role (consistent shape, no null checks needed)

### Backend endpoint
- Extend existing /api/v1/sync endpoint with 7 new entity type arrays
- Backwards-compatible: new keys default to empty arrays
- No v2 endpoint needed

### Claude's Discretion
- Exact handler implementations for new entity types (follow existing handler patterns)
- Test structure and assertion specifics
- Any necessary Drift migration details for missing columns

</decisions>

<specifics>
## Specific Ideas

No specific requirements — all decisions follow established patterns from Phase 2 sync engine. The loop-based refactor is the main architectural change; all other work is mechanical gap closure.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- All 7 missing sync handlers already exist as files (booking_sync_handler.dart, job_site_sync_handler.dart, client_profile_sync_handler.dart, job_request_sync_handler.dart, quote_sync_handler.dart, invoice_sync_handler.dart)
- SyncRegistry already has handler registration for all types
- Existing pullDelta() pattern (7 working entity types) serves as exact template

### Established Patterns
- SyncHandler abstract class: push() + applyPulled() interface
- insertOnConflictUpdate for idempotent upserts in Drift
- DioClient.pushWithIdempotency for outbound sync
- Per-entity-type cursor not needed — single server_timestamp cursor covers all types

### Integration Points
- sync_engine.dart pullDelta() — main change location
- job_sync_handler.dart applyPulled() — add 5 missing fields
- Backend sync endpoint (sync router) — add 7 new entity type queries
- service_locator.dart — verify all handlers registered in SyncRegistry

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 09-sync-engine-gap-closure*
*Context gathered: 2026-03-14*
