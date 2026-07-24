# Phase 27 — User Roles & RBAC Expansion

## Why

Today the system has exactly **three** user-level roles — `admin`, `contractor`, `client` —
enforced at 8 hard change-points (a pydantic `Literal`, a DB `CHECK` constraint, a
provision constant, a TS union, a Dart enum + `fromString`, a Flutter router guard, and
two test assertions). Meanwhile the codebase already *references* roles that were never
made valid, producing dead gates and broken UI conditionals:

- **`owner`** — used in `web/src/components/layout/sidebar.tsx:60`, `foreman/page.tsx:34`,
  `foreman/status/[projectId]/page.tsx:38`; no user can hold it, so those checks are inert.
- **`gc`** — gated in `backend/app/features/inspection/router.py:47` (`_require_gc_or_admin`);
  the whole GC-inspection path is unreachable because `gc` is not assignable.
- **`foreman`** — treated as a *user-level* role in the web, but it only exists as a
  *project-level* assignment in `project_assignments` (migration `0025_foreman_role`).

This phase adds **five** new user-level roles and reconciles the ghosts.

## New role set (canonical slugs)

Roles are lowercase snake-case single tokens (matching `admin`/`contractor`/`client`).
Final valid set after this phase:

```
owner, admin, project_manager, gc, foreman, contractor, worker, client
```

| Slug              | Meaning                                                                 |
|-------------------|-------------------------------------------------------------------------|
| `owner`           | Company owner / super-admin. Everything admin does + company & billing settings. |
| `admin`           | (existing) Full operational management within the company.              |
| `project_manager` | Manages projects, jobs, scheduling, quotes, invoices. No user/role or company settings. |
| `gc`              | General contractor. Inspections, per-trade billing approval, foreman assignment. |
| `foreman`         | On-site lead for **assigned** projects: daily checklists, task execution, crew coordination. Now a real user-level role (project-level `project_assignments` row is retained and unchanged). |
| `contractor`      | (existing) Executes assigned jobs; can submit quotes.                   |
| `worker`          | Laborer below contractor: view assigned tasks, complete checklist items, log time, upload photos. No job/quote/client management. |
| `client`          | (existing) Customer portal — own jobs & quotes only.                    |

Users may hold **multiple** roles (the model is a junction table `user_roles`), so these
are additive capabilities, not a strict single-tier ladder.

## Multiple roles per user (semantics)

A user can hold any combination of roles simultaneously (e.g. `admin` + `contractor`, or
`gc` + `foreman`). Every layer treats roles as a **set**, never a single value:

- **Permission resolution = union (most-permissive wins).** A user's effective permissions
  are `⋃ expand(role_permissions[r])` over all their roles `r`. `require_permission(key)`
  and `GET /me/permissions` both compute this union. Holding *any* role that grants a key
  grants the key. There is no "deny" override — this is additive-only.
- **No role precedence for permissions.** Because it's a union, order doesn't matter; a
  user who is both `worker` and `project_manager` gets the PM's superset.
- **Precedence DOES apply to single-choice UI variants.** Where a screen must pick ONE
  variant (e.g. mobile schedule/reports admin-vs-contractor view), choose by
  highest-privilege role present: `owner|admin` → admin variant, else `project_manager|gc`
  → manager variant, else `contractor|foreman|worker` → field variant, else `client`.
  This is a display rule only; it never restricts what the union already permits.
- **Role assignment is per-role and additive.** `POST /users/{id}/roles` assigns one role
  (idempotent); removing a role is a separate soft-delete. A user's role set is the sum of
  their non-deleted `user_roles` rows. Role-management UIs render the set (chips: add/remove),
  not a single-select — `RoleSelect` is for adding one role, not replacing the set.
- **JWT carries the full role list.** `create_access_token(..., roles)` already embeds the
  complete `roles` array; `CurrentUser.roles` is a list. Login re-derives the full set from
  the DB. No change needed — just do not collapse it to `roles[0]` anywhere.

## Default permission matrix (seeded; per-company editable)

This matrix is the **default** each company starts with. It is copied into a per-company
`company_role_permissions` store at company creation, and **owner/admin can override it**
(see "Editable role permissions" below). The rows here define the seed + the "Reset to
defaults" target — not a hardcoded ceiling.

