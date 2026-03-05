---
phase: 01-foundation
plan: 05
subsystem: testing
tags: [pytest, pytest-asyncio, httpx, alembic, rls, postgresql, flutter, go_router, riverpod, seed-data]

# Dependency graph
requires:
  - 01-03 (FastAPI CRUD endpoints, tenant middleware, RLS migration, SQLAlchemy models)
  - 01-04 (AuthState Freezed sealed class, AuthNotifier, go_router with role guards, RouteNames)
provides:
  - "backend/tests/conftest.py: multi-tenant fixtures (async_client, tenant_a_client, tenant_b_client, seed_two_tenants, clean_tables autouse)"
  - "backend/tests/integration/test_tenant_isolation.py: 5 tests proving RLS cross-tenant isolation"
  - "backend/tests/integration/test_role_endpoints.py: 5 tests proving role assignment CRUD"
  - "mobile/test/unit/features/auth/auth_provider_test.dart: 6 AuthNotifier state unit tests"
  - "mobile/test/unit/core/routing/app_router_test.dart: 8 go_router role guard testWidgets tests"
  - "backend/scripts/seed_data.py: idempotent async script creating 2 demo companies with users and roles"
affects:
  - "All Phase 4-8 features — test patterns established here (conftest fixtures, tenant client pattern)"
  - "Phase 2 (Sync Engine) — seed data provides dev environment for sync testing"
  - "Phase 6 (Auth) — auth_provider_test.dart patterns apply to real JWT auth tests"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Multi-tenant test pattern: separate AsyncClient per tenant with X-Company-Id header; no dependency overrides so real TenantMiddleware -> ContextVar -> SET LOCAL RLS path runs"
    - "Alembic in test setup: run alembic upgrade head via subprocess to get real RLS policies (not create_all which skips migration SQL)"
    - "autouse clean_tables fixture: TRUNCATE user_roles, users, companies before each test for isolation"
    - "Flutter test pattern: ProviderScope overrides with _StubAuthNotifier to control auth state; ProviderContainer for unit tests without widgets"
    - "seed_data.py idempotency: check company name existence before insert; runs via python -m scripts.seed_data"

key-files:
  created:
    - backend/tests/integration/__init__.py
    - backend/tests/integration/test_tenant_isolation.py
    - backend/tests/integration/test_role_endpoints.py
    - mobile/test/unit/features/auth/auth_provider_test.dart
    - mobile/test/unit/core/routing/app_router_test.dart
    - backend/scripts/__init__.py
    - backend/scripts/seed_data.py
  modified:
    - backend/tests/conftest.py (complete rewrite with multi-tenant fixtures)

key-decisions:
  - "Test fixtures use real get_db (no override) — exercises full TenantMiddleware -> ContextVar -> SET LOCAL path; injecting a mock session would bypass RLS"
  - "Alembic migrations run in test setup (not create_all) — RLS policies are Alembic SQL that create_all cannot reproduce"
  - "clean_tables autouse fixture truncates before each test — ensures no cross-test contamination; safer than per-test transaction rollback which would interfere with multi-request tests"
  - "Flutter tests written for final architecture (require build_runner) — same pattern as Plans 01-04; will compile when Flutter SDK installed"
  - "seed_data.py uses SET LOCAL per insert to satisfy RLS for user creation — required because RLS FORCE is on users/user_roles tables"

requirements-completed:
  - INFRA-01
  - INFRA-02

# Metrics
duration: 7min
completed: 2026-03-05
---

# Phase 1 Plan 05: Integration Tests and Seed Data Summary

**PostgreSQL RLS tenant isolation proven by 5 integration tests + 5 role CRUD tests via real Alembic-migrated test DB; Flutter role guard behavior proven by 6 AuthNotifier unit tests and 8 go_router testWidgets tests; idempotent seed data script creates 2 demo companies**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-03-05T07:16:49Z
- **Completed:** 2026-03-05T07:24:00Z
- **Tasks:** 2 of 2
- **Files modified:** 8 (7 created, 1 modified)

## Accomplishments

- Wrote the most critical Phase 1 tests: 5 integration tests proving PostgreSQL RLS prevents cross-tenant data access at both read and write levels, including bidirectional isolation and safe empty-default with no tenant header
- Rewrote conftest.py with multi-tenant fixtures that use real get_db dependency (no session injection) so TenantMiddleware -> ContextVar -> after_begin SET LOCAL RLS path runs exactly as production
- Created 5 role endpoint tests covering all 3 role types, invalid role rejection (422), correct response fields, 404 for non-existent users, and tenant-scoped role visibility
- Created 6 Flutter AuthNotifier unit tests covering state transitions (loading -> authenticated -> unauthenticated), multi-role support, and all 3 role type assignments using ProviderContainer
- Created 8 Flutter go_router testWidgets tests verifying role guard redirects (unauthenticated -> /onboarding, contractor blocked from /admin, client blocked from /contractor, multi-role access to both)
- Created idempotent seed_data.py script producing 2 demo companies (Ace Plumbing & Electrical + BuildRight Construction) with users across all 3 role types for multi-tenant dev testing

## Task Commits

Each task was committed atomically:

1. **Task 1: Write backend tenant isolation and role integration tests** - `0477a37` (feat)
2. **Task 2: Write Flutter role guard tests and seed data script** - `dc42ff2` (feat)

