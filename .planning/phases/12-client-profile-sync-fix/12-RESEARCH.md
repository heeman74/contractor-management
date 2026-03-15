# Phase 12: Client Profile Sync Fix - Research

**Researched:** 2026-03-14
**Domain:** Flutter sync handler URL routing / FastAPI REST endpoint alignment
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CLNT-01 | Customer/client CRM with profiles and job history | Push URL fix restores offline sync path; pull-side and direct API already work — this is the last gap closing full offline-first CRM functionality |
</phase_requirements>

---

## Summary

Phase 12 closes integration gap INT-04: `ClientProfileSyncHandler.push()` uses two wrong URL patterns (`POST /clients/profiles` for CREATE and `PATCH /clients/profiles/{id}` for UPDATE) that do not exist on the backend. The backend only exposes `POST /clients/{user_id}/profile` with upsert semantics — a single endpoint that handles both create and update. Every offline client profile edit enqueued in the sync queue is parking on HTTP 404, silently stalling.

The fix is small and surgical: update `push()` in `client_profile_sync_handler.dart` to route both CREATE and UPDATE operations to `POST /clients/{user_id}/profile`. The `user_id` is available in the sync queue payload (already stored as `userId` field by `job_dao.dart`). Both operations map to the same endpoint because the backend's `create_or_update_profile` is a true upsert that handles both create and partial update in one call.

A single E2E test in `mobile/test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart` must verify the complete offline-edit → sync → backend-persist flow using the project's established pattern: real Drift in-memory DB, `MockDioClient`, `verify()` on captured HTTP calls, and `await drainQueue()` / `await pullDelta()`.

**Primary recommendation:** Two-line URL fix in `push()`, consolidating CREATE and UPDATE to `POST /clients/{user_id}/profile` using `user_id` extracted from the payload.

---

## Standard Stack

### Core (already in project — no new deps)
| Component | Version | Purpose | Notes |
|-----------|---------|---------|-------|
| DioClient.pushWithIdempotency | — | HTTP push with idempotency key | Already used by all other sync handlers; `method` param defaults to `'POST'` — no change needed for CREATE/UPDATE both being POST |
| SyncHandler abstract class | — | `push(SyncQueueData)` interface | Handler reads `item.payload` (JSON string), `item.entityId`, `item.operation` |
| Drift ClientProfiles table | schema v3+ | Local storage | `userId` column is non-nullable; the value is in the enqueued payload |
| mocktail | current | Test mocks | `MockDioClient`, `when()` + `verify()` pattern from Phase 9 E2E |

### No New Dependencies
This phase requires zero new packages. All tooling is established.

---

## Architecture Patterns

### Backend Endpoint Contract (HIGH confidence — read from source)

```
POST /api/v1/clients/{user_id}/profile
```

- `user_id` is a path parameter (UUID)
- Request body: `ClientProfileCreate` schema (includes `user_id`, `billing_address`, `tags`, `admin_notes`, `referral_source`, `preferred_contractor_id`, `preferred_contact_method`)
- Semantics: **upsert** — `create_or_update_profile` in `crm_service.py` calls `get_or_create_profile` then applies non-None fields
- Returns: `201 Created` with `ClientProfileResponse`
- **There is NO separate PATCH endpoint for profiles** — the `POST` handles both create and update

### Sync Queue Payload Structure (HIGH confidence — read from source)

`job_dao.dart:insertClientProfile` enqueues this payload for CREATE:
```json
{
  "id": "<profile_uuid>",
  "companyId": "<company_uuid>",
  "userId": "<user_uuid>",
  "version": 1,
  "createdAt": "2026-...",
  "updatedAt": "2026-..."
}
```

Note: The payload uses camelCase keys (`userId`, `companyId`). The backend `ClientProfileCreate` schema expects snake_case (`user_id`, `billing_address`, etc.). The handler must either:
1. Extract `userId` from the camelCase payload directly for the URL path, OR
2. The payload can be sent as-is if the backend accepts it via FastAPI's alias handling

Research finding: FastAPI's `ClientProfileCreate` uses standard snake_case Pydantic field names without `alias` or `populate_by_name`. The camelCase payload keys (`userId`, `companyId`) will NOT be recognized by the backend schema — they will be silently ignored, and required field `user_id` will be missing, causing a 422. However, since `user_id` is in the URL path (not body), the path extraction is the critical piece. The body only needs the optional CRM fields.

**Correct approach**: Extract `userId` from payload for the URL path. The body can pass the payload as-is — the backend's upsert will apply whatever optional CRM fields are recognized (billing_address, tags, etc.) and ignore unknown camelCase keys.

### Pattern: Other Sync Handlers (HIGH confidence — read from source)

Handlers that use entity IDs in URL paths extract from `item.entityId` or the payload:

```dart
// From job_sync_handler.dart pattern for UPDATE:
final jobId = item.entityId;
await _dioClient.pushWithIdempotency('/jobs/$jobId', payload, item.id, method: 'PATCH');

// From note_sync_handler.dart pattern:
final noteId = payload['id'] as String;
await _dioClient.pushWithIdempotency('/jobs/$jobId/notes/$noteId', payload, item.id);
```