| Capability                                                | owner | admin | project_manager | gc | foreman | contractor | worker | client |
|-----------------------------------------------------------|:----:|:-----:|:---------------:|:--:|:-------:|:----------:|:------:|:------:|
| Company & billing settings, delete company data           |  ✓   |       |                 |    |         |            |        |        |
| Manage users & assign roles (`POST /users/{id}/roles`)    |  ✓   |   ✓   |                 |    |         |            |        |        |
| Manage projects / jobs / scheduling / quotes / invoices   |  ✓   |   ✓   |        ✓        |    |         |            |        |        |
| Inspections & per-trade billing approval                  |  ✓   |   ✓   |                 | ✓  |         |            |        |        |
| Assign foreman to a project                               |  ✓   |   ✓   |                 | ✓  |         |            |        |        |
| Manage tasks / daily checklists on **assigned** projects  |  ✓   |   ✓   |        ✓        | ✓  |  ✓ᵃ     |            |        |        |
| Execute assigned jobs, submit quotes                      |  ✓   |   ✓   |                 |    |  ✓      |     ✓      |        |        |
| Complete checklist items, log time, upload photos         |      |       |                 |    |  ✓      |     ✓      |   ✓    |        |
| Client portal (own jobs & quotes)                         |      |       |                 |    |         |            |        |   ✓    |

ᵃ foreman management is scoped to projects they are assigned to via `project_assignments`.

## Capability groups (role-set constants in `app/core/security.py`)

Named role-sets + `require_*` helpers still exist, but their role now shifts: they are the
**source of the default permission matrix**, not the runtime enforcement. Membership is by
role presence (OR), matching the existing `require_roles` semantics.

| Helper              | Role set                                     | Seeds / still gates                                |
|---------------------|----------------------------------------------|----------------------------------------------------|
| `require_owner`     | `{owner}`                                     | company/billing settings (owner-only)              |
| `require_admin`     | `{owner, admin}` **(broadened)**              | admin-only gates not yet migrated to permissions    |
| `require_manager`   | `{owner, admin, project_manager}`             | (default source for management permission keys)     |
| `require_gc`        | `{owner, admin, gc}`                           | (default source for inspection/foreman keys)        |

Runtime enforcement of *editable* capabilities moves to `require_permission("<key>")`
(see below). The role-set helpers remain for owner/admin structural gates that are NOT
per-company overridable (e.g. `roles.permissions.manage` is always held by owner).

**Non-goal (this phase):** row-level "assigned project only" enforcement for foreman is
left as-is (already handled by `_require_admin_or_assigned_foreman` in
`foreman/router.py`, extended to also honor `gc`). We are not building a full ABAC layer.

## Editable role permissions (per-company overrides) — 27-04

Owner/admin can change what each role is allowed to do, per company. Implemented as a
permission-key layer on top of the roles.

> **Granularity update (executed):** the catalog was built **CRUD-granular**, not coarse.
> The authoritative catalog is `backend/app/core/permissions.py` — **47 keys**: per-resource
> `view/create/edit/delete` for projects, jobs, schedule, quotes, invoices, clients, tasks,
> users; plus named actions (`roles.assign`, `roles.permissions.manage`, `jobs.execute`,
> `quotes.submit`, `tasks.complete`, `inspections.perform`, `billing.trade.approve`,
> `foreman.assign`, `time.log`, `photos.upload`, `company.settings.manage`,
> `company.billing.manage`, `portal.access`). The coarse table below is the original sketch,
> retained for history; the shipped defaults are derived from these granular keys.

### Permission catalog (original coarse sketch — superseded by the 47-key granular set)

| Group    | Key                          | Label                                    |
|----------|------------------------------|------------------------------------------|
| Company  | `company.settings.manage`    | Manage company settings                  |
| Company  | `company.billing.manage`     | Manage billing & subscription            |
| Access   | `users.manage`               | Create / deactivate users                |
| Access   | `roles.assign`               | Assign roles to users                    |
| Access   | `roles.permissions.manage`   | Edit role permissions                    |
| Ops      | `projects.manage`            | Create / edit projects                   |
| Ops      | `jobs.manage`                | Create / edit jobs                       |
| Ops      | `schedule.manage`            | Manage scheduling                        |
| Ops      | `quotes.manage`              | Create / edit / send quotes              |
| Ops      | `invoices.manage`            | Create / edit / finalize invoices        |
| Ops      | `clients.manage`             | Manage clients / CRM                     |
| Build    | `inspections.manage`         | Manage inspections                       |
| Build    | `billing.trade.approve`      | Approve per-trade billing                |
| Build    | `foreman.assign`             | Assign foremen to projects               |
| Build    | `tasks.manage`               | Manage project tasks & checklists        |
| Field    | `jobs.execute`               | Update status of assigned jobs           |
| Field    | `quotes.submit`              | Submit quotes for assigned jobs          |
| Field    | `tasks.complete`             | Complete assigned checklist items        |
| Field    | `time.log`                   | Log time entries                         |
| Field    | `photos.upload`              | Upload job photos                        |
| Portal   | `portal.access`              | Access client portal                     |

