# Stack Research

**Domain:** Contractor management SaaS — Flutter mobile + Python backend
**Researched:** 2026-03-04
**Confidence:** HIGH (all versions verified against pub.dev and PyPI as of research date)

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Flutter | 3.32+ (SDK) | Cross-platform mobile app (Android + iOS) | Official Flutter recommendation; single codebase, mature offline support, first-class testing tooling. Android-first aligns with priority order. |
| Dart | 3.8+ | Flutter language | Required by Flutter; null-safe by default, strong typing reduces runtime bugs in offline sync logic |
| FastAPI | 0.135.1 | Python backend API | Async-native (ASGI), automatic OpenAPI docs, excellent type safety via Pydantic, lowest boilerplate for REST APIs in Python. Fastest path to mobile-compatible JSON API. |
| PostgreSQL | 16+ | Primary database | Best-in-class Row Level Security for tenant isolation. RLS enforces multi-tenant data separation at the database layer, not the app layer — critical for SaaS. |
| SQLAlchemy | 2.0.48 | ORM + async DB access | SQLAlchemy 2.0 has full async support via `asyncpg`. Native async is required when paired with FastAPI's async endpoints to avoid thread pool bottlenecks. |
| Alembic | 1.18.4 | Database schema migrations | Standard migration tool for SQLAlchemy. `--autogenerate` compares Python models to actual DB schema — essential for evolving a multi-tenant schema safely. |
| Drift | 2.32.0 | Local SQLite ORM for Flutter | Type-safe, reactive, code-generated SQL queries. Supports background isolates, migration APIs, and streaming queries — the right fit for offline-first where SQLite is the source of truth. |
| Riverpod | 3.2.1 | Flutter state management | Compile-time safe providers, no BuildContext dependency, excellent testing support, and tight offline-first integration. Preferred over BLoC for this project due to lower boilerplate and native async handling. |

### Supporting Libraries — Flutter

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| drift_flutter | 0.3.0 | Flutter-specific Drift integration | Every screen — opens the SQLite database with platform-appropriate settings for Android/iOS |
| go_router | 17.1.0 | Declarative navigation | Navigation across all three role-specific UX flows (admin, contractor, client). Handles deep linking and role-based route guards. |
| dio | 5.9.2 | HTTP client for API sync | All network requests. Use interceptors for: auth token injection, offline queue detection, and request retry logic. Prefer over base `http` package for interceptors alone. |
| connectivity_plus | 7.0.0 | Network state detection | Detecting online/offline transitions to gate sync operations. Flutter Favorite package, cross-platform. |
| workmanager | 0.9.0+3 | Background sync scheduling | Scheduling periodic background sync when app is not active. Only option that works on both Android and iOS for background Dart execution. |
| freezed | 3.2.5 | Immutable data classes + unions | All domain models (Job, Contractor, Client, Schedule). Generates `copyWith`, `==`, `toString`, and sealed class patterns. Eliminates a major class of mutation bugs in offline state. |
| json_serializable | 6.13.0 | JSON de/serialization code gen | API response parsing. Use alongside `freezed` — `freezed` generates the model, `json_serializable` generates `fromJson`/`toJson`. |
| riverpod_generator | 4.0.3 | Riverpod code generation | Reduces provider boilerplate via `@riverpod` annotations. Required with Riverpod 3.x for idiomatic usage. |
| get_it | 9.2.1 | Service locator / DI container | Registering singletons (DioClient, DatabaseService, SyncEngine). Use alongside Riverpod: Riverpod for UI state, get_it for infrastructure services. |
| mocktail | 1.0.4 | Unit test mocking | Mocking repositories and services in unit tests. Preferred over `mockito` — no code generation required, works natively with null safety. |
| patrol | 4.2.0 | E2E / integration testing | End-to-end tests that interact with native OS dialogs (permissions, notifications). Required for E2E on Android — flutter's built-in `integration_test` cannot handle native dialogs. |

