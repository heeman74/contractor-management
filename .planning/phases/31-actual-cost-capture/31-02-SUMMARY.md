---
phase: 31-actual-cost-capture
plan: 02
subsystem: api
tags: [fastapi, sqlalchemy, postgres, rls, finance, cost-receipts, file-upload]

# Dependency graph
requires:
  - phase: 31-actual-cost-capture
    plan: 01
    provides: "cost_receipts table (migration 0034), CostReceipt model, CostReceiptResponse schema, gated cost-entry CRUD router/service/repository"
provides:
  - "POST/GET/DELETE /api/v1/cost-entries/{id}/receipts — upload, list, soft-delete receipts, gated by finance.manage/finance.view"
  - "Authenticated, RLS-scoped /files/cost-receipts/{cost_entry_id}/{filename} serving via serve_router's cost-receipts branch"
  - "Receipt E2E coverage: upload+fetch, multiple receipts per entry, cross-tenant 404, 403-for-non-finance on every receipt endpoint"
affects: [33-margin-tracking, 35-financial-dashboard]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Multipart upload helper mirrors _save_task_attachment_file exactly: uuid4-suffixed filename under uploads/{category}/{parent_id}/, 25MB cap -> 413, returns /files/{category}/... remote_url"
    - "serve_router branch is an RLS-scoped existence query on the exact remote_url (not a bare UUID-shape check) — this is what makes cross-tenant requests resolve to zero rows -> 404"
    - "delete_receipt takes both cost_entry_id and receipt_id and 404s on mismatch — defends against a receipt_id from a different cost entry being deleted through this endpoint (confused-deputy guard)"

key-files:
  created: []
  modified:
    - backend/app/features/finance/router.py
    - backend/app/features/finance/service.py
    - backend/app/features/finance/repository.py
    - backend/app/features/files/serve_router.py
    - backend/tests/test_phase_31_e2e.py

key-decisions:
  - "delete_receipt service method validates receipt.cost_entry_id == the URL's cost_entry_id before soft-deleting (not in the plan's literal wording, but a straightforward Rule 2 correctness fix — the nested route implies that relationship and should enforce it)"
  - "Receipt file existence check reused the task-attachments template verbatim per the plan's explicit instruction — no UUID-shape shortcut, since that would defeat the tenant-isolation guarantee (31-RESEARCH.md Pitfall 6)"

requirements-completed: [COST-03]

# Metrics
duration: 15min
completed: 2026-07-26
---

# Phase 31 Plan 02: Receipt Upload, Serving, and E2E Coverage

**Multipart receipt upload/list/soft-delete on cost entries plus an RLS-scoped `cost-receipts` branch in the authenticated file-serving router, covering COST-03 end-to-end.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-07-26T04:49Z
- **Completed:** 2026-07-26T04:53Z
- **Tasks:** 3 completed
- **Files modified:** 5

## Accomplishments

- Owner/PM can `POST /cost-entries/{id}/receipts` (multipart file + optional caption), storing the file under `uploads/cost-receipts/{cost_entry_id}/{uuid}{ext}` and returning a `/files/cost-receipts/...` URL — verified end-to-end by fetching that URL back and getting the bytes (200).
- A cost entry supports zero-to-many receipts: `test_multiple_receipts_per_cost_entry` uploads two files to one entry and confirms `GET /cost-entries/{id}/receipts` returns both.
- Tenant B gets 404 (not the file bytes) when requesting Tenant A's receipt URL — the `cost-receipts` serve branch queries `CostReceipt.remote_url` under RLS, so a cross-tenant row simply doesn't exist for the query.
- A non-finance role (admin) gets 403 on upload, list, and delete receipt endpoints, extending Phase 31's existing 403-coverage pattern to receipts.
- Delete is a soft-delete (`deleted_at`), consistent with the rest of the finance domain; deleting a receipt whose `cost_entry_id` doesn't match the URL's now 404s rather than silently succeeding.

## Task Commits

Each task was committed atomically:

1. **Task 1: Receipt upload/list/delete endpoints + service/repository receipt methods** - `6f2f7e4` (feat)
2. **Task 2: serve_router cost-receipts branch (RLS-scoped existence check)** - `f9cd3ee` (feat)
3. **Task 3: Extend test_phase_31_e2e.py with receipt E2E** - `6bcfca7` (test)

