---
phase: 16-quotes-and-invoices
plan: "01"
subsystem: backend-api, web-frontend
tags: [quotes, invoices, list-endpoints, typescript-types, status-badge, api-client, dnd-kit]
dependency_graph:
  requires: [Phase 13 web auth, Phase 8 quote/invoice models]
  provides: [GET /quotes/ list, GET /invoices/ list, Invoice.amount_paid, Quote/Invoice TS types, apiFetchRaw, StatusBadge extensions]
  affects: [16-02 quotes list UI, 16-03 invoices list UI, 16-04 quote builder]
tech_stack:
  added: ["@dnd-kit/core", "@dnd-kit/sortable", "@dnd-kit/utilities", "shadcn/select", "shadcn/popover", "shadcn/calendar"]
  patterns: [TenantScopedRepository.list_all, Alembic additive migration, apiFetchRaw proxy pattern]
key_files:
  created:
    - backend/migrations/versions/0013_add_amount_paid_and_list_endpoints.py
    - backend/tests/test_phase_16_e2e.py
    - web/tests/phase-16-quotes.spec.ts
    - web/tests/phase-16-invoices.spec.ts
    - web/src/components/ui/select.tsx
    - web/src/components/ui/popover.tsx
    - web/src/components/ui/calendar.tsx
  modified:
    - backend/app/features/quotes/router.py
    - backend/app/features/invoices/router.py
    - backend/app/features/invoices/models.py
    - backend/app/features/invoices/schemas.py
    - backend/app/features/invoices/service.py
    - web/src/types/api.ts
    - web/src/components/shared/status-badge.tsx
    - web/src/lib/api-client.ts
    - web/package.json
decisions:
  - "GET /quotes/ inserts before GET /for-job/{job_id} to avoid FastAPI path parameter shadowing"
  - "GET /invoices/ filters soft-deleted records in Python layer since list_all() does not filter them"
  - "apiFetchRaw mirrors apiClient retry/refresh pattern but returns Response instead of parsed JSON"
  - "dnd-kit chosen over react-sortable-hoc per CONTEXT.md recommendation for quote builder drag reorder"
  - "test_setup_invoice re-logins after role assignment to get fresh JWT including client role"
metrics:
  duration: 6 minutes
  completed_date: "2026-03-18"
  tasks_completed: 2
  files_changed: 16
---

# Phase 16 Plan 01: Backend List Endpoints, Invoice amount_paid, TypeScript Types, and Shared Components Summary

Backend list endpoints for quotes and invoices, Invoice.amount_paid migration, TypeScript Quote/Invoice types, StatusBadge extended with 6 new statuses, apiFetchRaw for PDF blob downloads, dnd-kit/shadcn installed, and 6 real integration tests all passing.

## What Was Built

### Task 1: Backend List Endpoints + amount_paid
- **GET /api/v1/quotes/** — admin-only list endpoint returning all active (non-deleted, non-revised) quotes for the tenant; optional `?status=` filter
- **GET /api/v1/invoices/** — admin-only list endpoint returning all non-soft-deleted invoices; optional `?status=` filter
- **Invoice.amount_paid** — new `Numeric(10, 2)` column with `server_default="0"` added to model and migration
- **InvoiceResponse.amount_paid** — new field on Pydantic schema; included in `coerce_decimal` field_validator list
- **MarkPaidRequest.amount_paid** — optional field; `update_payment_status` assigns it to the model when provided
- **Alembic migration 0013** — `op.add_column("invoices", ...)` with `down_revision = "0012"`
- **6 backend integration tests** — all real, no `@pytest.mark.skip` stubs, all passing

### Task 2: Frontend Foundation
- **TypeScript types** — `Quote`, `Invoice`, `QuoteLineItem`, `InvoiceLineItem`, `QuoteTemplate` interfaces added to `web/src/types/api.ts`; type aliases `QuoteStatus`, `InvoiceStatus`, `ItemType`, `DiscountType`
- **StatusBadge colorMap extended** — `viewed` (purple), `expired` (orange), `revised` (gray), `unpaid` (yellow), `partially_paid` (blue), `finalized` (teal)
- **apiFetchRaw helper** — appended to `web/src/lib/api-client.ts`; mirrors `apiClient` retry pattern but returns raw `Response` for PDF/blob downloads
- **dnd-kit installed** — `@dnd-kit/core`, `@dnd-kit/sortable`, `@dnd-kit/utilities` for quote builder drag-and-drop
- **shadcn components** — `select`, `popover`, `calendar` installed for quote builder form
- **Playwright E2E stubs** — 12 stubs in `phase-16-quotes.spec.ts`, 8 stubs in `phase-16-invoices.spec.ts`

## Verification Results

- `ruff check` — all 5 modified backend files pass
- `uv run python -m pytest tests/test_phase_16_e2e.py -x -v` — 6/6 tests passing
- `npx tsc --noEmit` — exits 0, no TypeScript errors

## Deviations from Plan

None — plan executed exactly as written, with one implementation detail: `_setup_invoice` test helper re-logins after assigning the `client` role to get a fresh JWT that includes it (JWT is not mutated by adding a DB role; a new token is needed). This is consistent with the pattern used in `test_phase_8_e2e.py`.

## Self-Check: PASSED

All required files exist. Commits 655ceb2 and 81d7549 verified in git log. All 6 integration tests passing. TypeScript typecheck exits 0.