### Supporting Libraries — Python Backend

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Pydantic | 2.12.5 | Request/response validation | All API schemas. FastAPI requires it. v2 is Rust-backed — JSON serialization is 2x faster, critical for large schedule payloads. |
| asyncpg | 0.30+ | Async PostgreSQL driver | The only production-grade async Postgres driver. Required for SQLAlchemy async mode — do not use `psycopg2` (synchronous, blocks the event loop). |
| pytest | 9.0.2 | Test framework | All backend tests. `pytest-asyncio` extends it for testing async FastAPI endpoints. |
| httpx | 0.28.1 | Async HTTP test client | Testing FastAPI endpoints. `httpx.AsyncClient` with `ASGITransport` lets you test the ASGI app without running a real server. |
| Celery | 5.4+ | Async task queue | Background jobs: sync conflict resolution batches, scheduled job reminders, availability recalculation after edits. Use with Redis as broker. |
| Redis | 7.x (server) | Message broker + cache | Celery broker and result backend. Also useful for caching scheduling computations (availability windows, conflict checks). |
| python-jose | 3.3+ | JWT handling | Tenant context extraction from JWT claims. Each request carries `tenant_id` in JWT — FastAPI dependency extracts and validates it before any DB access. |
| python-dotenv | 1.0+ | Environment config | Local dev environment variables. Use `pydantic-settings` in production for structured config validation. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Docker + Docker Compose | Local backend dev environment | Run PostgreSQL, Redis, FastAPI, and Celery worker together. Eliminates "works on my machine" for backend. |
| Alembic | Schema migrations | `alembic revision --autogenerate -m "description"` to generate migrations from SQLAlchemy model changes. Run `alembic upgrade head` on container start. |
| build_runner | Flutter code generation | Required for Drift, freezed, json_serializable, and riverpod_generator. Run `dart run build_runner build --delete-conflicting-outputs` after model changes. |
| GitHub Actions | CI/CD | Lint + test on PR. Android APK build on `main` push. Use Fastlane for Play Store deployment. |
| Fastlane | Android release automation | Automates signing, versioning, and Google Play internal track uploads from GitHub Actions. |

---

## Installation

### Flutter (pubspec.yaml)

```yaml
dependencies:
  flutter_riverpod: ^3.2.1
  riverpod_annotation: ^4.0.3
  drift: ^2.32.0
  drift_flutter: ^0.3.0
  go_router: ^17.1.0
  dio: ^5.9.2
  connectivity_plus: ^7.0.0
  workmanager: ^0.9.0+3
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
  mocktail: ^1.0.4
  patrol: ^4.2.0
```

### Python Backend (requirements.txt)