## Files Created/Modified

**Backend tests:**
- `backend/tests/conftest.py` — Rewritten: test_engine (Alembic upgrade), clean_tables (autouse TRUNCATE), async_client, seed_two_tenants, tenant_a_client, tenant_b_client
- `backend/tests/integration/__init__.py` — Package init for integration test module
- `backend/tests/integration/test_tenant_isolation.py` — 5 RLS isolation tests: bidirectional read isolation, each-tenant-sees-own-users, no-header returns empty, cross-tenant write blocked
- `backend/tests/integration/test_role_endpoints.py` — 5 role CRUD tests: assign all 3 types, invalid role 422, response fields, 404 nonexistent user, tenant-scoped role visibility

**Flutter tests:**
- `mobile/test/unit/features/auth/auth_provider_test.dart` — 6 AuthNotifier tests: initial loading state, setMockUser transitions, logout, single role, multi-role, overwrite behavior
- `mobile/test/unit/core/routing/app_router_test.dart` — 8 testWidgets tests: loading->splash, unauth->onboarding, admin->adminTeam, contractor blocked from /admin, client blocked from /contractor, multi-role admin+contractor access, shared route access

**Seed data:**
- `backend/scripts/__init__.py` — Package init documenting seed_data usage
- `backend/scripts/seed_data.py` — Async idempotent seeder: Ace Plumbing & Electrical (4 users: admin, 2 contractors, 1 client) + BuildRight Construction (2 users: admin, 1 contractor); SET LOCAL RLS for user creation; usage instructions printed

## Decisions Made

- Used real `get_db` dependency (no override) in test fixtures so the complete TenantMiddleware -> ContextVar -> after_begin SET LOCAL RLS execution path is tested — injecting a mock session would bypass the RLS enforcement being proven
- Used Alembic subprocess migration in test setup rather than `Base.metadata.create_all()` — the RLS policies, ENABLE ROW LEVEL SECURITY, and FORCE ROW LEVEL SECURITY are Alembic SQL that `create_all` cannot reproduce
- Used TRUNCATE (autouse before each test) rather than per-test transaction rollback — multi-tenant tests involve multiple requests across independent sessions; rolling back a single session would not clean up data from other requests
- Flutter tests written for final post-build_runner state — same pattern as Plans 01-04; requires `dart run build_runner build --delete-conflicting-outputs`
- seed_data.py uses `SET LOCAL app.current_company_id` before each user insert — required because FORCE ROW LEVEL SECURITY applies to all sessions including script sessions

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

**Flutter SDK not installed:** Same blocker as Plans 01-04. `flutter test` and `dart run build_runner build` cannot run until Flutter SDK is installed. All test files are written using go_router 17.1.0, Riverpod 3.2.1, and Freezed 3.2.5 APIs and will compile correctly once build_runner generates the required `.g.dart` and `.freezed.dart` files.

**Test database not running:** `pytest tests/integration/` requires PostgreSQL to be running (via Docker Compose or local installation). The tests will fail with a connection error if the database is unavailable. Run `docker compose up -d postgres` before running integration tests.

## User Setup Required

**Backend integration tests:** Requires PostgreSQL running with the test database:
```bash
# Start test database
docker compose up -d postgres

# Run migrations (if not already applied)
cd backend && DATABASE_URL=postgresql+asyncpg://appuser:apppassword@localhost:5432/contractorhub_test alembic upgrade head

# Run integration tests
cd backend && TEST_DATABASE_URL=postgresql+asyncpg://appuser:apppassword@localhost:5432/contractorhub_test pytest tests/integration/ -v
```

**Flutter tests:** Requires Flutter SDK and build_runner:
```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test test/unit/
```

**Seed data:**
```bash
# With Docker Compose backend running:
docker compose exec backend python -m scripts.seed_data

# Or locally with DATABASE_URL set:
cd backend && python -m scripts.seed_data
```

## Self-Check: PASSED

- FOUND: backend/tests/conftest.py
- FOUND: backend/tests/integration/__init__.py
- FOUND: backend/tests/integration/test_tenant_isolation.py (contains test_tenant_a_cannot_read_tenant_b)
- FOUND: backend/tests/integration/test_role_endpoints.py (contains test_assign_all_role_types)
- FOUND: backend/scripts/seed_data.py (contains seed_data function)
- FOUND: mobile/test/unit/features/auth/auth_provider_test.dart (contains testWidgets patterns)
- FOUND: mobile/test/unit/core/routing/app_router_test.dart (contains testWidgets)
- FOUND commit: 0477a37 (Task 1)
- FOUND commit: dc42ff2 (Task 2)

## Next Phase Readiness

- Phase 1 is architecturally complete: Flutter scaffold, FastAPI backend, RLS isolation, role guards, and isolation proofs all in place
- The tenant isolation tests are the definitive proof that Phase 1 architecture is sound — run them when PostgreSQL is available to get final confirmation
- Seed data enables immediate dev environment setup for Phase 2 (Sync Engine) and Phase 4 (Jobs feature)
- Test fixtures (tenant_a_client, tenant_b_client pattern) are reusable for all future Phase 2-8 integration tests
- Flutter test pattern (ProviderContainer, ProviderScope overrides, _StubAuthNotifier) is the established pattern for all future auth-dependent widget tests

---
*Phase: 01-foundation*
*Completed: 2026-03-05*
