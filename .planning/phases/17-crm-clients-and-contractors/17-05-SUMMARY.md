---
phase: 17-crm-clients-and-contractors
plan: "05"
subsystem: ui
tags: [nextjs, playwright, pytest, crm, typescript, fastapi]

# Dependency graph
requires:
  - phase: 17-02
    provides: CRM client list and detail pages built
  - phase: 17-03
    provides: contractor list, profile, and schedule editor pages built
  - phase: 17-04
    provides: contractor schedule editor (weekly grid + date overrides) built

provides:
  - Cross-page CRM links from job/quote/invoice detail and schedule calendar
  - Playwright E2E test suite covering all 6 CRM/CONTR requirements (9 tests)
  - Backend integration tests for CRM router (13 tests, 2 files)

affects: [phase-18, testing, crm]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "contractor_name additive field on Job TypeScript interface (mirrors backend additive-only rule)"
    - "CRM cross-page links: text-indigo-600 hover:text-indigo-800 hover:underline on all Link components"
    - "ContractorLaneHeader wraps resource name in Next.js Link with stopPropagation to avoid calendar drag conflicts"

key-files:
  created:
    - backend/tests/test_phase_17_e2e.py
    - web/tests/phase-17-crm.spec.ts (rewritten)
  modified:
    - web/src/app/(dashboard)/jobs/[id]/page.tsx
    - web/src/app/(dashboard)/quotes/[id]/page.tsx
    - web/src/app/(dashboard)/invoices/[id]/page.tsx
    - web/src/app/(dashboard)/schedule/_components/contractor-lane-header.tsx
    - web/src/types/api.ts
    - backend/tests/test_crm_router.py

key-decisions:
  - "contractor_name added to Job TypeScript interface as nullable string (additive, matches backend JobResponse field added in phase 17-02)"
  - "ContractorLaneHeader Link uses e.stopPropagation() to prevent react-big-calendar from treating link click as a drag-start event"
  - "Backend integration tests use tenant_a_client fixture (not client/admin_token) — matches conftest.py fixture naming convention"
  - "test_client_detail_response_shape seeds a client profile by assigning 'client' role to the tenant_a admin user via /api/v1/users/{user_id}/roles"

patterns-established:
  - "Playwright tests: resilient to empty data — check firstRow.isVisible() before clicking to detail pages"
  - "Backend E2E tests: import app.features.scheduling.models at top to register all ORM mappers before tests run"

requirements-completed:
  - CRM-01
  - CRM-02
  - CONTR-01
  - CONTR-02
  - CONTR-03
  - CONTR-04

# Metrics
duration: 25min
completed: 2026-03-19
---

# Phase 17 Plan 05: CRM Integration — Cross-Links, E2E Tests, and Backend Tests Summary

**CRM cross-page links across job/quote/invoice/schedule, 9 Playwright E2E tests, and 13 backend integration tests validating all 6 CRM/CONTR requirements**

## Performance

- **Duration:** 25 min
- **Started:** 2026-03-19T07:00:00Z
- **Completed:** 2026-03-19T07:25:00Z
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments

- Job detail page contractor link shows `contractor_name` (was truncated UUID), client link shows `client_name` with full indigo accent styling
- Invoice detail client field upgraded from plain text to clickable `/clients/{id}` Link
- Schedule calendar contractor lane headers are now clickable links to `/contractors/{id}` via updated `ContractorLaneHeader` component
- 9 Playwright E2E tests cover CRM-01 (client list/search), CRM-02 (client detail), CONTR-01 (contractor list), CONTR-02 (profile), CONTR-03 (schedule editor grid), CONTR-04 (date overrides), and cross-page link verification
- 13 backend integration tests in two files validate all CRM router endpoints against a real test database

## Task Commits

Each task was committed atomically:

1. **Task 1: Add cross-page CRM links** - `6a3e3bb` (feat)
2. **Task 2: Backend integration tests for CRM router** - `7ffd167` (feat)
3. **Task 3: Playwright E2E tests covering all CRM/CONTR requirements** - `e38daef` (feat)

## Files Created/Modified

