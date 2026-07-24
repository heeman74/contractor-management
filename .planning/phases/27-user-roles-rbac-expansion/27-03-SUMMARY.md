---
phase: 27-user-roles-rbac-expansion
plan: "03"
subsystem: mobile
tags: [rbac, roles, flutter, dart, riverpod, drift, go_router]
dependency_graph:
  requires:
    - 27-01 (eight roles — the API contract mobile consumes)
  provides:
    - mobile UserRole enum (8 values) with non-throwing fromString, slug, displayLabel, capability getters
    - permission-aware router role guards + screen-variant selection
tech_stack:
  added: []
  patterns:
    - "fromString returns UserRole? (null on unknown) — forward-compatible; callers use whereType<UserRole>()"
    - "Capability getters (isAdminLevel/isManagerLevel/isGcLevel) mirror backend role-sets"
    - "Router guards use any((r)=>r.isAdminLevel) so owner satisfies admin"
key_files:
  created:
    - mobile/test/unit/user_role_test.dart
  modified:
    - mobile/lib/shared/models/user_role.dart (8-value enum + fromString/slug/displayLabel/capabilities)
    - mobile/lib/features/auth/presentation/providers/auth_provider.dart (whereType filter x3)
    - mobile/lib/features/users/data/user_dao.dart (nullable row mapper + whereType filter)
    - mobile/lib/core/routing/app_router.dart (_checkRoleAccess guards + admin/reports variant selection)
    - mobile/lib/core/database/tables/user_roles.dart (role-values doc comment)
    - mobile/lib/shared/screens/profile_screen.dart (role icon/color switches — 8 arms)
    - mobile/lib/features/admin/presentation/screens/team_management_screen.dart (role chip switch — 8 arms)
    - mobile/lib/features/schedule/presentation/widgets/contractor_lane.dart (role color switch — 8 arms)
key_decisions:
  - "CRITICAL FIX: fromString no longer throws — a user holding a new role would previously crash at login/restore."
  - "All four exhaustive `switch (role)` expressions extended with explicit arms for the five new roles (no wildcard)."
  - "Task 5 (consume /me/permissions for UI gating) deferred — server enforces regardless; mobile gating is UX-only."
  - "/contractor area opened to contractor/foreman/worker; /foreman to manager/gc/foreman; owner treated as admin for variants."
patterns_established:
  - "Enum widening discipline: update fromString, slug round-trip, displayLabel, and every exhaustive switch together."
requirements-completed: [ROLE-08, ROLE-09]
duration: ~25min
completed: 2026-07-23
---

# Phase 27-03: Mobile RBAC Summary

**The mobile UserRole enum now covers all eight roles, parses unknown roles safely instead of
crashing, and the router recognizes the new roles for gated areas and screen variants.**

## Accomplishments
- `UserRole` widened to owner/admin/projectManager/gc/foreman/contractor/worker/client with
  non-throwing `fromString`, snake_case `slug`, `displayLabel`, and `isAdminLevel/isManagerLevel/isGcLevel`.
- Auth parse sites and the users DAO drop unknown roles (`whereType<UserRole>()`) rather than throw.
- Router `_checkRoleAccess` + schedule/reports variant selection recognize the new roles; owner
  is treated as admin.
- Four exhaustive `switch (role)` sites (profile icon/color, team chip, schedule lane) extended
  with arms for the five new roles.

## Verification
- `dart analyze lib test` → **0 errors**.
- `flutter test test/unit/user_role_test.dart` → **10 passed**.
- Affected unit suites (routing, auth provider, user DAO, team management) → **42 passed**.

## Notes
- Optional Task 5 (fetch `/me/permissions` for mobile UI gating) was intentionally deferred;
  the backend enforces permissions regardless, so there is no security gap.
