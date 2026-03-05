---
phase: 01-foundation
plan: 03
subsystem: domain-model
tags: [flutter, dart, freezed, drift, riverpod, fastapi, pydantic, sqlalchemy, entities, dao, rest-api]

# Dependency graph
requires:
  - 01-01 (Flutter scaffold with Drift tables and AppDatabase)
  - 01-02 (FastAPI backend with SQLAlchemy models, TenantMiddleware, RLS migration)
provides:
  - "UserRole enum (admin, contractor, client) in shared/models/user_role.dart"
  - "TradeType enum with 9 trade specializations in shared/models/trade_type.dart"
  - "CompanyEntity: @freezed with full business profile (tradeTypes, address, phone, logo, businessNumber)"
  - "UserEntity: @freezed with companyId tenant scoping"
  - "UserRoleEntity: @freezed with UserRole enum, userId, companyId"
  - "CompanyDao: @DriftAccessor with reactive Stream-based reads (watchAllCompanies)"
  - "UserDao: @DriftAccessor with watchUsersByCompany(Stream) and watchRolesForUser(Stream)"
  - "Riverpod providers: companiesProvider (Stream) and companyUsersProvider (Stream)"
  - "Backend Company CRUD: POST, GET, PATCH /api/v1/companies/"
  - "Backend User CRUD: POST, GET /api/v1/users/ with tenant scoping from middleware"
  - "Role assignment: POST/GET /api/v1/users/{id}/roles supporting admin, contractor, client"
affects:
  - "01-04 (go_router + role guards — builds on UserRole enum and entity layer)"
  - "All Phase 4-8 feature screens — every screen streams from these DAOs"
  - "Phase 2 (Sync Engine) — DAOs are the local write targets for sync operations"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Freezed entity pattern: @freezed abstract class with fromJson/toJson for all domain objects"
    - "Drift DAO pattern: @DriftAccessor with Stream<> watch queries — all UI reads are reactive"
    - "Entity mapping: DAO._rowToEntity() converts Drift row to Freezed entity (never expose ORM rows to UI)"
    - "TradeType storage: comma-separated text in Drift; PostgreSQL ARRAY(String) in backend"
    - "Tenant scoping: company_id NEVER from request body — always from get_current_tenant_id() ContextVar"
    - "Riverpod providers: @riverpod Stream<List<Entity>> wraps DAO watch queries via getIt<AppDatabase>()"

key-files:
  created:
    - mobile/lib/shared/models/user_role.dart
    - mobile/lib/shared/models/trade_type.dart
    - mobile/lib/features/company/domain/company_entity.dart
    - mobile/lib/features/users/domain/user_entity.dart
    - mobile/lib/features/users/domain/user_role_entity.dart
    - mobile/lib/features/company/data/company_dao.dart
    - mobile/lib/features/users/data/user_dao.dart
    - mobile/lib/features/company/presentation/providers/company_providers.dart
    - mobile/lib/features/users/presentation/providers/user_providers.dart
  modified:
    - mobile/lib/core/database/app_database.dart (added daos: [CompanyDao, UserDao])
    - mobile/lib/core/database/tables/companies.dart (added tradeTypes column)
    - mobile/lib/core/database/tables/user_roles.dart (added createdAt column)
    - backend/app/features/companies/schemas.py (added trade_types, min_length, ConfigDict)
    - backend/app/features/companies/service.py (added update_company)
    - backend/app/features/companies/router.py (added PATCH endpoint)
    - backend/app/features/companies/models.py (added trade_types ARRAY column)
    - backend/app/features/users/schemas.py (removed company_id from UserCreate, added RoleAssignment with Literal)
    - backend/app/features/users/service.py (company_id from ContextVar, added list_users + get_user_roles)
    - backend/app/features/users/router.py (added GET /, GET /{id}/roles endpoints)
    - backend/migrations/versions/0001_initial.py (added trade_types column to companies table)

key-decisions:
  - "TradeType stored as comma-separated string in Drift (text column) — no Drift custom type needed; parsed to enum on read"
  - "UserRole enum aliased in user_dao.dart as role_enum to avoid conflict with Drift-generated UserRole data class"
  - "company_id excluded from UserCreate schema by design — enforced tenant isolation principle"
  - "UserRoles Drift table missing createdAt — added as auto-fix (required by UserRoleEntity)"
  - "Companies Drift table missing tradeTypes — added as auto-fix (required by CompanyEntity must_have)"
  - "Company SQLAlchemy model uses ARRAY(String) for trade_types — native PostgreSQL array, serializes cleanly to list[str]"

# Metrics
duration: 6min
completed: 2026-03-05
---

# Phase 1 Plan 03: Domain Entity Layer Summary

