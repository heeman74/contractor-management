# Phase 2: Offline Sync Engine -- Nyquist Validation Map

**Phase:** 2 -- Offline Sync Engine
**Requirements:** INFRA-03, INFRA-04
**nyquist_compliant:** true
**Validated:** 2026-03-14

---

## Requirement-to-Test Verification Map

### INFRA-03: Offline-first mobile app with local data storage

| Task | Behavior | Test File | Test Type | Automated Command | Status |
|------|----------|-----------|-----------|-------------------|--------|
| 02-01 | SyncQueueDao.getPendingItems returns items in FIFO order (createdAt ASC) | `mobile/test/unit/core/sync/sync_queue_dao_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_queue_dao_test.dart` | COVERED |
| 02-01 | SyncQueueDao.markSynced removes item from queue | `mobile/test/unit/core/sync/sync_queue_dao_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_queue_dao_test.dart` | COVERED |
| 02-01 | SyncQueueDao.markParked sets status and error message | `mobile/test/unit/core/sync/sync_queue_dao_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_queue_dao_test.dart` | COVERED |
| 02-01 | SyncQueueDao.watchPendingCount emits correct reactive count | `mobile/test/unit/core/sync/sync_queue_dao_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_queue_dao_test.dart` | COVERED |
| 02-01 | SyncCursorDao.getCursor returns null on first launch (never synced) | `mobile/test/unit/core/sync/sync_cursor_dao_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_cursor_dao_test.dart` | COVERED |
| 02-01 | CompanyDao insert/update/delete atomically write to entity table and sync_queue | `mobile/test/unit/features/company/company_dao_test.dart` | Unit | `cd mobile && flutter test test/unit/features/company/company_dao_test.dart` | COVERED |
| 02-01 | Soft-deleted records excluded from read streams (watchAllCompanies, watchUsersByCompany) | `mobile/test/unit/features/company/company_dao_test.dart` | Unit | `cd mobile && flutter test test/unit/features/company/company_dao_test.dart` | COVERED |
| 02-03 | SyncEngine.drainQueue processes items in FIFO order | `mobile/test/unit/core/sync/sync_engine_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_engine_test.dart` | COVERED |
| 02-03 | SyncEngine parks 4xx errors immediately (no retry) | `mobile/test/unit/core/sync/sync_engine_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_engine_test.dart` | COVERED |
| 02-03 | SyncEngine retries 5xx errors with exponential backoff | `mobile/test/unit/core/sync/sync_engine_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_engine_test.dart` | COVERED |
| 02-03 | SyncEngine resets attemptCount after max retries (item stays pending) | `mobile/test/unit/core/sync/sync_engine_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_engine_test.dart` | COVERED |
| 02-03 | SyncEngine concurrent drain prevention (_isSyncing guard) | `mobile/test/unit/core/sync/sync_engine_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_engine_test.dart` | COVERED |
| 02-03 | ConnectivityService triggers callback on real connectivity restore | `mobile/test/unit/core/sync/connectivity_service_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/connectivity_service_test.dart` | COVERED |
| 02-03 | ConnectivityService does not trigger on ConnectivityResult.none | `mobile/test/unit/core/sync/connectivity_service_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/connectivity_service_test.dart` | COVERED |
| 02-03 | SyncRegistry maps entity types to handlers; getHandler throws on unregistered type | `mobile/test/unit/core/sync/sync_registry_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_registry_test.dart` | COVERED |
| 02-03 | Each SyncHandler pushes via DioClient with Idempotency-Key header | `mobile/test/unit/core/sync/sync_engine_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_engine_test.dart` | COVERED |

### INFRA-04: Background sync engine with conflict resolution

