# ContractorHub — Project Rules

## Architecture
- **Backend**: FastAPI + SQLAlchemy async + PostgreSQL with Row Level Security
- **Mobile**: Flutter + Riverpod + Drift + Dio + GetIt
- **Auth**: JWT access tokens (15 min) + refresh token rotation (30 days)
- **Multi-tenant**: company_id in JWT drives RLS via ContextVar + SET LOCAL

## Python / Backend Rules

### N+1 Query Prevention
- NEVER query inside a loop. Use `selectinload()` or `joinedload()` for related data.
- All SQLAlchemy models with foreign keys MUST define `relationship()` with `lazy="raise"` to make accidental lazy loads fail loudly.
- When returning lists with nested data, always eager-load relationships in the query.
- Prefer `selectinload` for one-to-many, `joinedload` for many-to-one.

### SQLAlchemy
- All DB operations use `AsyncSession` via the `get_db` FastAPI dependency (auto-commit/rollback).
- Do NOT call `db.commit()` in service functions — `get_db` handles it.
- Use `db.flush()` when you need generated IDs before commit.
- The `after_begin` event listener in `tenant.py` is synchronous by design (SQLAlchemy sync event API).

### Security
- `JWT_SECRET_KEY` and `DATABASE_URL` MUST come from environment — no hardcoded defaults.
- Passwords: bcrypt via passlib, min 8 chars (Pydantic `Field(min_length=8)`).
- Refresh tokens stored as SHA-256 hashes. Rotation on every use. Family revocation on reuse.
- All data endpoints require `Depends(get_current_user)`. Auth endpoints (`/auth/*`) are public.
- Rate limit auth endpoints via `@limiter.limit()` from slowapi.

### OOP Architecture (Required for All New Features)
- All new models MUST inherit from `BaseModel` (app/core/base_models.py) or `TenantScopedModel`.
- All new services MUST inherit from `BaseService` or `TenantScopedService` (app/core/base_service.py).
- All new repositories MUST inherit from `BaseRepository` or `TenantScopedRepository` (app/core/base_repository.py).
- All new routers MUST use `CRUDRouter` mixin or follow the base router pattern (app/core/base_router.py).
- All new response schemas MUST inherit from `BaseResponseSchema` (app/core/base_schemas.py).
- Standalone service functions are NOT allowed — use class methods.

### FastAPI Patterns
- Use specific exception types over generic `ValueError` where possible.
- Router functions: keep thin — delegate to service layer.
- Schemas: use `model_validate()` for ORM-to-Pydantic conversion.

### Testing
- Test DB uses `contractorhub_test` database. Env vars set in `conftest.py`.
- Fixtures use JWT Bearer tokens (not X-Company-Id headers).
- `clean_tables` truncates ALL tables including `refresh_tokens`.

## Flutter / Mobile Rules

### Dio Interceptors
- Use `QueuedInterceptor` (not `Interceptor`) when async operations are needed in `onRequest`/`onError`. Plain `Interceptor` with `async void` silently breaks the interceptor chain.
- `AuthInterceptor` MUST run before `RetryInterceptor` so 401s refresh before retry logic.
- No `LogInterceptor` in release builds. No body logging even in debug (token leakage risk).

### State Management (Riverpod)
- Use `AsyncNotifier` when `build()` requires async initialization.
- If using sync `Notifier` with fire-and-forget async, document why explicitly.
- Do NOT mix GetIt service locator calls inside Riverpod providers without documenting the tradeoff.

### Type Safety
- NEVER use bare `as` casts on API response data. Use `is` type checks with error handling.
- Use `whereType<T>()` instead of `.map((e) => e as T)` for list filtering.
- Validate response shapes before accessing fields — throw `FormatException` on mismatch.

### Error Handling
- NEVER silently swallow exceptions with empty `catch (_) {}`. At minimum use `debugPrint`.
- DioException handlers must distinguish status codes (401, 409, 422, 5xx).
- Auth errors: return user-friendly messages, never expose backend error details.

### Secure Storage
- Tokens stored via `flutter_secure_storage` (Keychain/Keystore).
- JWT decoded locally (without verification) for offline user/company/roles extraction.
- Clear tokens on logout and failed refresh.

### Android
- `network_security_config.xml`: HTTPS-only except localhost/10.0.2.2 for dev.
- Referenced in `AndroidManifest.xml` via `android:networkSecurityConfig`.

### Navigation
- Use `RouteNames` constants — no magic route strings.
- GoRouter uses ValueNotifier bridge pattern to prevent router rebuilds on auth changes.
- Login/Register/Onboarding are unauthenticated routes; all others require auth.

## General Rules
- Run `ruff check` and `ruff format` before committing Python code.
- Run `dart analyze` before committing Flutter code.
- Prefer editing existing files over creating new ones.
- No hardcoded secrets anywhere — use env vars or secure storage.

## Testing Rules
- Every new service function or endpoint MUST have corresponding tests before merging.
- Backend: integration tests via ASGI client; use existing conftest.py fixtures.
- Flutter: unit tests with mocktail for services; Drift in-memory DB for DAOs; widget tests with ProviderScope overrides for screens.
- Test edge cases: invalid input, missing auth, wrong token types, empty results, soft-deleted records.
- Never mock what you can test with an in-memory database (Drift DAOs, SQLAlchemy with test DB).
- Run `pytest` (backend) and `flutter test` (mobile) before committing.

### E2E Tests (Required for Every New Feature)
- Every new feature MUST include intensive end-to-end tests covering the full user flow before merging.
- E2E tests must exercise the complete path: UI interaction → service/provider → data layer (Drift/API) → response handling → UI update.
- For screens with dialog flows (confirm/cancel, form submission), test both the happy path (correct POST data, success UI) and error path (server errors, snackbar messages).
- Mock network calls at the Dio level (`MockDio` via `MockDioClient.instance`) and verify captured request paths and payloads.
- For data-driven UI, seed realistic Drift data and assert rendering: badges, chips, sort order, empty states.
- E2E tests must cover multi-role flows when applicable (e.g., client submits → admin reviews → job created).
- Minimum coverage per feature: happy path, validation/error handling, edge cases (empty data, max limits), and cross-role visibility.
