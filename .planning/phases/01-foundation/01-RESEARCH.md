# Phase 1: Foundation - Research

**Researched:** 2026-03-04
**Domain:** Flutter project scaffold + FastAPI backend scaffold + PostgreSQL multi-tenant RLS + role-gated navigation
**Confidence:** HIGH (stack choices verified against pub.dev and PyPI; patterns verified against official docs and authoritative sources)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Monorepo: single git repo with `/mobile` (Flutter) and `/backend` (Python/FastAPI) top-level folders
- Flutter app: feature-first architecture — organized by domain (jobs/, scheduling/, clients/), each feature has its own models, screens, providers
- Python backend: domain-driven structure — organized by domain (jobs/, scheduling/, users/), each domain has routes, services, models, schemas
- REST API — standard REST endpoints, no GraphQL; simpler, well-suited for mobile, easier offline sync
- Same app shell with content filtered by role — not separate home screens per role
- Shared bottom navigation tabs across all three roles, content filtered by what each role can access
- A user can have multiple roles (e.g., contractor in one company, admin in another) — multi-role support from day one
- Role-gated route guards control what each role can see and access
- Self-service signup: company admin signs up, creates company profile, starts adding contractors
- Full company profile at signup: company name, address, phone, trade types, logo, business number
- Contractors and clients added via invite (email/SMS) — admin sends invite link, person signs up and joins
- Contractors tagged with one or more trade types (builder, electrician, plumber, HVAC, etc.)
- Docker Compose: one command starts FastAPI + PostgreSQL + Redis in containers
- Seed data script available but optional
- GitHub Actions CI pipeline from day one — run tests on every push
- Strict code quality enforcement: dart analyze + ruff (Python) + pre-commit hooks from the start

### Claude's Discretion
- Bottom tab structure and icons (Claude designs based on feature set)
- Exact directory structure within feature-first and domain-driven patterns
- Docker Compose service configuration details
- CI pipeline configuration specifics
- Seed data composition (which demo entities to create)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INFRA-01 | Multi-tenant company workspace with data isolation per company | PostgreSQL RLS policies + btree_gist extension; SET LOCAL via SQLAlchemy after_begin event; company_id UUID FK on all tenant tables |
| INFRA-02 | Three user roles: company admin, contractor, client | User+Role data models with UUID PKs; multi-role support via junction table; go_router redirect guards keyed on role set |
| INFRA-05 | Flutter mobile app (Android first, iOS second) | Flutter 3.32+ with Drift 2.32 / Riverpod 3.2 / go_router 17.1 / get_it 9.2; Android-first but no stack changes needed for iOS later |
| INFRA-06 | Python backend API (FastAPI) shared across platforms | FastAPI 0.135.1 + SQLAlchemy 2.0.48 async + asyncpg + Alembic 1.18.4; Docker Compose for local dev |
</phase_requirements>

---

## Summary

Phase 1 establishes the two project skeletons (Flutter mobile, FastAPI backend) and wires them together with the two non-negotiable architectural primitives: multi-tenant data isolation enforced at the database layer via PostgreSQL Row Level Security, and role-differentiated navigation enforced in Flutter via go_router route guards. Every subsequent phase builds on these foundations without changing them.

The Flutter scaffold centers on four libraries wired together: Drift (local SQLite, reactive streams), Riverpod 3.x (UI state, provider graph), go_router 17.x (declarative navigation, route guards), and get_it (DI container for infrastructure singletons). Code generation via build_runner is required for Drift table classes, Riverpod providers, and Freezed models. The backend scaffold centers on FastAPI with async SQLAlchemy, PostgreSQL with RLS enabled from migration 0001, and Alembic managing all schema changes. Docker Compose runs the full stack with one command. GitHub Actions CI and pre-commit hooks enforce code quality from the first commit.

The most critical technical decisions to get right in this phase — because they are non-recoverable if retrofitted — are: (1) RLS enabled on every tenant table from migration 0001 with `SET LOCAL` per-transaction, never per-session; (2) version columns on all entities from day one; (3) UUID primary keys everywhere, not integer sequences; (4) the Drift local DB is the source of truth for Flutter reads from the very first screen.