The catalog is code-defined (`app/core/permissions.py`) — companies can toggle which roles
hold which keys, but cannot invent new keys.

### Default role → permission map (the seed; `DEFAULT_ROLE_PERMISSIONS`)

| Role              | Default permission keys                                                                 |
|-------------------|-----------------------------------------------------------------------------------------|
| `owner`           | `["*"]` — all keys, **locked** (always includes `roles.permissions.manage`; non-removable) |
| `admin`           | everything except `company.settings.manage`, `company.billing.manage` (incl. `roles.permissions.manage`) |
| `project_manager` | `projects.manage, jobs.manage, schedule.manage, quotes.manage, invoices.manage, clients.manage, tasks.manage` |
| `gc`              | `inspections.manage, billing.trade.approve, foreman.assign, tasks.manage`               |
| `foreman`         | `tasks.manage, jobs.execute, quotes.submit, tasks.complete, time.log, photos.upload`    |
| `contractor`      | `jobs.execute, quotes.submit, tasks.complete, time.log, photos.upload`                   |
| `worker`          | `tasks.complete, time.log, photos.upload`                                               |
| `client`          | `portal.access`                                                                         |

### Storage

`company_role_permissions` (tenant-scoped, RLS): one row per `(company_id, role)` with a
`permissions JSONB` array of keys. Unique `(company_id, role)`. "Reset to defaults"
overwrites a role's row (or all rows) from `DEFAULT_ROLE_PERMISSIONS`.

### Enforcement

`require_permission("<key>")` — an async FastAPI dependency that loads the caller's
company row-set (cached per request), unions the permission keys across the caller's
roles, and 403s unless the key (or `"*"`) is present. Domain management gates
(jobs/projects/schedule/quotes/invoices/inspections/foreman.assign/billing.trade.approve/
roles.assign/company.settings) are converted from `require_admin`/`require_manager`/
`require_gc` to `require_permission(...)`.

### Endpoints (owner/admin only, gated by `roles.permissions.manage`)

- `GET  /api/v1/roles/permissions` → `{ catalog: [...], roles: { role: [keys] }, defaults: {...} }`
- `PUT  /api/v1/roles/{role}/permissions` → replace one role's key set
- `POST /api/v1/roles/permissions/reset` → reset one role (body `{role}`) or all to defaults
- `GET  /api/v1/me/permissions` → the **current user's** effective permission keys (union
  across their roles) — consumed by web/mobile to gate UI. Any authenticated user.

### Safeguards (prevent lockout)

- `owner` is always `["*"]` and cannot be edited or have `roles.permissions.manage` removed.
- A `PUT`/reset may never leave **zero** roles holding `roles.permissions.manage`.
- The catalog is fixed; unknown keys in a `PUT` body are rejected (422).
- Seeding runs on company registration; a migration backfills existing companies.

## Reconciliation of pre-existing inconsistencies (in scope)

1. **`gc` ghost gate** — `inspection/router.py:47` `_require_gc_or_admin` → `require_gc`.
   Now reachable because `gc` becomes assignable.
2. **`owner` ghost UI** — web sidebar/foreman checks (`["admin","owner"]`) keep working and
   are now backed by a real, assignable role; no code change needed beyond adding the role.
3. **`foreman` user-level vs project-level** — `foreman` becomes a valid user-level role.
   The web check in `foreman/status/[projectId]/page.tsx:38` is now backed by a real role.
   The per-project `project_assignments` table is unchanged and still authoritative for
   *which* project a foreman is assigned to.
4. **Narrow foreman CHECK** — `backend/app/features/foreman/models.py:65`
   `CHECK (role IN ('foreman'))` is widened to `('foreman','lead','inspector')` to match
   migration `0025_foreman_role:35`.
