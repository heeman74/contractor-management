---
status: testing
phase: 01-foundation
source: [01-01-SUMMARY.md, 01-02-SUMMARY.md, 01-03-SUMMARY.md, 01-04-SUMMARY.md, 01-05-SUMMARY.md]
started: 2026-03-05T07:30:00Z
updated: 2026-03-05T07:30:00Z
---

## Current Test

number: 1
name: Cold Start Smoke Test
expected: |
  Kill any running containers. Run `docker compose up --build` from the project root. PostgreSQL 16 starts with healthcheck passing, Redis 7 starts, FastAPI backend starts and runs Alembic migrations automatically. Visit http://localhost:8000/health — returns a JSON response. Visit http://localhost:8000/docs — shows Swagger UI with all endpoints.
awaiting: user response

## Tests

### 1. Cold Start Smoke Test
expected: Kill any running containers. Run `docker compose up --build` from the project root. PostgreSQL 16 starts with healthcheck passing, Redis 7 starts, FastAPI backend starts and runs Alembic migrations automatically. Visit http://localhost:8000/health — returns a JSON response. Visit http://localhost:8000/docs — shows Swagger UI with all endpoints.
result: [pending]

### 2. Company CRUD via API
expected: Using Swagger UI (http://localhost:8000/docs) or curl, POST to /api/v1/companies/ with `{"name": "Test Co", "trade_types": ["plumbing"]}` and header `X-Company-Id: <any-uuid>`. Returns 201 with company object including id, name, trade_types. GET /api/v1/companies/{id} returns the same company. PATCH /api/v1/companies/{id} with `{"name": "Updated Co"}` returns updated name.
result: [pending]

### 3. User CRUD with Tenant Isolation
expected: With `X-Company-Id` header set to a company's UUID, POST to /api/v1/users/ with `{"email": "test@example.com", "first_name": "Test", "last_name": "User"}` (note: no company_id in body). Returns 201 with user including the company_id from the header. GET /api/v1/users/ returns only users for the company in the header — switching the header to a different company UUID returns a different set of users (or empty).
result: [pending]

### 4. Role Assignment via API
expected: POST to /api/v1/users/{user_id}/roles with `{"role": "admin"}`. Returns 201 with role assignment. GET /api/v1/users/{user_id}/roles returns the assigned role. Repeat with "contractor" and "client" — all three role types work. POST with an invalid role like "superadmin" returns 422 validation error.
result: [pending]

### 5. RLS Tenant Isolation Tests Pass
expected: With Docker Compose running, execute: `cd backend && pytest tests/integration/test_tenant_isolation.py -v`. All 5 tests pass — proving Tenant A cannot read Tenant B's data, Tenant B cannot read Tenant A's data, no tenant header returns empty results, and cross-tenant writes are blocked.
result: [pending]

### 6. Role Endpoint Tests Pass
expected: Execute: `cd backend && pytest tests/integration/test_role_endpoints.py -v`. All 5 tests pass — proving all 3 role types are assignable, invalid roles are rejected, and role visibility is tenant-scoped.
result: [pending]

### 7. Seed Data Script Populates Demo Data
expected: Run `docker compose exec backend python -m scripts.seed_data`. Script creates "Ace Plumbing & Electrical" (4 users) and "BuildRight Construction" (2 users) without errors. Running it again is safe (idempotent — checks existence before inserting). Verify by calling GET /api/v1/companies/ with appropriate tenant header.
result: [pending]

### 8. Flutter App Builds and Shows Role Picker
expected: Run `cd mobile && flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter run`. App launches, briefly shows splash screen, then redirects to onboarding screen with role picker buttons: "Sign in as Admin", "Sign in as Contractor", "Sign in as Client", and a multi-role test option.
result: [pending]

### 9. Admin Role Navigation (5 Tabs)
expected: On the onboarding screen, tap "Sign in as Admin". App redirects to home screen with bottom navigation showing 5 tabs: Home, Jobs, Schedule, Profile, and Team. The Team tab is visible because user has admin role. Tapping each tab navigates to the corresponding placeholder screen.
result: [pending]

### 10. Contractor Role Navigation (4 Tabs)
expected: Sign out (via Profile screen), return to onboarding, tap "Sign in as Contractor". Bottom navigation shows 4 tabs: Home, Jobs, Schedule, Profile. No Team tab visible. Home screen shows contractor-specific quick links.
result: [pending]

### 11. Route Guard Blocks Unauthorized Access
expected: While signed in as Contractor, attempt to navigate to an admin route (e.g., deep link to /admin/team). App redirects to the unauthorized screen showing "Access Denied" with options to go back or return home. Admin routes are not accessible without admin role.
result: [pending]

### 12. Flutter Unit Tests Pass
expected: Run `cd mobile && flutter test test/unit/`. All 14 tests pass — 6 AuthNotifier state tests (loading, setMockUser, logout, multi-role) and 8 go_router role guard tests (splash redirect, onboarding redirect, admin access, contractor blocked from admin, client blocked from contractor, multi-role access).
result: [pending]

## Summary

total: 12
passed: 0
issues: 0
pending: 12
skipped: 0

## Gaps

[none yet]