**Primary recommendation:** Establish all four architectural primitives in strict order: Docker + PostgreSQL + RLS schema first, FastAPI tenant middleware second, Drift + Riverpod scaffold third, go_router role guards fourth. Verify tenant isolation with an automated test before moving to Phase 2.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Flutter | 3.32+ | Cross-platform mobile (Android-first) | Official Flutter SDK; single codebase; Android-first priority matches project |
| Dart | 3.8+ | Flutter language | Required by Flutter 3.32+; null-safe, strong typing |
| Drift | 2.32.0 | Local SQLite ORM + reactive streams | Type-safe, code-generated queries; reactive streams native to Riverpod; migration API prevents data loss on upgrades |
| drift_flutter | 0.3.0 | Flutter-specific Drift database opener | Required to open SQLite with platform-correct path on Android/iOS |
| Riverpod | 3.2.1 (flutter_riverpod) | UI state management | Compile-time safe providers; no BuildContext dependency; excellent async/stream handling; works naturally with Drift streams |
| riverpod_generator | 4.0.3 | Riverpod code generation | Required with Riverpod 3.x for `@riverpod` annotations; reduces provider boilerplate |
| go_router | 17.1.0 | Declarative navigation + route guards | Flutter team-maintained; redirect function API for role-based route protection; deep link support |
| get_it | 9.2.1 | Service locator / DI container | Infrastructure singleton registration (AppDatabase, DioClient); decoupled from UI layer |
| FastAPI | 0.135.1 | Python backend REST API | Async-native (ASGI); automatic OpenAPI docs; Pydantic v2 type safety |
| SQLAlchemy | 2.0.48 | ORM + async DB access | Full async support via asyncpg; event listeners for per-transaction RLS context injection |
| Alembic | 1.18.4 | Database schema migrations | `--autogenerate` from SQLAlchemy models; versioned migration scripts; runs on container startup |
| PostgreSQL | 16+ | Primary database | Best-in-class Row Level Security; btree_gist extension for EXCLUDE USING GIST constraints (Phase 3) |
| asyncpg | 0.30.0 | Async PostgreSQL driver | Only production-grade async Postgres driver; required for SQLAlchemy async mode |

### Supporting (Flutter)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| freezed | 3.2.5 | Immutable data classes + sealed unions | All domain entities (Company, User, Role); generates copyWith, ==, toString |
| freezed_annotation | 3.2.5 | Freezed runtime annotations | Required alongside freezed; add to `dependencies` not dev |
| json_serializable | 6.13.0 | JSON de/serialization code gen | API response parsing alongside Freezed models |
| json_annotation | 4.9.0 | json_serializable runtime annotations | Required alongside json_serializable; add to `dependencies` |
| dio | 5.9.2 | HTTP client | All network requests; interceptors for auth token injection and retry |
| build_runner | 2.4.0+ | Code generation runner | Required to generate Drift, Freezed, json_serializable, Riverpod code |
| mocktail | 1.0.4 | Unit test mocking | Mock repositories and services; no codegen required |
| patrol | 4.2.0 | E2E integration testing | E2E tests requiring native OS interaction |

### Supporting (Python Backend)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Pydantic | 2.12.5 | Request/response validation | All API schemas; FastAPI requires it; v2 is Rust-backed (faster serialization) |
| pytest | 9.0.2 | Test framework | All backend tests |
| pytest-asyncio | 0.24.0 | Async test support | Testing async FastAPI endpoints |
| httpx | 0.28.1 | Async HTTP test client | `httpx.AsyncClient` with `ASGITransport` for in-process endpoint testing |
| python-jose | 3.3.0 | JWT decoding | Extract tenant_id from JWT claims in middleware; Phase 1 uses stub, real auth in v2 |
| python-dotenv | 1.0.1 | Environment config | Local dev `.env` file loading |
| uvicorn | 0.32.0 | ASGI server | Run FastAPI in Docker container |
| ruff | 0.11.x | Python linter + formatter | Replaces flake8 + isort + black; single tool, fastest Python linter |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Docker + Docker Compose | Local backend dev environment | Single command: `docker compose up` starts FastAPI + PostgreSQL + Redis |
| build_runner | Flutter code generation | Run after any model/table/provider change: `dart run build_runner build --delete-conflicting-outputs` |
| pre-commit | Git hook framework | Runs dart analyze + ruff on every commit; prevents linting debt accumulation |
| GitHub Actions | CI pipeline | Lint + test on every push and PR; Android APK build on main |

### Installation

**Flutter (pubspec.yaml):**
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^3.2.1
  riverpod_annotation: ^4.0.3
  drift: ^2.32.0
  drift_flutter: ^0.3.0
  go_router: ^17.1.0
  dio: ^5.9.2
  freezed_annotation: ^3.2.5
  json_annotation: ^4.9.0
  get_it: ^9.2.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  riverpod_generator: ^4.0.3
  freezed: ^3.2.5
  json_serializable: ^6.13.0
  build_runner: ^2.4.0
  drift_dev: ^2.32.0
  mocktail: ^1.0.4
  patrol: ^4.2.0
```

**Python Backend (requirements.txt):**
```
fastapi[standard]==0.135.1
sqlalchemy[asyncio]==2.0.48
alembic==1.18.4
pydantic==2.12.5
asyncpg==0.30.0
python-jose[cryptography]==3.3.0
python-dotenv==1.0.1
uvicorn[standard]==0.32.0