## Files Created/Modified

- `backend/app/features/finance/router.py` - `_save_cost_receipt_file` helper (25MB cap -> 413), `POST/GET/DELETE /cost-entries/{cost_entry_id}/receipts[/{receipt_id}]` endpoints gated by `finance.manage`/`finance.view`; upload 404s via `get_entry_or_404` first so a forged/foreign cost_entry_id can't create an orphan receipt
- `backend/app/features/finance/service.py` - `FinanceService.add_receipt`/`list_receipts`/`delete_receipt` (delete validates the receipt belongs to the given cost entry)
- `backend/app/features/finance/repository.py` - `FinanceRepository.list_receipts_for_entry` (deleted_at filtered), `get_receipt_or_404`, `soft_delete_receipt`
- `backend/app/features/files/serve_router.py` - new `cost-receipts` branch copied from the `task-attachments` template; imports `CostReceipt` from `app.features.finance.models`; docstring updated with the new path shape
- `backend/tests/test_phase_31_e2e.py` - `_create_cost_entry` helper + 4 new tests: `test_upload_and_fetch_cost_receipt`, `test_multiple_receipts_per_cost_entry`, `test_other_tenant_cannot_fetch_cost_receipt`, `test_non_finance_role_403_on_every_receipt_endpoint`

## Decisions Made

- **Nested-route ownership check on delete**: the plan described `DELETE /cost-entries/{cost_entry_id}/receipts/{receipt_id}` but didn't explicitly call out validating that `receipt_id` belongs to `cost_entry_id`. Added that check (404 on mismatch) in the service layer as a Rule 2 correctness fix — the URL shape implies the relationship, and without the check any receipt_id known to the caller's tenant could be deleted through any cost_entry_id's delete route.
- **Verbatim RLS-scoped existence check in serve_router**: followed the plan's explicit instruction to copy the `task-attachments` branch pattern exactly (row-existence query, not a UUID-format check) — this is the one thing that actually enforces cross-tenant 404 (Pitfall 6 in 31-RESEARCH.md).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] delete_receipt didn't validate cost_entry_id/receipt_id relationship**
- **Found during:** Task 1 (writing the delete endpoint/service method)
- **Issue:** The plan's delete handler only needed `receipt_id` to soft-delete a row; nothing enforced that the receipt actually belongs to the `cost_entry_id` in the URL path, so a receipt from a different cost entry (same tenant) could be deleted through the wrong route.
- **Fix:** `FinanceService.delete_receipt` now takes `cost_entry_id` and `receipt_id`, fetches the receipt, and 404s if `receipt.cost_entry_id != cost_entry_id` before soft-deleting.
- **Files modified:** `backend/app/features/finance/service.py`, `backend/app/features/finance/router.py`
- **Verification:** Covered indirectly by the passing receipt E2E suite (no regression); no dedicated mismatch test was added since it wasn't in the plan's required test list, but the fix is unit-level cheap and matches the pattern the rest of the finance domain uses.
- **Committed in:** `6f2f7e4` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 2)
**Impact on plan:** Low-risk correctness hardening on the delete path; no scope creep, no new endpoints or schema.

## Issues Encountered

None - all three tasks' verification and acceptance criteria passed on the first implementation, including the full `test_phase_31_e2e.py` (13 tests) and `test_file_serving_auth_e2e.py` (12 tests) regression runs.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- COST-03 is fully delivered: receipt upload, list, soft-delete, and authenticated/RLS-scoped serving all work and are covered by E2E tests.
- Phase 31's backend is now complete for cost-entry CRUD + receipts (Plans 31-01 and 31-02). Remaining Phase 31 plans (31-03/04/05, if scoped for web/mobile UI) can build on a stable `/api/v1/cost-entries` + `/api/v1/cost-entries/{id}/receipts` + `/files/cost-receipts/...` API surface.
- No blockers.

---
*Phase: 31-actual-cost-capture*
*Completed: 2026-07-26*

## Self-Check: PASSED

All 5 modified/created code files found on disk; all three task commit hashes (`6f2f7e4`, `f9cd3ee`, `6bcfca7`) found in git history.
