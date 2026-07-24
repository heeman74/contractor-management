# Phase 27: User Roles & RBAC Expansion - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.

**Date:** 2026-07-23
**Phase:** 27-user-roles-rbac-expansion
**Areas discussed:** New user roles, Stack scope, Pre-existing inconsistencies, Permission model, Multi-role semantics
**Mode:** interactive (AskUserQuestion — decisions user-selected, not auto)

---

## New User-Level Roles

| Option | Description | Selected |
|--------|-------------|----------|
| owner | Company owner / super-admin above admin (backs the existing ghost UI checks) | ✓ |
| gc (general contractor) | Activates the dead GC-inspection gate in inspection/router.py | ✓ |
| foreman | Promote foreman from project-level assignment to a real user-level role | ✓ |
| project_manager / supervisor | Net-new operational role between admin and contractor | ✓ |
| worker | Laborer below contractor: task/checklist/time/photo only, no job/quote management | ✓ (added by user) |

**User's choice:** All five — owner, gc, foreman, project_manager, worker. Final valid set:
owner, admin, project_manager, gc, foreman, contractor, worker, client.

---

## Stack Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Full stack | Backend + web + mobile (schema, guards, selectors, Dart enum) | ✓ |
| Backend + web only | Skip Flutter; mobile fromString would throw on new roles | |
| Backend only | API/DB/provision only, generic string[] frontends | |

**User's choice:** Full stack (recommended).

---

## Pre-existing Inconsistencies (reconciliation)

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, reconcile them | Fix gc/owner ghost gates, narrow foreman CHECK, missing admin-guard on POST /users/{id}/roles | ✓ |
| No, roles only | Leave existing inconsistencies as-is | |

**User's choice:** Yes — reconcile. Captured in 27-01 Task 3 (interim role-based) and finalized
as permission gates in 27-04.

---

## Permission Model (owner/admin can change role permissions)

| Option | Description | Selected |
|--------|-------------|----------|
| Editable permission matrix | Per-company DB matrix of granular keys, edited in UI, DB-backed enforcement | |
| Defaults + per-company override | Ship hardcoded matrix as seeded defaults, store in DB, owner/admin override per company, reset-to-default | ✓ |
| Assignment only (no matrix) | Capabilities stay code-defined; owner/admin only change which roles a user holds | |

**User's choice:** Defaults + per-company override. Drove the new 27-04 plan (permission catalog,
company_role_permissions table + migration 0027 + backfill, require_permission enforcement,
/roles/permissions + /me/permissions endpoints, and the web Settings → Roles editor in 27-02).

---

## Editors of the Permission Matrix

| Option | Description | Selected |
|--------|-------------|----------|
| Owner and admin | Both hold roles.permissions.manage by default | ✓ |
| Owner only | Only owner can edit the matrix | |

**User's statement:** "owner and admin should be able to change and update role permissions."
Reflected in DEFAULT_ROLE_PERMISSIONS (admin gets roles.permissions.manage) with owner locked to
["*"] and a no-lockout guard (a PUT/reset may never leave zero holders of roles.permissions.manage).

---

## Multiple Roles Per User

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-role, union permissions | user_roles is a junction table; effective permissions = union across roles (most-permissive) | ✓ |
| Single role per user | One role per user | |

**User's statement:** "a user can have multiple roles." Confirmed as already-supported (junction
table). Documented union semantics, single-choice-UI precedence (highest-privilege role wins for
display variants only), additive per-role assignment, and full-roles-in-JWT in 27-CONTEXT.md.

---

## Open Items (flagged for confirmation before execution)

| Item | Question | Status |
|------|----------|--------|
| Catalog granularity | Keep 21 coarse keys (jobs.manage) vs finer (jobs.create/edit/delete)? | Awaiting confirmation — defaulted to coarse |
| admin self-edit | Confirmed admin may edit its own role's permissions (owner can revoke) | Resolved — yes per user statement |
