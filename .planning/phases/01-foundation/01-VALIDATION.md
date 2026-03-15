# Phase 1: Foundation -- Nyquist Validation Map

**Phase:** 1 -- Foundation
**Requirements:** INFRA-01, INFRA-02, INFRA-05, INFRA-06
**nyquist_compliant:** true
**Validated:** 2026-03-14

---

## Requirement-to-Test Verification Map

### INFRA-01: Multi-tenant company workspace with data isolation per company

| Task | Behavior | Test File | Test Type | Automated Command | Status |
|------|----------|-----------|-----------|-------------------|--------|
| 01-02 | RLS policies created on users and user_roles tables via Alembic migration | `backend/tests/integration/test_tenant_isolation.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_tenant_isolation.py -v` | COVERED |
| 01-02 | TenantMiddleware sets ContextVar from X-Company-Id header; SET LOCAL injects tenant_id per transaction | `backend/tests/integration/test_tenant_isolation.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_tenant_isolation.py -v` | COVERED |
| 01-03 | Company CRUD endpoint (POST, GET, PATCH) validates tenant scope via middleware | `backend/tests/integration/test_company_endpoints.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_company_endpoints.py -v` | COVERED |
| 01-03 | User CRUD endpoint derives company_id from ContextVar, never from request body | `backend/tests/integration/test_user_endpoints.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_user_endpoints.py -v` | COVERED |
| 01-05 | Tenant A cannot read Tenant B's data through any API endpoint | `backend/tests/integration/test_tenant_isolation.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_tenant_isolation.py -v` | COVERED |
| 01-05 | Tenant A cannot write to Tenant B's data | `backend/tests/integration/test_tenant_isolation.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_tenant_isolation.py -v` | COVERED |
| 01-05 | No tenant header returns empty results (safe default) | `backend/tests/integration/test_tenant_isolation.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_tenant_isolation.py -v` | COVERED |

### INFRA-02: Three user roles -- company admin, contractor, client

| Task | Behavior | Test File | Test Type | Automated Command | Status |
|------|----------|-----------|-----------|-------------------|--------|
| 01-03 | UserRole enum has admin, contractor, client values | `mobile/test/unit/features/auth/auth_provider_test.dart` | Unit | `cd mobile && flutter test test/unit/features/auth/auth_provider_test.dart` | COVERED |
| 01-03 | Role assignment endpoint supports all three role types | `backend/tests/integration/test_role_endpoints.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_role_endpoints.py -v` | COVERED |
| 01-03 | Invalid role type is rejected with 422 | `backend/tests/integration/test_role_endpoints.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_role_endpoints.py -v` | COVERED |
| 01-04 | Admin role can access /admin/team route | `mobile/test/unit/core/routing/app_router_test.dart` | Widget | `cd mobile && flutter test test/unit/core/routing/app_router_test.dart` | COVERED |
| 01-04 | Contractor role accessing /admin/team is redirected to /unauthorized | `mobile/test/unit/core/routing/app_router_test.dart` | Widget | `cd mobile && flutter test test/unit/core/routing/app_router_test.dart` | COVERED |
| 01-04 | Client role accessing /contractor routes is redirected to /unauthorized | `mobile/test/unit/core/routing/app_router_test.dart` | Widget | `cd mobile && flutter test test/unit/core/routing/app_router_test.dart` | COVERED |
| 01-04 | Multi-role user can access routes for all assigned roles | `mobile/test/unit/core/routing/app_router_test.dart` | Widget | `cd mobile && flutter test test/unit/core/routing/app_router_test.dart` | COVERED |
| 01-04 | Unauthenticated user redirected to /onboarding | `mobile/test/unit/core/routing/app_router_test.dart` | Widget | `cd mobile && flutter test test/unit/core/routing/app_router_test.dart` | COVERED |
| 01-05 | All three role types can be assigned and retrieved via API | `backend/tests/integration/test_role_endpoints.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_role_endpoints.py -v` | COVERED |

### INFRA-05: Flutter mobile app (Android first, iOS second)