# Dev / test
pytest==9.0.2
pytest-asyncio==0.24.0
httpx==0.28.1
ruff>=0.11.0
```

---

## Architecture Patterns

### Recommended Project Structure

**Monorepo root:**
```
contractormanagement/
├── mobile/                  # Flutter project
│   ├── lib/
│   │   ├── core/
│   │   │   ├── database/    # Drift DB class, migrations
│   │   │   ├── network/     # Dio client, interceptors
│   │   │   ├── routing/     # go_router setup, route guards
│   │   │   └── di/          # get_it setup, service registrations
│   │   ├── features/
│   │   │   ├── company/
│   │   │   │   ├── domain/  # Company entity, repo interface
│   │   │   │   ├── data/    # CompanyRepositoryImpl, DAO
│   │   │   │   └── presentation/ # providers, screens, widgets
│   │   │   ├── users/
│   │   │   │   ├── domain/  # User entity, Role entity, repo interface
│   │   │   │   ├── data/
│   │   │   │   └── presentation/
│   │   │   └── auth/        # Stub for v2 auth; role state provider lives here
│   │   └── shared/
│   │       ├── widgets/     # Reusable UI components
│   │       └── models/      # Shared enums (UserRole, TradeType)
│   ├── test/
│   │   ├── unit/
│   │   └── integration/
│   └── pubspec.yaml
├── backend/                 # FastAPI project
│   ├── app/
│   │   ├── main.py          # App factory, middleware registration
│   │   ├── core/
│   │   │   ├── config.py    # Pydantic-settings Settings class
│   │   │   ├── database.py  # SQLAlchemy async engine, session factory
│   │   │   ├── tenant.py    # TenantMiddleware, ContextVar, RLS helper
│   │   │   └── security.py  # JWT decode stub (real auth in v2)
│   │   └── features/
│   │       ├── companies/
│   │       │   ├── router.py
│   │       │   ├── service.py
│   │       │   ├── models.py   # SQLAlchemy ORM models
│   │       │   └── schemas.py  # Pydantic schemas
│   │       └── users/
│   │           ├── router.py
│   │           ├── service.py
│   │           ├── models.py
│   │           └── schemas.py
│   ├── migrations/          # Alembic migration scripts
│   │   ├── env.py
│   │   └── versions/
│   ├── tests/
│   │   ├── unit/
│   │   └── integration/     # Cross-tenant isolation tests live here
│   ├── alembic.ini
│   ├── Dockerfile
│   └── requirements.txt
├── docker-compose.yml
├── .pre-commit-config.yaml
└── .github/
    └── workflows/
        └── ci.yml
```

### Pattern 1: Drift Database Setup with get_it DI

**What:** A single AppDatabase class (Drift) opened with drift_flutter, registered as a singleton in get_it, and provided to Riverpod providers via the get_it instance.

**When to use:** Always — the database is initialized once at app startup and never recreated.

**Example:**
```dart
// lib/core/database/app_database.dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// Phase 1 tables — minimal foundation tables
class Companies extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Users extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get email => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class UserRoles extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get role => text()();  // 'admin' | 'contractor' | 'client'

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Companies, Users, UserRoles])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: stepByStep(
      // Future migrations added here
    ),
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'contractorhub',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}

// lib/core/di/service_locator.dart
import 'package:get_it/get_it.dart';

final getIt = GetIt.instance;

void setupServiceLocator() {
  getIt.registerSingleton<AppDatabase>(AppDatabase());
  // Register other services here
}

// main.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setupServiceLocator();
  runApp(
    ProviderScope(
      child: MyApp(),
    ),
  );
}
```

### Pattern 2: PostgreSQL RLS + SQLAlchemy Async Tenant Context

**What:** A `ContextVar` stores the current tenant's `company_id` per async request. FastAPI middleware sets it from the JWT. A SQLAlchemy `after_begin` event listener calls `SET LOCAL app.current_company_id` on the connection at the start of every transaction.

**When to use:** Every API request that accesses tenant-scoped data.

**Critical detail:** Use `SET LOCAL` (transaction-scoped), never `SET` (session-scoped). With connection pooling, `SET` leaks tenant context to the next user of a pooled connection. `SET LOCAL` is automatically cleared when the transaction ends.

**Example:**
```python
# app/core/tenant.py
from contextvars import ContextVar
from uuid import UUID
from sqlalchemy import text, event
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

# Per-request context variable — automatically isolated per async task
_current_tenant_id: ContextVar[UUID | None] = ContextVar(
    'current_tenant_id', default=None
)

def get_current_tenant_id() -> UUID | None:
    return _current_tenant_id.get()

def set_current_tenant_id(tenant_id: UUID) -> None:
    _current_tenant_id.set(tenant_id)


class TenantMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Phase 1 stub: extract from header (real JWT decode in v2)
        # In production: decode JWT and extract company_id claim
        company_id_str = request.headers.get("X-Company-Id")
        if company_id_str:
            set_current_tenant_id(UUID(company_id_str))
        return await call_next(request)


# SQLAlchemy event: set RLS variable at the start of EVERY transaction
# Must execute on the connection object (SQLAlchemy 2.0.17+ requirement)
@event.listens_for(AsyncSession, "after_begin")
async def receive_after_begin(session, transaction, connection):
    tenant_id = get_current_tenant_id()
    if tenant_id is not None:
        await connection.execute(
            text("SET LOCAL app.current_company_id = :cid"),
            {"cid": str(tenant_id)}
        )
