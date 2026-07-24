---
phase: 27-user-roles-rbac-expansion
plan: "02"
subsystem: web
tags: [rbac, permissions, nextjs, react-query, redux, tailwind, ui]
dependency_graph:
  requires:
    - 27-01 (eight roles) + 27-04 (permissions API: /roles/permissions, /me/permissions)
    - web api-client (apiGet/apiPut/apiPost via /api/proxy) + @tanstack/react-query
  provides:
    - web/src/lib/roles.ts (ROLE_SLUGS, Role, ROLE_LABELS, isAdmin/isManager/isGc)
    - web/src/lib/hooks/usePermissions.ts (can(key) from GET /me/permissions)
    - web/src/components/shared/role-select.tsx (RoleSelect)
    - web/src/app/(dashboard)/settings/roles/* (permission-matrix editor)
    - permission-gated sidebar + foreman pages
tech_stack:
  added: []
  patterns:
    - "usePermissions() -> can(key), backed by react-query on /me/permissions (5-min stale)"
    - "Nav gating: NavItem.permission (can) | NavItem.roles (JWT) | ungated"
    - "Matrix editor renders from the API catalog (labels+groups) — no client-side key mirror (DRY)"
    - "Render-time state sync (data.roles !== syncedRoles) instead of setState-in-effect"
key_files:
  created:
    - web/src/lib/roles.ts
    - web/src/lib/hooks/usePermissions.ts
    - web/src/components/shared/role-select.tsx
    - web/src/app/(dashboard)/settings/roles/page.tsx
    - web/src/app/(dashboard)/settings/roles/_components/permission-matrix.tsx
  modified:
    - web/src/types/api.ts (Role import; RoleAssignmentRequest.role: Role; RBAC response types)
    - web/src/components/layout/sidebar.tsx (permission-gated nav + Roles & Permissions link)
    - web/src/app/(dashboard)/foreman/page.tsx (can("foreman.assign"))
    - web/src/app/(dashboard)/foreman/status/[projectId]/page.tsx (isGc helper)
key_decisions:
  - "Editor is API-driven: fetches catalog/roles/defaults, so it auto-tracks the 47-key granular catalog with no duplication."
  - "Owner column is rendered all-on and disabled (locked); a per-role dot marks 'modified from default'."
  - "Save is per-dirty-role PUT; Reset posts /roles/permissions/reset; both invalidate me-permissions so gating refreshes."
  - "Conservative nav gating: existing always-visible items unchanged; only foreman + new Roles link are gated, to avoid over-hiding."
patterns_established:
  - "Effective-permission UI gating via a single hook; server stays the source of truth."
requirements-completed: [ROLE-06, ROLE-07, PERM-06]
duration: ~35min
completed: 2026-07-23
---

# Phase 27-02: Web RBAC Summary

**Owner/admin get a Settings → Roles matrix editor that reads and edits the per-company
permission grid, and the web app gates nav/routes on the user's effective permissions.**

## Accomplishments
- `lib/roles.ts` (shared role source) + `usePermissions()` (`can(key)` from `/me/permissions`).
- `RoleSelect` reusable eight-role picker.
- **Settings → Roles** editor: grouped permission rows × 8 role columns, toggle cells, owner
  locked, per-role dirty tracking, Save (per role) + Reset, "modified from default" markers.
- Sidebar gains a permission-gated **Roles & Permissions** link; foreman pages gate on
  `foreman.assign` / GC helper instead of hardcoded role literals.

## Verification
- `npx tsc --noEmit` clean; `npx eslint` clean on all changed files (incl. the render-time
  state-sync refactor to satisfy react-hooks/set-state-in-effect).

## Notes
- The editor is fully API-driven, so the CRUD-granular 47-key catalog renders without a
  client-side mirror. `RoleAssignmentRequest.role` is now the typed `Role` union.