For `ClientProfileSyncHandler`, `user_id` is NOT stored as `item.entityId` — `item.entityId` holds the **profile UUID** (the `id` field), not the `userId`. So `user_id` must be extracted from `payload['userId']`.

### Recommended Fix Pattern

```dart
// In client_profile_sync_handler.dart — push() method

@override
Future<void> push(SyncQueueData item) async {
  final payload = jsonDecode(item.payload) as Map<String, dynamic>;
  // userId is stored camelCase in the enqueued payload
  final userId = payload['userId'] as String;

  // Both CREATE and UPDATE use POST /clients/{user_id}/profile (upsert semantics)
  await _dioClient.pushWithIdempotency(
    '/clients/$userId/profile',
    payload,
    item.id,
  );
}
```

This eliminates the switch statement entirely — the backend's single upsert endpoint handles both cases.

### E2E Test Pattern (HIGH confidence — established in Phase 9, Phase 11)

From `phase_9_sync_gap_closure_e2e_test.dart`:

```dart
// Mock pattern
class MockDioClient extends Mock implements DioClient {}
class MockDio extends Mock implements Dio {}

// Setup
final db = AppDatabase(NativeDatabase.memory());
final mockDioClient = MockDioClient();
when(() => mockDioClient.pushWithIdempotency(any(), any(), any()))
    .thenAnswer((_) async => Response(
          data: {},
          statusCode: 201,
          requestOptions: RequestOptions(path: ''),
        ));

// Verify
verify(() => mockDioClient.pushWithIdempotency(
  '/clients/$userId/profile',
  any(),
  any(),
)).called(1);
```

The E2E test must cover:
1. **CREATE path**: Seed a sync queue item with `operation='CREATE'`, call `drainQueue()`, verify `POST /clients/{user_id}/profile` was called
2. **UPDATE path**: Seed a sync queue item with `operation='UPDATE'`, call `drainQueue()`, verify same URL was called
3. **Full flow**: Seed client profile in Drift, enqueue CREATE via DAO, drain queue, verify HTTP call and that profile remains in Drift (applyPulled side already tested in Phase 9)

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP path extraction | Custom URL builder class | Direct string interpolation `'/clients/$userId/profile'` | Identical to every other handler in the project; no abstraction needed |
| Idempotency | Manual retry deduplication | `DioClient.pushWithIdempotency` with item.id as key | Already handles `Idempotency-Key` header; backend deduplication established in Phase 2 |
| Test DB | SQLite test DB setup | `AppDatabase(NativeDatabase.memory())` | In-memory Drift pattern is established; matches CLAUDE.md rule |

---

## Common Pitfalls