```

```sql
-- In Alembic migration 0001:
-- Enable required extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- Companies table (no tenant isolation — IS the tenant)
CREATE TABLE companies (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR NOT NULL,
    version     INTEGER NOT NULL DEFAULT 1,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Users table — tenant-scoped
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID NOT NULL REFERENCES companies(id),
    email       VARCHAR NOT NULL,
    version     INTEGER NOT NULL DEFAULT 1,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- User roles junction table — one user can have multiple roles
CREATE TABLE user_roles (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id),
    company_id  UUID NOT NULL REFERENCES companies(id),
    role        VARCHAR NOT NULL CHECK (role IN ('admin', 'contractor', 'client')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS on all tenant-scoped tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;
ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_roles FORCE ROW LEVEL SECURITY;

-- RLS policies
CREATE POLICY tenant_isolation ON users
    USING (company_id = current_setting('app.current_company_id', true)::uuid);

CREATE POLICY tenant_isolation ON user_roles
    USING (company_id = current_setting('app.current_company_id', true)::uuid);

-- Indexes for tenant queries (essential — unindexed company_id = full table scan)
CREATE INDEX idx_users_company_id ON users(company_id);
CREATE INDEX idx_user_roles_company_id ON user_roles(company_id);
CREATE INDEX idx_user_roles_user_id ON user_roles(user_id);
```

**Note on `current_setting('app.current_company_id', true)`:** The second argument `true` means "return NULL if the setting doesn't exist" instead of raising an error. Without this, queries without an active tenant context crash rather than returning empty results. During testing with a superuser that bypasses RLS, this prevents errors on tables with the policy defined.

### Pattern 3: go_router Role Guards with Riverpod

**What:** A Riverpod provider exposes the current user's role set. go_router's `redirect` function reads this provider to gate access to role-specific routes. A `ValueNotifier` bridges Riverpod state to go_router's `refreshListenable` so the router re-evaluates guards when the role changes.

**When to use:** All role-gated routes (admin-only screens, contractor-only screens, client-only screens).

**Example:**
```dart
// lib/features/auth/presentation/providers/auth_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_provider.g.dart';

enum UserRole { admin, contractor, client }

@freezed
class AuthState with _$AuthState {
  const factory AuthState.loading() = _Loading;
  const factory AuthState.unauthenticated() = _Unauthenticated;
  const factory AuthState.authenticated({
    required String userId,
    required String companyId,
    required Set<UserRole> roles,
  }) = _Authenticated;
}

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  AuthState build() => const AuthState.loading();

  // Phase 1: stub that sets a default authenticated state for testing
  void setMockUser({required Set<UserRole> roles}) {
    state = AuthState.authenticated(
      userId: 'test-user-id',
      companyId: 'test-company-id',
      roles: roles,
    );
  }
}

// lib/core/routing/app_router.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ValueNotifier bridges Riverpod → go_router's refreshListenable
class AuthStateNotifier extends ValueNotifier<AuthState> {
  AuthStateNotifier(super.value);
}

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = AuthStateNotifier(
    ref.read(authNotifierProvider),
  );

  // Keep notifier in sync with Riverpod state
  ref.listen(authNotifierProvider, (_, next) {
    authNotifier.value = next;
  });

  return GoRouter(
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final authState = authNotifier.value;

      // Loading: show splash
      if (authState is _Loading) return '/splash';

      // Unauthenticated: redirect to onboarding
      if (authState is _Unauthenticated) {
        if (state.matchedLocation == '/splash') return null;
        return '/onboarding';
      }

      final authenticated = authState as _Authenticated;
      final roles = authenticated.roles;
      final path = state.matchedLocation;

      // Admin-only routes
      if (path.startsWith('/admin') && !roles.contains(UserRole.admin)) {
        return '/unauthorized';
      }

      // Contractor-only routes
      if (path.startsWith('/contractor') &&
          !roles.contains(UserRole.contractor)) {
        return '/unauthorized';
      }

      // Client-only routes
      if (path.startsWith('/client') && !roles.contains(UserRole.client)) {
        return '/unauthorized';
      }

      return null; // Allow navigation
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/unauthorized', builder: (_, __) => const UnauthorizedScreen()),
      // Shared shell with bottom nav
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          // Content filtered by role inside each screen
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/jobs', builder: (_, __) => const JobsScreen()),
          GoRoute(path: '/schedule', builder: (_, __) => const ScheduleScreen()),
          // Admin-only
          GoRoute(path: '/admin/team', builder: (_, __) => const TeamManagementScreen()),
          // Contractor-only
          GoRoute(path: '/contractor/availability', builder: (_, __) => const AvailabilityScreen()),
          // Client-only
          GoRoute(path: '/client/portal', builder: (_, __) => const ClientPortalScreen()),
        ],
      ),
    ],
  );
});
```

### Pattern 4: Docker Compose Stack

**What:** A single `docker-compose.yml` at the monorepo root starts all backend services. PostgreSQL starts first with a healthcheck; FastAPI depends on it being healthy; Alembic migrations run on container startup.

**Example:**
```yaml
# docker-compose.yml (at monorepo root)
version: "3.8"

services:
  backend:
    build: ./backend
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgresql+asyncpg://appuser:apppassword@postgres:5432/contractorhub
      REDIS_URL: redis://redis:6379/0
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - ./backend/app:/app/app  # Hot reload in dev
    restart: unless-stopped

  postgres:
    image: postgres:16-alpine
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: apppassword
      POSTGRES_DB: contractorhub
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U appuser -d contractorhub"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres-data:
  redis-data:
```

```dockerfile
# backend/Dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Run migrations then start server
CMD alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### Pattern 5: Alembic RLS Migration (0001_initial)

