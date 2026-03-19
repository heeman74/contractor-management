---
phase: 17-crm-clients-and-contractors
plan: "01"
subsystem: backend-api, web-frontend
tags: [crm, fastapi, typescript, playwright]
dependency_graph:
  requires: []
  provides:
    - GET /api/v1/crm/clients (paginated client list with search)
    - GET /api/v1/crm/clients/{user_id} (client profile with job history)
    - ClientListItem, ClientDetail TypeScript interfaces in api.ts
    - StatusBadge availability colors (available, partially_booked, fully_booked)
    - Playwright test stubs for CRM-01, CRM-02, CONTR-01 through CONTR-04
  affects:
    - backend/app/features/jobs/schemas.py (JobResponse.contractor_name added)
    - backend/app/features/jobs/router.py (_job_with_client_name extended)
tech_stack:
  added: []
  patterns:
    - CrmService delegates to CrmRepository (TenantScopedService/Repository pattern)
    - jobs_count scalar_subquery correlates ClientProfile to avoid N+1
    - sa_inspect guard in _job_with_client_name prevents lazy-raise on contractor
    - Lazy import of Job inside list_client_profiles to avoid circular ORM init
key_files:
  created:
    - backend/app/features/jobs/crm_router.py
    - backend/tests/test_crm_router.py
    - web/tests/phase-17-crm.spec.ts
  modified:
    - backend/app/features/jobs/schemas.py
    - backend/app/features/jobs/crm_repository.py
    - backend/app/features/jobs/crm_service.py
    - backend/app/features/jobs/router.py
    - backend/app/main.py
    - web/src/types/api.ts
    - web/src/components/shared/status-badge.tsx
decisions:
  - "Lazy import of Job model inside list_client_profiles method to break circular ORM mapper init (Job -> Booking circular ref triggers before scheduling models loaded)"
  - "from_profile classmethod uses TYPE_CHECKING import for ClientProfileModel to avoid circular import at module level in schemas.py"
  - "contractor_name on JobResponse is additive-only — no existing fields renamed (protects mobile Dart models per CLAUDE.md)"
metrics:
  duration: "4 minutes"
  completed: "2026-03-19"
  tasks_completed: 2
  files_modified: 10
---

# Phase 17 Plan 01: CRM Router and Type Foundation Summary

CRM API layer with GET /api/v1/crm/clients (paginated + search + jobs_count subquery) and GET /api/v1/crm/clients/{user_id} (profile, job history, properties), plus TypeScript type contracts and StatusBadge availability colors.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | CRM router with list/detail endpoints | d2bc3e8 | crm_router.py, schemas.py, crm_repository.py, crm_service.py, router.py, main.py, test_crm_router.py |
| 2 | TypeScript types, StatusBadge, E2E stubs | 1e283fc | api.ts, status-badge.tsx, phase-17-crm.spec.ts |

## Decisions Made

1. **Lazy import of Job in list_client_profiles** — importing `Job` at module level in crm_repository.py triggered SQLAlchemy mapper initialization before the `Booking` model (referenced in Job's relationships) was loaded. Using a lazy import inside the method body resolves this, matching the pattern already used in `crm_service.get_client_with_job_history`.

2. **TYPE_CHECKING guard for ClientProfileModel in schemas.py** — `from_profile` classmethod needed the ORM type for its signature. Added `from __future__ import annotations` and a `TYPE_CHECKING` import to keep ruff happy without triggering circular import at runtime.

3. **contractor_name is additive-only** — Added to `JobResponse` without renaming any existing fields, protecting the mobile Flutter/Dart models that Dart-serialize this response.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Circular ORM mapper init when importing crm_repository standalone**
- **Found during:** Task 1 verification
- **Issue:** `from app.features.jobs.models import Job` at module level in crm_repository.py triggered `configure_mappers()` before Booking was registered, causing `InvalidRequestError`
- **Fix:** Moved `Job` import to a lazy import inside `list_client_profiles` method body
- **Files modified:** backend/app/features/jobs/crm_repository.py
- **Commit:** d2bc3e8

**2. [Rule 2 - Missing critical functionality] schemas.py missing `from __future__ import annotations`**
- **Found during:** Task 1 ruff check
- **Issue:** `ClientListResponse.from_profile` type annotation referenced `ClientProfile` (ORM model) which ruff flagged as F821 undefined name
- **Fix:** Added `from __future__ import annotations`, `TYPE_CHECKING` guard, and `ClientProfileModel` alias
- **Files modified:** backend/app/features/jobs/schemas.py
- **Commit:** d2bc3e8

## Self-Check: PASSED

All files found, both commits verified, all key content checks passed.
