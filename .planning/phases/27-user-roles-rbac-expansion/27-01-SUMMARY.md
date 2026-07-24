---
phase: 27-user-roles-rbac-expansion
plan: "01"
subsystem: backend
tags: [rbac, roles, authorization, migration, sqlalchemy, fastapi, pytest]
dependency_graph:
  requires:
    - backend/app/features/users/models.py (UserRole junction table + valid_role CHECK)
    - backend/app/features/users/schemas.py (RoleAssignment Literal)
    - backend/app/core/security.py (require_roles, CurrentUser, get_current_user)
    - backend/migrations/versions/0025_foreman_role.py (migration chain head)
  provides:
    - Eight valid user-level roles (owner, admin, project_manager, gc, foreman, contractor, worker, client)
    - backend/app/core/security.py (OWNER/ADMIN/MANAGER/GC role-sets + require_owner/require_manager/require_gc; broadened require_admin)
    - backend/migrations/versions/0026_expand_user_roles.py (valid_role CHECK swap, reversible)
    - Reconciled gc inspection gate, foreman CHECK, foreman/gc guard, admin-guarded role assignment
  affects:
    - 27-04 (permissions subsystem — role-sets are the default-matrix seed source; gates migrate to require_permission)
    - 27-02 (web — consumes the eight-role contract)
    - 27-03 (mobile — consumes the eight-role contract)
tech_stack:
  added: []
  patterns:
    - Named role-set tuples (OWNER/ADMIN/MANAGER/GC_ROLES) as the single source of coarse privilege tiers
    - "owner implies admin" — broaden require_admin once instead of touching every admin call site
    - Additive, reversible CHECK-constraint migration (DROP/ADD CONSTRAINT, no data rewrite)
key_files:
  created:
    - backend/migrations/versions/0026_expand_user_roles.py
    - backend/tests/test_rbac_helpers.py
  modified:
    - backend/app/features/users/schemas.py (RoleAssignment.role Literal -> eight roles)
    - backend/app/features/users/models.py (valid_role CHECK -> eight roles)
    - backend/app/core/security.py (role-set constants + require_owner/require_manager/require_gc; require_admin broadened to owner+admin)
    - backend/app/features/inspection/router.py (_require_gc_or_admin delegates to require_gc)
    - backend/app/features/foreman/models.py (ProjectAssignment CHECK -> foreman/lead/inspector)
    - backend/app/features/foreman/router.py (admin branch honors owner/admin/gc; contractor-or-admin includes owner)
    - backend/app/features/users/router.py (assign_role now requires admin)
    - backend/scripts/provision.py (VALID_ROLES -> eight roles; --role choices)
    - backend/scripts/seed_data.py (demo users for owner/project_manager/gc/foreman/worker)
    - backend/tests/integration/test_role_endpoints.py (all eight roles + non-admin 403)
    - backend/app/features/dashboard/router.py (removed pre-existing unused imports to unblock ruff)
key_decisions:
  - "owner implies admin: require_admin gates on {owner, admin}; no existing admin call site changed."
  - "foreman stays dual: user-level role AND per-project project_assignments row; neither migrates into the other."
  - "Non-destructive migration: role column is TEXT + named CHECK, so 0026 is DROP/ADD CONSTRAINT (reversible, no rewrite)."
  - "Interim role-based reconciliation; 27-04 supersedes enforcement with require_permission without undoing it."
patterns_established:
  - "Role-set tuples in security.py name the privilege tiers and seed 27-04's default permission matrix."
  - "Multi-role union semantics: require_roles passes if ANY held role matches (covered by test_rbac_helpers)."
requirements-completed: [ROLE-01, ROLE-02, ROLE-03, ROLE-04, ROLE-05]
duration: ~25min
completed: 2026-07-23
---

# Phase 27-01: Backend Roles Foundation Summary

**Five new user-level roles (owner, project_manager, gc, foreman, worker) are now valid,
assignable, and enforced through named capability helpers, with the pre-existing gc/owner/
foreman/admin-guard inconsistencies reconciled.**

## Performance

- **Duration:** ~25 min
- **Tasks:** 5 of 5 completed + verification
- **Files modified:** 10 modified, 2 created

## Accomplishments

- **Widened the whitelist** at both enforcement points: the pydantic `RoleAssignment.role`
  `Literal` and the `user_roles.valid_role` CHECK now list all eight roles.
- **Migration 0026** swaps the CHECK additively (DROP/ADD CONSTRAINT); verified up/down/up
  round-trip on the dev DB and auto-applied to the test DB by the suite.
- **Capability helpers** in `security.py`: `OWNER/ADMIN/MANAGER/GC_ROLES` tuples plus
  `require_owner/require_manager/require_gc`; `require_admin` broadened to `{owner, admin}`.
- **Reconciliation:** the gc inspection gate now delegates to `require_gc` (reachable because
  gc is assignable); the foreman `ProjectAssignment` CHECK matches migration 0025
  (`foreman/lead/inspector`); the foreman guard honors owner/admin/gc; and
  `POST /users/{id}/roles` now requires admin (closing the self-assignment gap).
- **Provisioning + seed:** `provision.VALID_ROLES` (and `--role` choices) cover all eight;
  `seed_data` adds a demo user per new role to Ace Plumbing.
- **Tests:** role-endpoint test now asserts all eight roles assignable + a non-admin 403 case;
  new `test_rbac_helpers.py` unit-tests each gate's positive/negative/multi-role behavior.

## Verification

- `alembic upgrade head → downgrade -1 → upgrade head` clean on dev DB.
- `pytest test_role_endpoints test_rbac_helpers test_auth test_foreman_e2e test_provision_script`
  → **67 passed**.
- `ruff check app scripts tests` → **All checks passed**; `ruff format --check` → clean.
- `from app.main import app` builds (178 routes).

## Notes for downstream plans

- The role-set tuples here are the **seed source** for 27-04's `DEFAULT_ROLE_PERMISSIONS`.
  27-04 converts the domain gates (jobs/projects/schedule/quotes/invoices/inspection/
  foreman.assign/roles.assign) from these role-sets to `require_permission("<key>")`.
- Removed two pre-existing unused imports in `dashboard/router.py` (phase-26 leftovers) that
  were failing `ruff check` and would have blocked the commit gate.