**What:** The very first Alembic migration creates all foundation tables, enables the btree_gist extension, enables RLS, and creates tenant isolation policies. All subsequent migrations are additive.

**Key rule:** Never disable RLS in a migration. Never use `FORCE ROW LEVEL SECURITY` on the `companies` table itself (it is the tenant root, not a tenant-scoped table).

**Example (migrations/versions/0001_initial.py):**
```python
from alembic import op
import sqlalchemy as sa
from sqlalchemy import text

def upgrade() -> None:
    # Required extensions
    op.execute(text("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""))
    op.execute(text("CREATE EXTENSION IF NOT EXISTS btree_gist"))

    # Companies (tenant root — no RLS needed)
    op.create_table(
        'companies',
        sa.Column('id', sa.UUID, primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('name', sa.String, nullable=False),
        sa.Column('version', sa.Integer, nullable=False, server_default='1'),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.func.now()),
    )

    # Users (tenant-scoped)
    op.create_table(
        'users',
        sa.Column('id', sa.UUID, primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('company_id', sa.UUID, sa.ForeignKey('companies.id'), nullable=False),
        sa.Column('email', sa.String, nullable=False),
        sa.Column('version', sa.Integer, nullable=False, server_default='1'),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('idx_users_company_id', 'users', ['company_id'])

    # User roles junction table (tenant-scoped; supports multiple roles per user)
    op.create_table(
        'user_roles',
        sa.Column('id', sa.UUID, primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('user_id', sa.UUID, sa.ForeignKey('users.id'), nullable=False),
        sa.Column('company_id', sa.UUID, sa.ForeignKey('companies.id'), nullable=False),
        sa.Column('role', sa.String, nullable=False),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("role IN ('admin', 'contractor', 'client')", name='valid_role'),
    )
    op.create_index('idx_user_roles_company_id', 'user_roles', ['company_id'])
    op.create_index('idx_user_roles_user_id', 'user_roles', ['user_id'])

    # Enable RLS on tenant-scoped tables
    op.execute(text("ALTER TABLE users ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE users FORCE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE user_roles FORCE ROW LEVEL SECURITY"))

    # Tenant isolation policies
    op.execute(text("""
        CREATE POLICY tenant_isolation ON users
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """))
    op.execute(text("""
        CREATE POLICY tenant_isolation ON user_roles
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """))


def downgrade() -> None:
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON user_roles"))
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON users"))
    op.drop_table('user_roles')
    op.drop_table('users')
    op.drop_table('companies')
```

### Pattern 6: CI Pipeline (GitHub Actions)

**Example (.github/workflows/ci.yml):**
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  flutter:
    name: Flutter Lint + Test
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: mobile
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.32.0'
          channel: stable
          cache: true
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter analyze
      - run: flutter test

  backend:
    name: Python Lint + Test
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: backend
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: appuser
          POSTGRES_PASSWORD: apppassword
          POSTGRES_DB: contractorhub_test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install -r requirements.txt
      - run: ruff check .
      - run: ruff format --check .
      - run: alembic upgrade head
        env:
          DATABASE_URL: postgresql+asyncpg://appuser:apppassword@localhost:5432/contractorhub_test
      - run: pytest tests/
        env:
          DATABASE_URL: postgresql+asyncpg://appuser:apppassword@localhost:5432/contractorhub_test
```

**Example (.pre-commit-config.yaml):**
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.11.0
    hooks:
      - id: ruff-check
        args: [--fix]
      - id: ruff-format
```

### Anti-Patterns to Avoid

- **RLS via application WHERE clauses only:** Application bugs skip tenant filters; RLS cannot be bypassed.
- **`SET` instead of `SET LOCAL` for tenant context:** `SET` is session-scoped. With connection pooling, the wrong tenant context leaks to the next user of that connection. Always use `SET LOCAL`.
- **`FORCE ROW LEVEL SECURITY` on the companies table:** Companies is the tenant root, not a tenant-scoped table. Applying FORCE RLS here prevents inserts by non-superusers without a matching policy.
- **Accepting `company_id` from the request body/params:** Tenants can pass arbitrary company_ids. Derive `company_id` exclusively from the JWT/session on the server.
- **Integer autoincrement PKs on tenant-scoped resources:** Sequential integers allow tenants to enumerate other tenants' resource IDs (IDOR). Always use UUID v4.
- **`onUpgrade` in Drift that calls `onCreate`:** Drops all tables and recreates them, destroying all unsynced local data. Use `stepByStep()` migrations.
- **Registering AppDatabase as a Riverpod provider:** Drift database is an infrastructure singleton, not UI state. Register with get_it; expose data via Riverpod providers that call DAO methods.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SQLite reactive queries | Custom stream polling | Drift watch queries | Drift streams emit on every table change automatically |
| Type-safe SQL queries | Raw string SQL | Drift code generation | Generated query builders; compile-time errors, not runtime |
| Immutable data models | Manual copyWith/== | Freezed | Generates copyWith, ==, hashCode, toString; prevents mutation bugs |
| JSON parsing boilerplate | Manual fromJson/toJson | json_serializable | Code generation eliminates a whole class of deserialization bugs |
| Route guards | Manual Navigator.pop/push checks | go_router redirect | Redirect is called on every navigation; impossible to bypass accidentally |
| DI container | Inherited widgets for services | get_it | Type-safe service lookup without BuildContext dependency |
| Database migrations | Manual ALTER TABLE in app code | Drift stepByStep + Alembic | Both provide migration safety, test support, and rollback capability |
| Tenant isolation | App-level WHERE clauses | PostgreSQL RLS | RLS is enforced at DB level — cannot be bypassed by application bugs |
| Concurrent booking prevention | Application-level check-then-insert | PostgreSQL EXCLUDE USING GIST | Application checks are not atomic; GIST constraints are |
| UUID generation | Custom random string | `uuid` package (Dart) / `gen_random_uuid()` (Postgres) | RFC 4122 compliance; collision probability essentially zero |