5. **Missing admin guard** — `POST /users/{user_id}/roles`
   (`backend/app/features/users/router.py:47`) currently has **no** authorization guard
   (any authenticated tenant user can self-assign any valid role). Add `require_admin`.

## Change-point inventory (from role-system audit)

Minimum edits per new user-level role, all covered by the plans below:

| # | File / location                                             | Plan |
|---|-------------------------------------------------------------|------|
| 1 | `backend/app/features/users/schemas.py:55` — `Literal`      | 27-01 |
| 2 | `backend/app/features/users/models.py:48` — CHECK constraint | 27-01 |
| 3 | **new** `migrations/versions/0026_expand_user_roles.py` (ALTER `valid_role`) | 27-01 |
| 4 | `backend/scripts/provision.py:53` — `VALID_ROLES`           | 27-01 |
| 5 | `backend/app/core/security.py` — role-set helpers            | 27-01 |
| 6 | `web/src/types/api.ts:407` — `RoleAssignmentRequest` union  | 27-02 |
| 7 | `mobile/lib/shared/models/user_role.dart:5` — `enum UserRole` | 27-03 |
| 8 | `mobile/lib/core/routing/app_router.dart:606` — route guards | 27-03 |
| 9 | `backend/tests/integration/test_role_endpoints.py:25,39`    | 27-01 |

## Plans in this phase

- **27-01 (wave 1, backend — roles foundation):** role whitelist (schema + model CHECK),
  migration 0026, `require_*` capability helpers (now the default-seed source),
  reconciliation of gc/owner/foreman/admin-guard, `provision.py` + `seed_data.py`,
  backend tests.
- **27-04 (wave 1b, backend — permissions subsystem):** permission catalog
  (`app/core/permissions.py`), `DEFAULT_ROLE_PERMISSIONS`, `company_role_permissions`
  table + migration 0027 (+ backfill), seed-on-register, `require_permission` dependency,
  the `/roles/permissions` + `/me/permissions` endpoints, and conversion of domain gates
  from role-sets to permission keys. Depends on 27-01.
- **27-02 (wave 2, web):** TS role types + shared `ROLES`/label map, role selector UI, the
  **Settings → Roles permission-matrix editor** (consumes 27-04's endpoints), and nav/route
  gating driven by `GET /me/permissions` instead of static role checks.
- **27-03 (wave 2, mobile):** Dart `UserRole` enum + `fromString`/`displayLabel`, router
  `_checkRoleAccess` guards, Drift table comment, role-based screen selection, and
  (optional) consuming `/me/permissions` for UI gating.

27-04 depends on 27-01. Waves 2 (web) and 3 (mobile) depend on 27-04's API contract (the
permissions endpoints) and can run in parallel with each other.

## Design decisions

- **Owner implies admin.** `require_admin` is broadened to `{owner, admin}` rather than
  adding `owner` at every existing admin call site. One helper edit; no call-site churn.
- **foreman stays dual.** A user-level `foreman` role (capability) plus the existing
  project-level `project_assignments.role='foreman'` (scope). We do not migrate one into
  the other.
- **No destructive enum swap.** `user_roles.role` is `TEXT` + a `CHECK` constraint, so the
  migration is a `DROP CONSTRAINT` / `ADD CONSTRAINT` — additive, reversible, no data
  rewrite, no Postgres enum type to alter.
- **worker gets no new endpoints this phase.** It is a *restricting* role: it exists so the
  field/task-execution surface (checklists, time entries, photos — added in phase 26) can
  be granted to laborers without job/quote/client management. At the permission level worker
  differs from contractor by lacking `jobs.execute` and `quotes.submit`.
- **Permissions are per-company and editable by owner/admin, not global.** The default
  matrix is a seed, not a ceiling — owner/admin change it via the Settings → Roles editor.
  `owner` is always `["*"]` (locked) and at least one role must always retain
  `roles.permissions.manage`, so a company can never lock itself out.
- **Enforcement migrates to permission keys, incrementally.** 27-04 converts the domain
  management gates to `require_permission(...)`. Remaining `require_admin` gates keep working
  (owner/admin hold all keys by default) and can be converted later without a data change.
- **Frontends gate UI from `GET /me/permissions`,** not by replicating the matrix — the
  server stays the single source of truth for what a user may do.