| Task | Behavior | Test File | Test Type | Automated Command | Status |
|------|----------|-----------|-----------|-------------------|--------|
| 01-01 | Drift local database opens and creates tables | `mobile/test/unit/features/company/company_dao_test.dart` | Unit | `cd mobile && flutter test test/unit/features/company/company_dao_test.dart` | COVERED |
| 01-01 | get_it service locator registers AppDatabase singleton | `mobile/test/e2e/phase_1_auth_e2e_test.dart` | E2E | `cd mobile && flutter test test/e2e/phase_1_auth_e2e_test.dart` | COVERED |
| 01-03 | Drift DAOs stream data reactively (watch queries) | `mobile/test/unit/features/company/company_dao_test.dart` | Unit | `cd mobile && flutter test test/unit/features/company/company_dao_test.dart` | COVERED |
| 01-03 | Drift DAOs for Users provide reactive streams | `mobile/test/unit/features/users/user_dao_test.dart` | Unit | `cd mobile && flutter test test/unit/features/users/user_dao_test.dart` | COVERED |
| 01-04 | GoRouter ValueNotifier bridge prevents router rebuild on auth state change | `mobile/test/unit/core/routing/app_router_test.dart` | Widget | `cd mobile && flutter test test/unit/core/routing/app_router_test.dart` | COVERED |
| 01-04 | AuthNotifier state transitions (loading, authenticated, unauthenticated) | `mobile/test/unit/features/auth/auth_provider_test.dart` | Unit | `cd mobile && flutter test test/unit/features/auth/auth_provider_test.dart` | COVERED |

### INFRA-06: Python backend API (FastAPI) shared across platforms

| Task | Behavior | Test File | Test Type | Automated Command | Status |
|------|----------|-----------|-----------|-------------------|--------|
| 01-02 | FastAPI health endpoint responds at /health | `backend/tests/integration/test_auth.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_auth.py -v` | COVERED |
| 01-02 | Rate limiting applied to auth endpoints | `backend/tests/integration/test_rate_limiting.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_rate_limiting.py -v` | COVERED |
| 01-02 | Security headers present on responses | `backend/tests/integration/test_security_headers.py` | Integration | `cd backend && uv run python -m pytest tests/integration/test_security_headers.py -v` | COVERED |
| 01-02 | CI pipeline exists for lint + test | `.github/workflows/ci.yml` | Smoke | N/A (infrastructure artifact, not a test) | COVERED |

---

## E2E Test Coverage

| Test File | Covers | Command |
|-----------|--------|---------|
| `mobile/test/e2e/phase_1_auth_e2e_test.dart` | Full auth flow: login, role selection, navigation guards, logout | `cd mobile && flutter test test/e2e/phase_1_auth_e2e_test.dart` |

---

## Additional Test Files (Beyond Requirement Map)

| Test File | Purpose | Command |
|-----------|---------|---------|
| `mobile/test/unit/core/auth/auth_repository_test.dart` | Auth repository unit tests | `cd mobile && flutter test test/unit/core/auth/auth_repository_test.dart` |
| `mobile/test/widget/features/auth/login_screen_test.dart` | Login screen widget tests | `cd mobile && flutter test test/widget/features/auth/login_screen_test.dart` |
| `mobile/test/widget/features/auth/register_screen_test.dart` | Register screen widget tests | `cd mobile && flutter test test/widget/features/auth/register_screen_test.dart` |
| `mobile/test/widget/features/auth/onboarding_screen_test.dart` | Onboarding screen widget tests | `cd mobile && flutter test test/widget/features/auth/onboarding_screen_test.dart` |
| `mobile/test/widget/shared/home_screen_test.dart` | Home screen widget tests | `cd mobile && flutter test test/widget/shared/home_screen_test.dart` |
| `backend/tests/integration/test_auth_edge_cases.py` | Auth edge cases (expired tokens, malformed JWT) | `cd backend && uv run python -m pytest tests/integration/test_auth_edge_cases.py -v` |

---

## Run All Phase 1 Tests

```bash
# Flutter (mobile)
cd mobile && flutter test test/unit/ test/widget/ test/e2e/phase_1_auth_e2e_test.dart

# Backend
cd backend && uv run python -m pytest tests/integration/test_tenant_isolation.py tests/integration/test_role_endpoints.py tests/integration/test_company_endpoints.py tests/integration/test_user_endpoints.py tests/integration/test_auth.py tests/integration/test_auth_edge_cases.py tests/integration/test_rate_limiting.py tests/integration/test_security_headers.py -v
```

---

## Coverage Summary

| Requirement | Total Behaviors | Covered | Partial | Missing | Compliance |
|-------------|----------------|---------|---------|---------|------------|
| INFRA-01 | 7 | 7 | 0 | 0 | FULL |
| INFRA-02 | 9 | 9 | 0 | 0 | FULL |
| INFRA-05 | 6 | 6 | 0 | 0 | FULL |
| INFRA-06 | 4 | 4 | 0 | 0 | FULL |
| **Total** | **26** | **26** | **0** | **0** | **FULL** |