**Key insight:** The three most dangerous things to hand-roll in this stack are tenant isolation (use RLS), conflict prevention (use DB constraints), and Flutter data models (use Freezed + json_serializable). All three have well-tested library solutions that handle the edge cases that custom code consistently misses.

---

## Common Pitfalls

### Pitfall 1: SET vs SET LOCAL — Tenant Context Leakage

**What goes wrong:** Using `SET app.current_company_id = 'X'` (session-level) instead of `SET LOCAL app.current_company_id = 'X'` (transaction-level). When asyncpg reuses a pooled connection, the previous tenant's company_id is still set. Tenant B sees Tenant A's data.

**Why it happens:** `SET` is session-scoped and persists until explicitly reset or connection closes. `SET LOCAL` is automatically cleared at transaction end.

**How to avoid:** Always `SET LOCAL` in the `after_begin` event listener. Never `SET`. No exceptions.

**Warning signs:** Using `SET` anywhere in the tenant context code; session-level connection configuration for tenant routing.

### Pitfall 2: Alembic Migration User Lacks Extension Privileges

**What goes wrong:** `CREATE EXTENSION btree_gist` in migration 0001 fails with `ERROR: permission denied to create extension "btree_gist"`. The migration user (appuser) is not a superuser and cannot install extensions.

**Why it happens:** PostgreSQL extension creation requires superuser privileges. The application database user should not be a superuser, but migrations often run as the application user.

**How to avoid:** Pre-install extensions in the PostgreSQL container initialization script (`docker-entrypoint-initdb.d/`) as the postgres superuser. Or run a separate init migration under a superuser-privileged user. In Docker Compose, use an init SQL script:

```sql
-- docker/init.sql (mounted to /docker-entrypoint-initdb.d/)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS btree_gist;
```

**Warning signs:** Migration fails on first `docker compose up`; CI fails on postgres extension creation.

### Pitfall 3: `current_setting` Without NULL-Safe Second Argument

**What goes wrong:** RLS policy uses `current_setting('app.current_company_id')::uuid`. A superuser session (e.g., Alembic migrations, DBA tooling) doesn't have this setting. The function raises: `ERROR: unrecognized configuration parameter "app.current_company_id"`.

**Why it happens:** `current_setting(name)` throws an error if the setting is undefined. `current_setting(name, true)` returns NULL instead.

**How to avoid:** Always write policies as `current_setting('app.current_company_id', true)::uuid`. This returns NULL when no tenant is set, which causes the `USING` clause to evaluate to NULL (not true), so no rows match — which is the correct behavior for unscoped sessions.

**Warning signs:** Alembic migrations fail with `unrecognized configuration parameter` errors; DBA queries fail on tenant-scoped tables.

### Pitfall 4: go_router Router Rebuilt on Every State Change

**What goes wrong:** The router is declared as a Riverpod `Provider` that directly `watch`es the auth provider. Every auth state change rebuilds the entire GoRouter, which discards navigation history and causes the app to reset to the initial route.

**Why it happens:** `GoRouter` is not a const/stateless object. Rebuilding it destroys its internal state, including the navigation stack.

**How to avoid:** Use the `ValueNotifier` bridge pattern. The GoRouter is created once; the `refreshListenable` (`ValueNotifier`) is updated when auth changes, which triggers `redirect` re-evaluation without rebuilding the router.

**Warning signs:** App navigates back to splash/home screen whenever the user's role changes; navigation history lost on re-authentication.

### Pitfall 5: Drift UUID Primary Key with customConstraint Conflicts

**What goes wrong:** Defining a UUID primary key as `text().customConstraint('NOT NULL PRIMARY KEY')()` causes `table has more than one primary key` error because Drift already adds a primary key via the `primaryKey` override.

**Why it happens:** Drift's `customConstraint` appends raw SQL to the column definition. If `PRIMARY KEY` appears in customConstraint AND in the table's `primaryKey` getter, SQLite gets two PRIMARY KEY declarations.

**How to avoid:** Use `text().clientDefault(() => const Uuid().v4())()` for the column and override `Set<Column> get primaryKey => {id}` at the table level. Never combine `customConstraint('PRIMARY KEY')` with the `primaryKey` override.

**Warning signs:** SQLite error `table has more than one primary key` on app startup; build_runner warnings about constraint conflicts.

