---
phase: 27-user-roles-rbac-expansion
plan: "04"
subsystem: backend
tags: [rbac, permissions, authorization, migration, jsonb, rls, fastapi, pytest]
dependency_graph:
  requires:
    - 27-01 (eight valid roles + require_* capability helpers as the default-matrix seed source)
    - backend/app/core/base_models.py (TenantScopedModel)
    - backend/app/core/base_repository.py / base_service.py (tenant-scoped bases)
    - backend/app/features/auth/service.py (register — seed hook)
  provides:
    - backend/app/core/permissions.py (PERMISSION_CATALOG 21 keys, DEFAULT_ROLE_PERMISSIONS, expand)
    - backend/migrations/versions/0027_company_role_permissions.py (per-company matrix table + backfill + RLS)
    - backend/app/core/security.py (require_permission dependency + effective_permissions)
    - backend/app/features/rbac/* (model, repository, schemas, service, router)
    - REST: GET/PUT/reset /roles/permissions + GET /me/permissions
  affects:
    - 27-02 (web — consumes /roles/permissions editor + /me/permissions gating)
    - 27-03 (mobile — optional /me/permissions consumption)
tech_stack:
  added: []
  patterns:
    - "Editable per-company permission matrix (JSONB list per role) seeded from code defaults"
    - "require_permission(key): async FastAPI dependency factory reading the tenant matrix (union across roles)"
    - "Inline gate conversion: await require_permission('key')(current_user, db) — no signature churn"
    - "Backfill BEFORE enabling RLS so appuser (NOBYPASSRLS) can insert without tenant context"
    - "Admin default derived from catalog minus company.* keys — cannot drift as keys are added"
key_files:
  created:
    - backend/app/core/permissions.py
    - backend/migrations/versions/0027_company_role_permissions.py
    - backend/app/features/rbac/__init__.py
    - backend/app/features/rbac/models.py
    - backend/app/features/rbac/repository.py
    - backend/app/features/rbac/schemas.py
    - backend/app/features/rbac/service.py
    - backend/app/features/rbac/router.py
    - backend/tests/integration/test_role_permissions.py
  modified:
    - backend/app/core/security.py (require_permission + effective_permissions)
    - backend/app/features/auth/service.py (seed_defaults on register)
    - backend/app/main.py (rbac_router registered)
    - backend/app/features/users/router.py (roles.assign)
    - backend/app/features/inspection/router.py (inspections.manage; helper removed)
    - backend/app/features/foreman/router.py (foreman.assign)
    - backend/app/features/jobs/router.py (jobs.manage x6)
    - backend/app/features/projects/router.py (projects.manage x2)
    - backend/app/features/scheduling/router.py (schedule.manage x3, via svc.db)
    - backend/app/features/quotes/router.py (quotes.manage x12)
    - backend/app/features/invoices/router.py (invoices.manage x9)
    - backend/app/features/billing_milestones/router.py (invoices.manage x3 + billing.trade.approve x1)
    - backend/tests/conftest.py (truncate company_role_permissions)
    - backend/tests/test_foreman_e2e.py (assert on permission-key detail)
key_decisions:
  - "Coarse 21-key catalog (jobs.manage, not jobs.create/edit/delete) — the documented default granularity."
  - "owner locked to ['*']; admin gets all keys except company.settings/billing.manage; both hold roles.permissions.manage."
  - "Enforcement reads the live DB matrix, so an admin's edit changes access immediately (proven by test)."
  - "No-lockout guard: a PUT/reset may never leave zero roles with roles.permissions.manage (owner's wildcard always satisfies it)."
  - "Inline await-dependency conversion chosen over route-level dependencies to minimize signature churn across ~35 sites."
patterns_established:
  - "Permission enforcement decoupled from roles: gates name a capability key; the per-company matrix maps roles -> keys."
  - "Frontends gate UI from GET /me/permissions (server stays the source of truth)."
requirements-completed: [PERM-01, PERM-02, PERM-03, PERM-04, PERM-05]
duration: ~50min
completed: 2026-07-23
---

# Phase 27-04: Editable Permissions Subsystem Summary

**Owner/admin can now edit a per-company role -> permission matrix, and the backend enforces
it live — editing a role's keys changes what its users can do on the next request.**

> **Granularity follow-up (same phase, executed after review):** the catalog was reworked
> from the coarse 21-key set to a **CRUD-granular 47-key set** (per-resource
> view/create/edit/delete + named actions). `DEFAULT_ROLE_PERMISSIONS` was re-derived, the
> ~35 domain gates were re-mapped to specific verbs (e.g. `jobs.create`/`jobs.edit`/
> `jobs.delete`, `invoices.finalize`, `inspections.perform`), the dev DB was re-seeded
> (downgrade/upgrade 0027), and the permission tests were updated. Full suite re-verified:
> **541 passed, 1 skipped**. `permissions.py` is the authoritative catalog.

## Performance

- **Duration:** ~50 min
- **Tasks:** 6 of 6 completed + verification
- **Files:** 9 created, 15 modified

## Accomplishments

- **Permission catalog** (`app/core/permissions.py`): 21 granular keys across Company/Access/
  Operations/Construction/Field/Portal, plus `DEFAULT_ROLE_PERMISSIONS` (owner `["*"]`, admin
  derived as catalog−company.* keys, and per-role sets for the rest) and `expand()`.
- **`company_role_permissions` table** (migration **0027**): one JSONB row per (company, role),
  unique on (company_id, role), RLS-forced. Backfills every existing company from defaults
  **before** enabling RLS (so appuser can insert without tenant context). Round-trips up/down/up.
- **Enforcement** (`require_permission(key)`): an async dependency that unions the caller's
  roles' keys from the tenant matrix (falling back to code defaults) and 403s on a miss.
  `effective_permissions()` backs both it and `/me/permissions`.
- **Seed-on-register**: `AuthService.register` seeds the matrix for each new company in-transaction.
- **RBAC feature module**: model/repository/schemas/service/router. Editor endpoints
  (`GET/PUT /roles/{role}/permissions`, `POST /roles/permissions/reset`) gated by
  `roles.permissions.manage`; `GET /me/permissions` for UI gating. Safeguards: owner locked,
  unknown keys 422, no-lockout guard (409).
- **Domain-gate conversion**: ~35 `require_admin` sites across users/inspection/foreman/jobs/
  projects/scheduling/quotes/invoices/billing_milestones now enforce via `require_permission`
  with mapped keys (billing `mark-invoiced` → `billing.trade.approve`; create/update/delete →
  `invoices.manage`). The row-level `_require_admin_or_assigned_foreman` fallback is left intact.

## Verification

- `alembic upgrade/downgrade/upgrade` clean on dev DB; test DB migrates via the suite.
- **Full backend suite: 541 passed, 1 skipped** (10m59s) — includes the new
  `test_role_permissions.py` (seeding, editor auth, live enforcement, unknown-key 422, owner-lock,
  reset, /me/permissions union) and every converted domain test.
- `ruff check app scripts tests` clean; `ruff format --check` clean.

## Notes for downstream plans

- Web (27-02) consumes `GET /api/v1/roles/permissions` (catalog + roles + defaults),
  `PUT /roles/{role}/permissions`, `POST /roles/permissions/reset`, and `GET /me/permissions`.
- One test expectation updated: `test_non_admin_cannot_assign` now asserts the detail contains
  `foreman.assign` (was "admin role required") — the gate wording changed with the mechanism.
- Added `company_role_permissions` to conftest's truncate list (FK to companies).
- **Open item:** catalog granularity is coarse (per-resource `*.manage`). Splitting into
  create/edit/delete is a catalog-only change if finer control is wanted later.