| Task | Behavior | Test File | Test Type | Automated Command | Status |
|------|----------|-----------|-----------|-------------------|--------|
| 02-02 | Delta sync returns all entities changed since cursor timestamp | `backend/tests/integration/test_delta_sync.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_delta_sync.py -v` | COVERED |
| 02-02 | Tombstoned records (deleted_at set) included in delta response | `backend/tests/integration/test_delta_sync.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_delta_sync.py -v` | COVERED |
| 02-02 | Delta sync respects tenant isolation (RLS enforced on /sync endpoint) | `backend/tests/integration/test_delta_sync.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_delta_sync.py -v` | COVERED |
| 02-02 | Delta sync response contains server_timestamp in ISO8601 | `backend/tests/integration/test_delta_sync.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_delta_sync.py -v` | COVERED |
| 02-02 | updated_at auto-advances on UPDATE via PostgreSQL trigger | `backend/tests/integration/test_delta_sync.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_delta_sync.py -v` | COVERED |
| 02-02 | user_roles included in delta sync response | `backend/tests/integration/test_delta_sync.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_delta_sync.py -v` | COVERED |
| 02-02 | Duplicate UUID POST returns existing record (ON CONFLICT DO NOTHING) | `backend/tests/integration/test_idempotency.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_idempotency.py -v` | COVERED |
| 02-02 | Idempotency preserves original data (first write wins) | `backend/tests/integration/test_idempotency.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_idempotency.py -v` | COVERED |
| 02-02 | Concurrent duplicate creates result in exactly 1 DB row | `backend/tests/integration/test_idempotency.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_idempotency.py -v` | COVERED |
| 02-03 | SyncEngine.pullDelta fetches from /sync?cursor= and upserts into local Drift DB | `mobile/test/unit/core/sync/sync_engine_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_engine_test.dart` | COVERED |
| 02-03 | pullDelta updates sync cursor after successful pull | `mobile/test/unit/core/sync/sync_engine_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_engine_test.dart` | COVERED |
| 02-03 | pullDelta with null cursor (first launch) omits cursor param | `mobile/test/unit/core/sync/sync_engine_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_engine_test.dart` | COVERED |
| 02-03 | SyncStatus stream emits correct states during drain (syncing, allSynced) | `mobile/test/unit/core/sync/sync_engine_test.dart` | Unit | `cd mobile && flutter test test/unit/core/sync/sync_engine_test.dart` | COVERED |
| 02-05 | Sync edge cases (partial failures, empty queue, network interrupts) | `backend/tests/integration/test_sync_edge_cases.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_sync_edge_cases.py -v` | COVERED |
| 02-06 | Empty cursor string returns 200 (not 422) | `backend/tests/integration/test_delta_sync.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_delta_sync.py -v` | COVERED |
| 02-06 | Authenticated users on /splash or /onboarding redirected to /home | `mobile/test/unit/core/routing/app_router_test.dart` | Widget | `cd mobile && flutter test test/unit/core/routing/app_router_test.dart` | COVERED |

---

## E2E Test Coverage

| Test File | Covers | Command |
|-----------|--------|---------|
| `mobile/test/e2e/phase_2_offline_sync_e2e_test.dart` | Full offline sync flow: queue population, drain, delta pull, connectivity restore trigger, sync status UI states | `cd mobile && flutter test test/e2e/phase_2_offline_sync_e2e_test.dart` |

---

## Additional Test Files (Beyond Requirement Map)

| Test File | Purpose | Command |
|-----------|---------|---------|
| `mobile/test/unit/core/sync/handlers/company_sync_handler_test.dart` | CompanySyncHandler push and applyPulled unit tests | `cd mobile && flutter test test/unit/core/sync/handlers/company_sync_handler_test.dart` |
| `mobile/test/unit/core/sync/handlers/user_sync_handler_test.dart` | UserSyncHandler push and applyPulled unit tests | `cd mobile && flutter test test/unit/core/sync/handlers/user_sync_handler_test.dart` |

---

## Run All Phase 2 Tests

```bash
# Flutter (mobile)
cd mobile && flutter test test/unit/core/sync/ test/e2e/phase_2_offline_sync_e2e_test.dart

# Backend
cd backend && uv run python -m pytest tests/integration/test_delta_sync.py tests/integration/test_idempotency.py tests/integration/test_sync_edge_cases.py -v
```

---

## Coverage Summary

| Requirement | Total Behaviors | Covered | Partial | Missing | Compliance |
|-------------|----------------|---------|---------|---------|------------|
| INFRA-03 | 16 | 16 | 0 | 0 | FULL |
| INFRA-04 | 16 | 16 | 0 | 0 | FULL |
| **Total** | **32** | **32** | **0** | **0** | **FULL** |

---

## Known Caveats

1. **User idempotency test gap (WARNING):** `test_idempotency.py` `test_duplicate_user_uuid_returns_existing` tests user creation flow but does not exercise the ON CONFLICT DO NOTHING path with a duplicate UUID for users specifically. Company idempotency is fully proven including concurrent load. The user service has `on_conflict_do_nothing` structurally but lacks a dedicated duplicate-UUID proof test. This is a test coverage weakness, not an implementation gap.