### Pitfall 6: Drift Code Gen Not Run After Table Changes

**What goes wrong:** Developer adds a new column to a Drift table, runs the app, and gets runtime errors because the generated `*.g.dart` file is stale and doesn't reflect the new column.

**Why it happens:** Drift requires code generation — the generated code must be re-run every time the table definition changes. This is non-obvious to developers new to code generation.

**How to avoid:** Always run `dart run build_runner build --delete-conflicting-outputs` after any Drift table change. In CI, fail the build if generated files are stale.

**Warning signs:** Runtime `NoSuchMethodError` on table columns; compile errors referencing missing generated methods.

### Pitfall 7: Flutter Reads Blocking on HTTP Instead of Local DB

**What goes wrong:** A screen uses `FutureProvider` to call the API directly and awaits the response before rendering. Offline behavior is broken from day one.

**Why it happens:** The online-first pattern is the default mental model. It is easier to write `ref.watch(getFutureFromApi())` than to set up a Drift stream and sync it.

**How to avoid:** All Flutter reads must come from `StreamProvider` backed by a Drift watch query. The first screen that reads from an API directly — rather than from local Drift — is a bug, not a feature.

**Warning signs:** Any `FutureProvider` that calls `dio.get(...)` and returns data directly to the UI; absence of a Drift database in the project at the end of Phase 1.

---

## Code Examples

### Verified: Drift UUID Primary Key Pattern

```dart
// Source: pub.dev/packages/drift + GitHub issue #3612
class Companies extends Table {
  // UUID via text column with clientDefault — correct approach
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};  // NEVER use customConstraint('PRIMARY KEY')
}
```

### Verified: SQLAlchemy after_begin with AsyncSession (2.0.17+)

```python
# Source: github.com/sqlalchemy/sqlalchemy/discussions/10469
# CRITICAL: execute on the connection object, not the session
@event.listens_for(AsyncSession, "after_begin")
async def receive_after_begin(session, transaction, connection):
    tenant_id = get_current_tenant_id()
    if tenant_id is not None:
        await connection.execute(
            text("SET LOCAL app.current_company_id = :cid"),
            {"cid": str(tenant_id)}
        )
```

### Verified: PostgreSQL RLS Tenant Isolation Test Pattern

```python
# Proves Tenant A cannot read Tenant B's data
async def test_tenant_isolation(db_session_tenant_a, db_session_tenant_b):
    # Create a user for tenant B using tenant B's session
    tenant_b_user = User(company_id=TENANT_B_ID, email="b@example.com")
    db_session_tenant_b.add(tenant_b_user)
    await db_session_tenant_b.commit()

    # Attempt to read tenant B's user using tenant A's session
    # RLS should make this return empty — not 403/404, just no rows
    result = await db_session_tenant_a.execute(
        select(User).where(User.id == tenant_b_user.id)
    )
    rows = result.scalars().all()
    assert len(rows) == 0, "Tenant A should not be able to see Tenant B's user"
```

### Verified: go_router + Riverpod refreshListenable Bridge

```dart
// Source: github.com/lucavenir/go_router_riverpod
// Bridge: keeps GoRouter refresh in sync with Riverpod without rebuilding router
final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ValueNotifier<AuthState>(
    ref.read(authNotifierProvider),
  );
  ref.listen(authNotifierProvider, (_, next) {
    authNotifier.value = next;
  });

  return GoRouter(
    refreshListenable: authNotifier,
    redirect: (context, state) { /* role check logic */ },
    routes: [ /* routes */ ],
  );
});
```

### Verified: Drift stepByStep Migration