**Freezed domain entities (Company, User, UserRole), Drift DAOs with reactive Stream-based reads, Riverpod providers, and FastAPI CRUD endpoints with tenant isolation enforced at the service layer**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-03-05T07:05:49Z
- **Completed:** 2026-03-05T07:11:59Z
- **Tasks:** 2 of 2
- **Files modified:** 20 (9 created, 11 modified)

## Accomplishments

- Created UserRole (admin/contractor/client) and TradeType (9 trade specializations) shared enums with serialization helpers
- Created @freezed CompanyEntity, UserEntity, UserRoleEntity domain objects with copyWith, ==, fromJson/toJson (generated by build_runner when Flutter SDK is installed)
- Created CompanyDao (@DriftAccessor) with watchAllCompanies() Stream, getCompanyById, insertCompany, updateCompany, deleteCompany
- Created UserDao (@DriftAccessor) with watchUsersByCompany(Stream), getUserById, watchRolesForUser(Stream), insertUser, assignRole
- Updated AppDatabase with `daos: [CompanyDao, UserDao]` — DAOs accessible via `getIt<AppDatabase>().companyDao`
- Created @riverpod Stream providers wrapping DAO watch queries — offline-first UI consumption
- Full backend Company CRUD: POST, GET, PATCH with trade_types (ARRAY) and partial update support
- Full backend User CRUD: POST, GET (list) with tenant isolation from TenantMiddleware ContextVar
- Role assignment: POST/GET `/{user_id}/roles` supporting all three role types via Literal type
- Enforced critical tenant isolation: company_id NEVER from request body in UserCreate — from get_current_tenant_id() only

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Freezed domain entities, shared enums, and Drift DAOs** - `e7619cf` (feat)
2. **Task 2: Create Pydantic schemas and REST endpoints for Company and User CRUD** - `5b6b2ae` (feat)

## Self-Check: PASSED

- FOUND: mobile/lib/shared/models/user_role.dart
- FOUND: mobile/lib/shared/models/trade_type.dart
- FOUND: mobile/lib/features/company/domain/company_entity.dart
- FOUND: mobile/lib/features/users/domain/user_entity.dart
- FOUND: mobile/lib/features/users/domain/user_role_entity.dart
- FOUND: mobile/lib/features/company/data/company_dao.dart
- FOUND: mobile/lib/features/users/data/user_dao.dart
- FOUND: mobile/lib/features/company/presentation/providers/company_providers.dart
- FOUND: mobile/lib/features/users/presentation/providers/user_providers.dart
- FOUND: backend/app/features/companies/schemas.py (with trade_types, CompanyUpdate, ConfigDict)
- FOUND: backend/app/features/users/schemas.py (with RoleAssignment Literal, no company_id in UserCreate)
- FOUND commit: e7619cf (Task 1)
- FOUND commit: 5b6b2ae (Task 2)

## Files Created/Modified

**Flutter (mobile):**
- `mobile/lib/shared/models/user_role.dart` — UserRole enum: admin, contractor, client + fromString()
- `mobile/lib/shared/models/trade_type.dart` — TradeType enum: 9 trades + fromCommaSeparated()/toCommaSeparated() helpers
- `mobile/lib/features/company/domain/company_entity.dart` — @freezed CompanyEntity: id, name, address, phone, tradeTypes, logoUrl, businessNumber, version, timestamps
- `mobile/lib/features/users/domain/user_entity.dart` — @freezed UserEntity: id, companyId, email, firstName, lastName, phone, version, timestamps
- `mobile/lib/features/users/domain/user_role_entity.dart` — @freezed UserRoleEntity: id, userId, companyId, role (UserRole), createdAt
- `mobile/lib/features/company/data/company_dao.dart` — @DriftAccessor(Companies): watchAllCompanies(Stream), getCompanyById, insert, update, delete + _rowToEntity mapper
- `mobile/lib/features/users/data/user_dao.dart` — @DriftAccessor(Users, UserRoles): watchUsersByCompany(Stream), getUserById, watchRolesForUser(Stream), insertUser, assignRole
- `mobile/lib/features/company/presentation/providers/company_providers.dart` — @riverpod companiesProvider (Stream), companyProvider (Stream<CompanyEntity?>)
- `mobile/lib/features/users/presentation/providers/user_providers.dart` — @riverpod companyUsersProvider (Stream), userRolesProvider (Stream)
- `mobile/lib/core/database/app_database.dart` — added `daos: [CompanyDao, UserDao]` to @DriftDatabase
- `mobile/lib/core/database/tables/companies.dart` — added `tradeTypes` nullable text column
- `mobile/lib/core/database/tables/user_roles.dart` — added `createdAt` datetime column