### Pitfall 1: Extracting user_id from wrong field
**What goes wrong:** Using `item.entityId` as the user_id in the URL path
**Why it happens:** `item.entityId` stores the **profile UUID** (the row's `id`), not the `userId` foreign key
**How to avoid:** Extract from `payload['userId']` (camelCase, as stored by `job_dao.dart:insertClientProfile`)
**Warning signs:** Backend returns 422 Unprocessable Entity or 404 "Client profile not found for user <profile-uuid>"

### Pitfall 2: Keeping the UPDATE→PATCH branch
**What goes wrong:** Keeping `case 'UPDATE'` pointing to a PATCH endpoint that does not exist
**Why it happens:** The switch structure from the original code is preserved with only CREATE fixed
**How to avoid:** The backend has **no PATCH endpoint** for client profiles. `POST /clients/{user_id}/profile` is upsert — it handles both create and update. Eliminate the switch; route all operations to POST.
**Warning signs:** UPDATE operations still park with 404

### Pitfall 3: pumpAndSettle in E2E tests
**What goes wrong:** Test hangs or times out waiting for Drift stream to settle
**Why it happens:** Drift streams never emit a "done" event in tests
**How to avoid:** Use `tester.pump()` (not `pumpAndSettle()`) and `await` DAO calls directly — established pattern in MEMORY.md and CLAUDE.md
**Warning signs:** Test times out after 10+ seconds

### Pitfall 4: Payload snake_case vs camelCase mismatch
**What goes wrong:** Sending the raw camelCase payload and expecting the backend to populate CRM fields
**Why it happens:** `job_dao.dart` stores payload keys as camelCase (`userId`, `companyId`) but backend expects snake_case (`user_id`, `company_id`)
**How to avoid:** Since `user_id` is in the URL path (not body), the body mismatch is non-fatal for the core fix. The backend applies whatever recognized fields exist — unknown camelCase keys are ignored. For a complete fix, the CREATE payload in `insertClientProfile` should use snake_case keys, but this is a secondary improvement. The critical fix is the URL path.
**Warning signs:** Profile CRM fields (billing_address, admin_notes, etc.) fail to persist when pushed from offline — but this only matters if those fields are being edited offline

---

## Code Examples

### Verified: Backend endpoint signature (source: router.py line 866-884)
```python
@router.post(
    "/clients/{user_id}/profile",
    status_code=status.HTTP_201_CREATED,
    response_model=ClientProfileResponse,
)
async def create_or_update_client_profile(
    user_id: uuid.UUID,
    data: ClientProfileCreate,
    ...
) -> ClientProfileResponse:
    """Create or update a client profile (upsert semantics)."""
```

### Verified: Sync queue enqueue payload (source: job_dao.dart lines 391-407)
```dart
await into(syncQueue).insert(
  _buildQueueEntry(
    entityType: 'client_profile',
    entityId: entry.id.value,       // <-- profile UUID, not user UUID
    operation: 'CREATE',
    payload: {
      'id': entry.id.value,
      'companyId': entry.companyId.value,
      'userId': entry.userId.value,  // <-- this is what we need for URL
      ...
    },
  ),
);
```

### Verified: DioClient.pushWithIdempotency signature (source: dio_client.dart lines 88-105)
```dart
Future<Response<dynamic>> pushWithIdempotency(
  String path,
  Map<String, dynamic> data,
  String idempotencyKey, {
  String method = 'POST',
})
```

---

## State of the Art

| Old (Broken) Approach | Correct Approach | Impact |
|----------------------|-----------------|--------|
| `POST /clients/profiles` (CREATE) | `POST /clients/{user_id}/profile` | 404 → 201 |
| `PATCH /clients/profiles/{id}` (UPDATE) | `POST /clients/{user_id}/profile` (upsert) | 404 → 201 |
| Switch on CREATE/UPDATE | Single POST for both | Simplified handler |

---

## Open Questions

1. **Should the payload be normalized to snake_case?**
   - What we know: `job_dao.dart` enqueues camelCase keys (`userId`, `companyId`); backend `ClientProfileCreate` expects snake_case
   - What's unclear: Whether any CRM editable fields (billing_address, tags, etc.) are ever modified offline — if not, the body content doesn't matter practically
   - Recommendation: Document as tech debt but do NOT add to Phase 12 scope. The critical fix is the URL path. Payload normalization is a Phase 4 cleanup item. Keeping the scope minimal reduces risk.

2. **Does UPDATE need to enqueue via the DAO at all?**
   - What we know: There is no `updateClientProfile` DAO method in `job_dao.dart` — only `insertClientProfile` (CREATE). The UPDATE case in the handler was dead code because no DAO method ever enqueues an UPDATE for client profiles.
   - What's unclear: Whether the UPDATE branch was planned for future CRM edit screens
   - Recommendation: The simplest fix removes the UPDATE branch entirely (since no code ever enqueues one). If the planner wants defensive coverage, keep a unified POST branch that handles both. Either approach is correct.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Flutter test (flutter_test) + mocktail |
| Config file | mobile/pubspec.yaml (flutter_test in dev_dependencies) |
| Quick run command | `flutter test mobile/test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart` |
| Full suite command | `flutter test mobile/test/` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CLNT-01 | CREATE: offline profile enqueue → push to `/clients/{user_id}/profile` | E2E unit | `flutter test mobile/test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart` | ❌ Wave 0 |
| CLNT-01 | UPDATE: offline profile update → push to same upsert endpoint | E2E unit | `flutter test mobile/test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart` | ❌ Wave 0 |
| CLNT-01 | Full flow: Drift insert → queue → drain → HTTP call verified | E2E unit | `flutter test mobile/test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test mobile/test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart`
- **Per wave merge:** `flutter test mobile/test/`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `mobile/test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart` — covers all CLNT-01 sync push scenarios

*(No new framework setup needed — mocktail and flutter_test already in project)*

---

## Sources

### Primary (HIGH confidence)
- Direct read of `mobile/lib/features/jobs/data/client_profile_sync_handler.dart` — exact broken URLs on lines 34, 41
- Direct read of `backend/app/features/jobs/router.py` lines 866-884 — exact backend endpoint signature
- Direct read of `backend/app/features/jobs/schemas.py` lines 183-218 — `ClientProfileCreate` schema fields
- Direct read of `mobile/lib/features/jobs/data/job_dao.dart` lines 385-408 — sync payload structure
- Direct read of `mobile/lib/core/network/dio_client.dart` lines 88-105 — `pushWithIdempotency` signature
- Direct read of `.planning/v1.0-MILESTONE-AUDIT.md` — INT-04 gap description and evidence

### Secondary (MEDIUM confidence)
- Phase 9 E2E test (`phase_9_sync_gap_closure_e2e_test.dart`) — verified MockDioClient + SyncEngine test pattern
- Phase 11 E2E test (`phase_11_integration_polish_e2e_test.dart`) — verified pump() pattern and fake notifier pattern

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components are existing project code, read from source
- Architecture: HIGH — backend endpoint and handler code both read directly; no inference
- Pitfalls: HIGH — identified from direct code analysis (entityId vs userId, missing PATCH endpoint, Drift stream behavior from MEMORY.md)

**Research date:** 2026-03-14
**Valid until:** Stable (fix is against known committed code; no external dependencies)