```dart
// Source: drift.simonbinder.eu/migrations/step_by_step/
@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) async => await m.createAll(),
  onUpgrade: stepByStep(
    from1To2: (m, schema) async {
      // Add column to users table in schema v2
      await m.addColumn(schema.users, schema.users.phoneNumber);
    },
    from2To3: (m, schema) async {
      // Example future migration
      await m.createTable(schema.contractorProfiles);
    },
  ),
  beforeOpen: (details) async {
    await customStatement('PRAGMA foreign_keys = ON');
  },
);
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Provider (Flutter) | Riverpod 3.x | 2023+ (Provider officially superseded) | No BuildContext dependency; compile-time safety |
| BLoC for simple state | Riverpod `@riverpod` generator | 2024 | Less boilerplate; same testability |
| sqflite with raw SQL strings | Drift 2.x with code generation | Ongoing (Drift 2.32 current) | Type-safe queries; migration API; reactive streams |
| `flutter_driver` E2E tests | `patrol` + `integration_test` | 2022+ | Native OS dialog handling; required for permissions |
| psycopg2 sync driver | asyncpg via SQLAlchemy asyncio | 2021+ (FastAPI adoption) | Non-blocking; essential for async FastAPI performance |
| SQLAlchemy 1.x style | SQLAlchemy 2.0 fully async | 2023 | No legacy sync/async mixing; cleaner session lifecycle |
| after_begin on Session (pre-2.0.17) | after_begin on Connection object | SQLAlchemy 2.0.17 | Stricter state validation; must execute SQL on connection |

**Deprecated/outdated:**
- `psycopg2`: Synchronous; blocks async event loop in FastAPI. Never use in new async FastAPI projects.
- `Provider` package: Superseded by Riverpod by the same author. No reason to start new Flutter projects with Provider.
- `flutter_driver`: Replaced by `integration_test` + `patrol`. Do not use.
- `Hive` v2: Effectively unmaintained (last release 2022). Use Drift.
- `GetX`: Community moving away; bundles routing + state + DI in ways that make testing difficult.

---

## Open Questions

1. **Phase 1 auth stub approach**
   - What we know: v2 adds real auth (email/password, OAuth). Phase 1 needs a usable auth stub for testing role guards and tenant context.
   - What's unclear: Whether Phase 1 should use a hardcoded header (`X-Company-Id`) or a minimal JWT stub that downstream phases can swap out cleanly.
   - Recommendation: Use a hardcoded JWT stub in Phase 1 that already uses the `python-jose` decode path, so Phase 2+ only needs to wire in real token issuance, not change the decode logic.

2. **Database user permissions for Alembic vs runtime**
   - What we know: Alembic may need superuser privileges for extension creation; the runtime FastAPI user should not be a superuser.
   - What's unclear: Whether Docker Compose should use two different Postgres users (migration user + runtime user) in Phase 1.
   - Recommendation: Use a Docker init SQL script to install extensions as the postgres superuser at container creation time, so the Alembic user never needs superuser rights.

3. **Bottom navigation tab structure**
   - What we know: Three roles share one app shell; Claude designs tab structure.
   - What's unclear: How many tabs and which are conditionally visible per role vs. always visible.
   - Recommendation: Four shared tabs (Home, Jobs, Schedule, Profile) where tab content is role-filtered. Conditionally render a fifth Admin tab only for admin role users.

---

## Sources

### Primary (HIGH confidence)
- [drift.simonbinder.eu/setup/](https://drift.simonbinder.eu/setup/) — Drift 2.32 setup, database class, drift_flutter, code generation
- [drift.simonbinder.eu/migrations/step_by_step/](https://drift.simonbinder.eu/migrations/step_by_step/) — stepByStep migration pattern
- [pub.dev/packages/drift](https://pub.dev/packages/drift) — Version 2.32.0 confirmed
- [pub.dev/packages/drift_flutter](https://pub.dev/packages/drift_flutter) — Version 0.3.0 confirmed
- [pub.dev/packages/go_router](https://pub.dev/packages/go_router) — Version 17.1.0 confirmed
- [pub.dev/packages/flutter_riverpod](https://pub.dev/packages/flutter_riverpod) — Version 3.2.1 confirmed
- [pub.dev/packages/get_it](https://pub.dev/packages/get_it) — Version 9.2.1 confirmed
- [github.com/sqlalchemy/sqlalchemy/discussions/10469](https://github.com/sqlalchemy/sqlalchemy/discussions/10469) — SQLAlchemy 2.0.17+ after_begin event on Connection, not Session
- [github.com/simolus3/drift/issues/3612](https://github.com/simolus3/drift/issues/3612) — UUID primary key in Drift (avoid customConstraint + primaryKey combo)

### Secondary (MEDIUM confidence)
- [github.com/lucavenir/go_router_riverpod](https://github.com/lucavenir/go_router_riverpod) — ValueNotifier bridge pattern for go_router + Riverpod
- [dinkomarinac.dev/guarding-routes-in-flutter-with-gorouter-and-riverpod](https://dinkomarinac.dev/guarding-routes-in-flutter-with-gorouter-and-riverpod) — Role-based redirect pattern
- [oneuptime.com — FastAPI + PostgreSQL + Celery + Redis docker-compose (2026-02-08)](https://oneuptime.com/blog/post/2026-02-08-how-to-set-up-a-fastapi-postgresql-celery-stack-with-docker-compose/view) — Docker Compose healthchecks, depends_on conditions
- [github.com/astral-sh/ruff-pre-commit](https://github.com/astral-sh/ruff-pre-commit) — ruff-check + ruff-format hooks
- [apparencekit.dev/blog/flutter-riverpod-gorouter-redirect/](https://apparencekit.dev/blog/flutter-riverpod-gorouter-redirect/) — GoRouter redirect patterns with Riverpod

### Tertiary (LOW confidence — flag for validation)
- FastAPI multi-tenancy ContextVar pattern — multiple sources agree on the pattern; specific SQLAlchemy async after_begin interaction verified at HIGH via GitHub discussion above

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all versions verified against pub.dev and PyPI via STACK.md (2026-03-04)
- Architecture: HIGH — Drift setup verified against official docs; SQLAlchemy after_begin pattern verified against GitHub maintainer response; RLS SQL verified against PostgreSQL docs via ARCHITECTURE.md
- Pitfalls: HIGH — SET vs SET LOCAL, UUID constraint, and `current_setting` NULL-safety are all verified against official source material; Drift migration pitfall verified against official migration docs
- Docker Compose: MEDIUM-HIGH — pattern verified against a 2026-02-08 article; healthcheck syntax is standard Docker Compose v3 spec

**Research date:** 2026-03-04
**Valid until:** 2026-04-04 (30 days for stable stack; Drift and Riverpod versions may patch-release sooner)
