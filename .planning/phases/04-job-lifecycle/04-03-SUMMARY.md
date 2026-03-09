---
phase: 04-job-lifecycle
plan: "03"
subsystem: backend-service-layer
tags: [crm, job-request, rating, service-layer, orm, eager-loading, tenant-scoped]
dependency_graph:
  requires: [04-01]
  provides: [CrmRepository, CrmService, RequestService, RatingService]
  affects: [04-04-job-router]
tech_stack:
  added: []
  patterns:
    - TenantScopedRepository/Service inheritance for all new classes
    - joinedload for many-to-one relationships (ClientProfile.user, JobRequest.client)
    - selectinload for one-to-many relationships (Job.ratings)
    - lazy import at method level to break circular imports (crm_service -> Job, request_service -> User/UserRole)
    - AVG aggregate via func.avg for denormalized rating recalculation
    - 30-day rating window enforced by scanning status_history JSONB array
    - Anonymous web form submission: email lookup -> existing user or new User+UserRole(client)
key_files:
  created:
    - backend/app/features/jobs/crm_repository.py
    - backend/app/features/jobs/crm_service.py
    - backend/app/features/jobs/request_service.py
    - backend/app/features/jobs/rating_service.py
  modified: []
decisions:
  - "RequestService._accept_request creates Job directly (not via JobService) — avoids circular service import while still pre-filling all fields from request"
  - "Anonymous submission with submitted_email creates new User+UserRole(client) inline — reuses same User model creation pattern from Phase 1 UserService"
  - "_validate_rating_window: no 'complete' entry in status_history treated as open window — supports invoiced-without-complete flow without blocking ratings"
  - "recalculate_average_rating uses lazy import of CrmRepository inside RatingService._update_client_average_rating — keeps modules decoupled"
  - "RequestRepository.find_user_by_email uses lazy import of User model at method level — avoids top-level circular import"
metrics:
  duration: "4 min"
  completed: "2026-03-08"
  tasks: 2
  files: 4
---

# Phase 4 Plan 03: CRM, Request, and Rating Service Layer Summary

**One-liner:** Four service/repository classes implementing client CRM with search, saved properties, job request submit/accept/decline flow with anonymous user creation, and mutual ratings with 30-day window enforcement via status_history JSONB scanning.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | CRM repository and service — client profiles and saved properties | 4c830d3 | crm_repository.py, crm_service.py |
| 2 | Request service and rating service | 35a4562 | request_service.py, rating_service.py |

## What Was Built

### CrmRepository (crm_repository.py)

`TenantScopedRepository[ClientProfile]` with 7 methods:

1. **get_client_profile(user_id)** — SELECT with `joinedload(user)` + `joinedload(preferred_contractor)`
2. **get_or_create_profile(user_id, company_id)** — Returns existing or creates new profile, reloads with eager joins
3. **list_client_profiles(company_id, search_term, offset, limit)** — Joins User table for case-insensitive ilike search on first_name, last_name, email; ordered by last_name then created_at
4. **get_client_properties(client_id)** — Lists saved properties with `joinedload(job_site)`, defaults first
5. **add_client_property(...)** — Unsets existing defaults via bulk UPDATE before adding new default; reloads with eager job_site
6. **update_average_rating(client_profile_id, new_average)** — Bulk UPDATE on ClientProfile.average_rating field
7. **get_client_notes(client_id, company_id)** — Scalar SELECT of admin_notes column
8. **recalculate_average_rating(ratee_id)** — AVG(stars) aggregate from ratings table WHERE ratee_id matches; returns Decimal(2dp) or None

### CrmService (crm_service.py)

`TenantScopedService[ClientProfile]` with 7 methods:

1. **get_profile(user_id)** — Delegate to repository
2. **create_or_update_profile(user_id, company_id, data)** — Get-or-create then apply non-None fields (PATCH semantics via `model_dump(exclude_none=True)`)
3. **list_clients(company_id, search_term, offset, limit)** — Delegate with pagination
4. **get_client_with_job_history(user_id)** — Profile + jobs list (lazy imports `Job` and `select` to avoid circular); returns `(ClientProfile, list[Job])`
5. **manage_properties(client_id, company_id)** — List all saved properties
6. **add_property(...)** — Delegate to repository with default-unset logic
7. **remove_property(property_id)** — Soft-delete via `crm_repo.soft_delete()`; raises 404 on missing

### RequestService (request_service.py)

`RequestRepository(TenantScopedRepository[JobRequest])` + `RequestService(TenantScopedService[JobRequest])`:

**Repository methods:**
- `get_with_relations(request_id)` — Eager-loads client + converted_job
- `list_pending(company_id, offset, limit)` — Pending queue ordered oldest-first
- `list_for_client(client_id)` — Client's own submissions newest-first
- `find_user_by_email(email, company_id)` — Returns user_id or None (lazy User import)

**Service methods:**
1. **submit_request(data, company_id, client_id, photo_paths)** — For anonymous forms: email lookup → existing user or creates new `User` + `UserRole(client)` inline. Stores photo paths in JSONB array.
2. **list_pending_requests(company_id, ...)** — Review queue delegate
3. **review_request(request_id, action, admin_user_id, ...)** — Validates 'pending' status, dispatches to accept/decline/info_requested handler
4. **_accept_request(job_request, admin_user_id)** — Creates `Job` at Quote stage with status_history entry, sets `converted_job_id`; eager-loads client/contractor/ratings on result
5. **get_request(request_id)** — Single request with 404 on missing
6. **list_requests_for_client(client_id)** — Client's submissions

### RatingService (rating_service.py)

`RatingRepository(TenantScopedRepository[Rating])` + `RatingService(TenantScopedService[Rating])`:

**Repository methods:**
- `get_rating_for_job_direction(job_id, direction)` — UNIQUE constraint pre-check
- `list_for_job(job_id)` — Both directions with rater/ratee eager-loaded
- `list_for_user(user_id)` — Profile display, newest-first, job eager-loaded

**Service methods:**
1. **create_rating(...)** — 4-step validation: job status check (complete/invoiced), unique direction check (409 on duplicate), 30-day window validation, create Rating; then auto-updates ClientProfile.average_rating if admin_to_client
2. **update_rating(rating_id, stars, review_text, user_id)** — 403 for non-rater, re-validates window, recalculates average
3. **get_ratings_for_job(job_id)** — Both directions
4. **get_ratings_for_user(user_id)** — All where ratee_id matches
5. **_validate_rating_window(job)** — Scans status_history JSONB for most recent 'complete' entry; graceful fallback on missing/malformed timestamp; raises 422 if > 30 days ago
6. **_update_client_average_rating(ratee_id)** — Lazy import of CrmRepository; calls recalculate_average_rating + update_average_rating via profile lookup

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Lint] Unused `selectinload` import in crm_repository.py**
- **Found during:** Task 1 ruff check
- **Issue:** `selectinload` imported but not used at module level (only `joinedload` needed for crm_repository class-level eager_load_options)
- **Fix:** Removed `selectinload` from import; `selectinload` is still used in request_service.py where needed
- **Files modified:** crm_repository.py
- **Commit:** 4c830d3

## Self-Check: PASSED

- FOUND: backend/app/features/jobs/crm_repository.py
- FOUND: backend/app/features/jobs/crm_service.py
- FOUND: backend/app/features/jobs/request_service.py
- FOUND: backend/app/features/jobs/rating_service.py
- FOUND commit 4c830d3: feat(04-03): CRM repository and service — client profiles and saved properties
- FOUND commit 35a4562: feat(04-03): Request service and rating service with eligibility validation
- All 4 modules importable in full app context
- ruff check passes on all new files