```
fastapi[standard]==0.135.1
sqlalchemy[asyncio]==2.0.48
alembic==1.18.4
pydantic==2.12.5
asyncpg==0.30.0
celery[redis]==5.4.0
redis==5.2.0
python-jose[cryptography]==3.3.0
python-dotenv==1.0.1
uvicorn[standard]==0.32.0

# Dev / test
pytest==9.0.2
pytest-asyncio==0.24.0
httpx==0.28.1
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| FastAPI | Django REST Framework | If team has deep Django expertise, or admin UI (Django admin) is a high priority early on |
| Riverpod | BLoC | If the team is enterprise-scale (10+ Flutter devs) and strict event/state separation is a compliance requirement |
| Drift | ObjectBox | If write performance is the dominant concern (ObjectBox is faster for high-frequency writes); Drift has better SQL query expressiveness |
| Drift (custom sync) | PowerSync | If budget allows for a managed sync service (~$49+/mo) and you want to skip building the sync engine entirely. PowerSync syncs Postgres to SQLite automatically. Evaluate after MVP. |
| PostgreSQL RLS | Schema-per-tenant | Schema-per-tenant is stronger isolation but dramatically more complex to operate. RLS is the right starting point for a SaaS with shared infra. |
| Celery + Redis | ARQ | ARQ is pure-async and simpler, but has smaller community. Use ARQ if the team is async-first Python and Celery's synchronous worker model feels awkward. |
| mocktail | mockito | Use mockito if the team prefers generated mocks and is already running build_runner for other packages |
| patrol | integration_test (built-in) | Use built-in integration_test if E2E tests will never need native OS interaction (permissions, notifications). Unlikely for this app. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Provider (Flutter) | Provider is officially superseded. Riverpod is by the same author but fixes Provider's fundamental design issues (context dependency, rebuild scope, testability). No reason to start new projects with Provider. | Riverpod 3.x |
| GetX | GetX bundles routing, state, and DI into one opinionated framework that short-circuits Flutter's widget tree. Makes testing difficult and creates tight coupling. The community is moving away from it. | Riverpod + go_router + get_it separately |
| Hive | Hive v2 is effectively unmaintained (last release 2022). Hive v3 (Isar successor) is not stable. For structured relational data (jobs, contractors, schedules), SQLite with Drift is dramatically more capable. | Drift |
| SQLite directly (without Drift) | Raw SQLite (via sqflite) means no type safety, no migration framework, no streaming queries. Every SQL string is a latent bug. Drift generates type-safe query code from your schema. | Drift |
| psycopg2 (synchronous) | psycopg2 blocks the asyncio event loop. In an async FastAPI app, one slow DB query blocks all concurrent requests. FastAPI's performance advantage disappears. | asyncpg via SQLAlchemy async |
| Django ORM (in async FastAPI) | Django ORM is not async-native. Using it with FastAPI requires `sync_to_async` wrappers, adding complexity without benefit. If using Django, use DRF. If using FastAPI, use SQLAlchemy async. | SQLAlchemy 2.0 async |
| SQLite on the backend | SQLite does not support concurrent writes and lacks the RLS capabilities needed for multi-tenant isolation. PostgreSQL is the only appropriate choice here. | PostgreSQL |
| Flutter Driver (old) | flutter_driver is the deprecated E2E framework. `integration_test` replaced it for Flutter tests, and Patrol extends integration_test for native interaction. Flutter Driver should not appear in new code. | patrol + integration_test |
| Separate database per tenant (at launch) | Correct isolation model but operationally catastrophic at scale. Running 100 tenants means 100 databases, 100 migration runs, 100 connection pools. Use PostgreSQL RLS instead. Revisit at 1000+ tenants if compliance demands it. | PostgreSQL RLS in shared DB |

---

## Stack Patterns by Variant

**If offline sync needs are simple (append-only job logs, no conflict resolution):**
- Skip Celery + Redis
- Use FastAPI BackgroundTasks for lightweight async operations
- Still use Drift + workmanager on client side

**If scheduling engine becomes computationally heavy:**
- Extract scheduling logic into a Celery task
- Cache availability windows in Redis with TTL
- Scheduling results should be pre-computed and stored, not calculated on request

**If the team decides to use PowerSync instead of custom sync:**
- Remove workmanager, Celery, and custom sync queue logic
- PowerSync handles Postgres-to-SQLite bidirectional sync automatically
- Keep Drift as the local database layer (PowerSync's Flutter SDK builds on Drift)
- Cost: ~$49+/month for managed plan; self-host option available

**If iOS becomes equal priority to Android immediately:**
- No stack changes required — Flutter and workmanager both support iOS
- iOS background execution is more restricted than Android; document task constraints early
- patrol supports both platforms equally

---

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| flutter_riverpod 3.2.1 | Dart 3.4+, Flutter 3.22+ | Riverpod 3.x requires Dart 3.x |
| drift 2.32.0 | Dart 3.x, drift_flutter 0.3.0 | Use drift_flutter for the Flutter-specific database opener |
| freezed 3.2.5 | Dart 3.x, build_runner 2.4+ | Works alongside json_serializable in the same model file |
| FastAPI 0.135.1 | Pydantic 2.x, Python 3.9+ | FastAPI no longer supports Pydantic v1 |
| SQLAlchemy 2.0.48 | asyncpg 0.29+, Alembic 1.x | Use `sqlalchemy[asyncio]` install target to pull greenlet |
| patrol 4.2.0 | Flutter 3.22+, Android SDK 21+ | Requires native configuration in android/ and ios/ project folders |

---

## Sources

- pub.dev/packages/flutter_riverpod — Version 3.2.1 verified (HIGH confidence)
- pub.dev/packages/drift — Version 2.32.0 verified (HIGH confidence)
- pub.dev/packages/drift_flutter — Version 0.3.0 verified (HIGH confidence)
- pub.dev/packages/go_router — Version 17.1.0 verified (HIGH confidence)
- pub.dev/packages/dio — Version 5.9.2 verified (HIGH confidence)
- pub.dev/packages/connectivity_plus — Version 7.0.0 verified (HIGH confidence)
- pub.dev/packages/workmanager — Version 0.9.0+3 verified (HIGH confidence)
- pub.dev/packages/freezed — Version 3.2.5 verified (HIGH confidence)
- pub.dev/packages/json_serializable — Version 6.13.0 verified (HIGH confidence)
- pub.dev/packages/riverpod_generator — Version 4.0.3 verified (HIGH confidence)
- pub.dev/packages/get_it — Version 9.2.1 verified (HIGH confidence)
- pub.dev/packages/mocktail — Version 1.0.4 verified (HIGH confidence)
- pub.dev/packages/patrol — Version 4.2.0 verified (HIGH confidence)
- pypi.org/project/fastapi — Version 0.135.1 verified (HIGH confidence)
- pypi.org/project/sqlalchemy — Version 2.0.48 verified (HIGH confidence)
- pypi.org/project/alembic — Version 1.18.4 verified (HIGH confidence)
- pypi.org/project/pydantic — Version 2.12.5 verified (HIGH confidence)
- pypi.org/project/pytest — Version 9.0.2 verified (HIGH confidence)
- pypi.org/project/httpx — Version 0.28.1 verified (HIGH confidence)
- docs.flutter.dev/app-architecture/design-patterns/offline-first — Offline-first pattern (HIGH confidence)
- docs.powersync.com/client-sdks/reference/flutter — PowerSync Flutter SDK (MEDIUM confidence)
- medium.com/@koushiksathish3/multi-tenant-architecture-with-fastapi — FastAPI multi-tenancy patterns (MEDIUM confidence)
- dinkomarinac.dev/blog/building-local-first-flutter-apps-with-riverpod-drift-and-powersync — Riverpod + Drift integration pattern (MEDIUM confidence)
- fastapi.tiangolo.com/advanced/async-tests — Async testing with httpx (HIGH confidence)

---

*Stack research for: ContractorHub — Contractor Management SaaS (Flutter + FastAPI)*
*Researched: 2026-03-04*