- `web/src/types/api.ts` - Added `contractor_name: string | null` to Job interface (additive)
- `web/src/app/(dashboard)/jobs/[id]/page.tsx` - Contractor/client links now show names, use hover:text-indigo-800 styling
- `web/src/app/(dashboard)/quotes/[id]/page.tsx` - Client link updated to hover:text-indigo-800 for consistency
- `web/src/app/(dashboard)/invoices/[id]/page.tsx` - Client plain text upgraded to `/clients/{id}` Link
- `web/src/app/(dashboard)/schedule/_components/contractor-lane-header.tsx` - Name wrapped in `/contractors/{id}` Link with stopPropagation
- `web/tests/phase-17-crm.spec.ts` - Rewritten: 9 real tests replacing 8 test.skip stubs
- `backend/tests/test_phase_17_e2e.py` - New: 7 tests for client list and detail endpoints
- `backend/tests/test_crm_router.py` - Rewritten: 6 real tests replacing 4 @pytest.mark.skip stubs

## Decisions Made

- `contractor_name` added to Job TypeScript interface — additive field matching backend `JobResponse` (established in Phase 17-02 per STATE.md decision)
- `ContractorLaneHeader` Link uses `e.stopPropagation()` to prevent react-big-calendar from treating link click as a drag-start event
- Backend tests use `tenant_a_client` fixture (not `client`/`admin_token`) matching conftest.py naming convention from Phase 16 tests
- Role assignment endpoint is `/api/v1/users/{user_id}/roles` with body `{user_id, role}` — confirmed from Phase 16 E2E test pattern

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Job detail showed truncated UUID instead of contractor_name**
- **Found during:** Task 1 (cross-page links)
- **Issue:** Existing contractor link displayed `job.contractor_id.slice(0, 8)` — unusable for navigation context
- **Fix:** Updated display to use `job.contractor_name` (requires adding field to TypeScript interface) with fallback to truncated ID
- **Files modified:** `web/src/types/api.ts`, `web/src/app/(dashboard)/jobs/[id]/page.tsx`
- **Verification:** TypeScript compiles without errors
- **Committed in:** `6a3e3bb`

**2. [Rule 1 - Bug] Invoice detail showed client_name as plain text (not a link)**
- **Found during:** Task 1 — inspecting the invoice detail sidebar
- **Issue:** `job?.client_name ?? "—"` was rendered as plain `<p>` tag, unlike quote detail which already had a Link
- **Fix:** Wrapped in `<Link href={/clients/${job.client_id}}>` with conditional rendering
- **Files modified:** `web/src/app/(dashboard)/invoices/[id]/page.tsx`
- **Committed in:** `6a3e3bb`

**3. [Rule 1 - Bug] Backend test used wrong role endpoint path**
- **Found during:** Task 2 — test_client_detail_response_shape failed with 404
- **Issue:** Initial test used `/api/v1/users/roles` (wrong), actual endpoint is `/api/v1/users/{user_id}/roles`
- **Fix:** Corrected endpoint path; also added `user_id` to request body to match Phase 16 test pattern
- **Files modified:** `backend/tests/test_phase_17_e2e.py`
- **Verification:** All 13 backend tests pass
- **Committed in:** `7ffd167`

---

**Total deviations:** 3 auto-fixed (Rule 1 bugs)
**Impact on plan:** All fixes were required for correctness — client link in invoice was a missing feature, contractor name display was a UX issue, role endpoint was a test implementation error.

## Issues Encountered

- Quote detail page already had a `/clients/{id}` Link (correct from earlier phases) — only needed to add `hover:text-indigo-800` for styling consistency.
- Schedule calendar uses a dedicated `ContractorLaneHeader` component — plan's description of wrapping `resource.resourceTitle` was slightly off, but the pattern was the same (wrap `resource.name` in a `<Link>`).

## Next Phase Readiness

- Phase 17 is complete — all 6 CRM/CONTR requirements implemented and tested
- All cross-page CRM links functional: job detail → client/contractor, quote detail → client, invoice detail → client, schedule calendar → contractor
- Playwright E2E suite ready to run against running application
- Backend integration tests fully green (13/13 passing)

---
*Phase: 17-crm-clients-and-contractors*
*Completed: 2026-03-19*