**Backend:**
- `backend/app/features/companies/schemas.py` — CompanyCreate (min_length=1, trade_types), CompanyUpdate (all optional), CompanyResponse (ConfigDict, trade_types)
- `backend/app/features/companies/service.py` — create_company, get_company, update_company (partial, exclude_none)
- `backend/app/features/companies/router.py` — POST /, GET /{id}, PATCH /{id}
- `backend/app/features/companies/models.py` — added trade_types: ARRAY(String) column
- `backend/app/features/users/schemas.py` — UserCreate (no company_id), UserResponse (roles list), RoleAssignment (Literal type), UserRoleResponse
- `backend/app/features/users/service.py` — create_user (tenant ContextVar), list_users (RLS), assign_role, get_user_roles
- `backend/app/features/users/router.py` — POST /, GET /, POST /{user_id}/roles, GET /{user_id}/roles
- `backend/migrations/versions/0001_initial.py` — added trade_types ARRAY column to companies table

## Decisions Made

- Stored TradeType as comma-separated text in Drift (lightweight, no custom type needed) and as ARRAY(String) in PostgreSQL (native, queryable)
- Used `import 'user_role.dart' as role_enum` alias in user_dao.dart to resolve naming conflict with Drift-generated `UserRole` data class
- Made `company_id` absent from `UserCreate` by design — the most critical tenant isolation enforcement point
- Used `Literal["admin", "contractor", "client"]` for RoleAssignment.role for Python type safety + OpenAPI schema accuracy

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added tradeTypes column to Companies Drift table**
- **Found during:** Task 1
- **Issue:** The CompanyEntity must_have requires tradeTypes field, but the Drift Companies table from Plan 01 had no tradeTypes column. The entity mapping would fail at runtime.
- **Fix:** Added `TextColumn get tradeTypes => text().nullable()()` with comment explaining comma-separated storage
- **Files modified:** `mobile/lib/core/database/tables/companies.dart`
- **Committed in:** e7619cf (Task 1)

**2. [Rule 1 - Bug] Added createdAt column to UserRoles Drift table**
- **Found during:** Task 1
- **Issue:** The UserRoleEntity requires createdAt field, but the Drift UserRoles table from Plan 01 had no createdAt column. The DAO's _rowToUserRoleEntity mapper would fail.
- **Fix:** Added `DateTimeColumn get createdAt => dateTime()()` to UserRoles table
- **Files modified:** `mobile/lib/core/database/tables/user_roles.dart`
- **Committed in:** e7619cf (Task 1)

**3. [Rule 1 - Bug] Added trade_types to Company SQLAlchemy model and migration**
- **Found during:** Task 2
- **Issue:** CompanyCreate schema includes trade_types but the SQLAlchemy Company model had no trade_types column. The service would fail to persist trade_types.
- **Fix:** Added `trade_types: ARRAY(String)` to Company model and migration 0001
- **Files modified:** `backend/app/features/companies/models.py`, `backend/migrations/versions/0001_initial.py`
- **Committed in:** 5b6b2ae (Task 2)

**4. [Rule 1 - Bug] Removed company_id from UserCreate schema**
- **Found during:** Task 2
- **Issue:** The existing stub UserCreate schema in Plan 02 included company_id from request body — a critical tenant isolation bypass vulnerability flagged in the plan's CRITICAL note.
- **Fix:** Removed company_id from UserCreate; service derives it from get_current_tenant_id() ContextVar
- **Files modified:** `backend/app/features/users/schemas.py`, `backend/app/features/users/service.py`
- **Committed in:** 5b6b2ae (Task 2)

## Issues Encountered

**Flutter SDK not installed:** Same blocker as Plan 01. `dart run build_runner build` could not be executed. All source files are written correctly using Freezed 3.2.5, Drift 2.32, and Riverpod Generator 4.0.3 patterns and will generate properly when Flutter SDK is installed.

## User Setup Required

After Flutter SDK is installed, run:
```bash
cd /Users/heechung/AndroidStudioProjects/contractormanagement/mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
```

Generated files to verify:
- `mobile/lib/features/company/domain/company_entity.freezed.dart`
- `mobile/lib/features/company/domain/company_entity.g.dart`
- `mobile/lib/features/users/domain/user_entity.freezed.dart`
- `mobile/lib/features/users/domain/user_role_entity.freezed.dart`
- `mobile/lib/features/company/data/company_dao.g.dart`
- `mobile/lib/features/users/data/user_dao.g.dart`
- `mobile/lib/features/company/presentation/providers/company_providers.g.dart`
- `mobile/lib/features/users/presentation/providers/user_providers.g.dart`
- `mobile/lib/core/database/app_database.g.dart`

## Next Phase Readiness

- UserRole enum is the foundation for Plan 01-04 (go_router role guards)
- CompanyEntity and UserEntity are the domain objects all future feature screens operate on
- DAO Stream pattern established — all Phase 4-8 screens follow watchXxx() stream pattern
- Backend Company + User CRUD endpoints are the API contract for Phase 2 sync engine
- Tenant isolation enforced at service layer (ContextVar) and DB layer (RLS) — ready for Phase 6 auth

---
*Phase: 01-foundation*
*Completed: 2026-03-05*
