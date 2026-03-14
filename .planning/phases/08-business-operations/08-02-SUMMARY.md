---
phase: 08-business-operations
plan: "02"
subsystem: backend
tags: [quotes, invoices, reports, api, sync, pdf, sequential-numbering]
dependency_graph:
  requires:
    - backend/app/features/quotes/models.py
    - backend/app/features/invoices/models.py
    - backend/app/features/reports/schemas.py
    - backend/app/features/pdf/service.py
  provides:
    - backend/app/features/quotes/repository.py
    - backend/app/features/quotes/service.py
    - backend/app/features/quotes/router.py
    - backend/app/features/invoices/repository.py
    - backend/app/features/invoices/service.py
    - backend/app/features/invoices/router.py
    - backend/app/features/reports/service.py
    - backend/app/features/reports/router.py
  affects:
    - backend/app/features/sync/service.py (Phase 8 delta methods added)
    - backend/app/features/sync/router.py (quotes/invoices in delta response)
    - backend/app/features/sync/schemas.py (SyncResponse extended)
    - backend/app/features/companies/models.py (invoice_prefix/sequence columns)
    - backend/app/main.py (3 new routers registered)
tech_stack:
  added: []
  patterns:
    - TenantScopedRepository with class-level eager_load_options
    - isort:split side-effect imports for mapper registration (same as Phase 4)
    - SELECT FOR UPDATE on company row for sequential invoice numbering
    - Plain APIRouter with static routes declared before /{id} parameterized routes
    - from_orm_with_totals() classmethod for computed financial totals
    - fire-and-forget FCM via try/except (notification failures never block operations)
    - QuoteConversionItem from aggregate COUNT/CASE expressions (no N+1)
key_files:
  created:
    - backend/app/features/quotes/repository.py
    - backend/app/features/quotes/service.py
    - backend/app/features/quotes/router.py
    - backend/app/features/invoices/repository.py
    - backend/app/features/invoices/service.py
    - backend/app/features/invoices/router.py
    - backend/app/features/reports/service.py
    - backend/app/features/reports/router.py
  modified:
    - backend/app/features/sync/service.py (4 Phase 8 methods added)
    - backend/app/features/sync/router.py (Phase 8 entities in delta_sync)
    - backend/app/features/sync/schemas.py (SyncResponse extended with 4 fields)
    - backend/app/features/companies/models.py (invoice_prefix/invoice_sequence)
    - backend/app/main.py (quotes, invoices, reports routers included)
decisions:
  - "QuoteRepository mapper registration: isort:split side-effect imports of invoices.models, scheduling.models, users.models before Quote — same pattern as jobs/router.py Phase 4"
  - "InvoiceRepository mapper registration: same side-effect import pattern for quotes.models, scheduling.models, users.models"
  - "SELECT FOR UPDATE on company row for sequential invoice number — atomically increments invoice_sequence, formats as {prefix}-{N:04d}"
  - "Sync delta for client role: quotes filtered to sent/viewed/approved/declined only — drafts not exposed to clients"
  - "quote_line_items and invoice_line_items included as separate flat arrays in sync response — consistent with existing pattern (not nested)"
  - "ReportingService not TenantScopedService — aggregate query service with no base repository; RLS applied via middleware"
  - "Revenue by month uses SUM(quantity * unit_price) per line item — discount/tax not applied in aggregate to keep query simple; full totals available per-invoice via from_orm_with_totals"
  - "ExtendExpiryRequest Pydantic model defined at top of quotes/router.py — avoids E402 out-of-order import"
metrics:
  duration: "11 min"
  completed_date: "2026-03-14"
  tasks_completed: 2
  files_created: 8
  files_modified: 5
---

# Phase 8 Plan 02: Business Operations REST API Summary

**One-liner:** Full quote lifecycle API (create/send/approve/decline/revise/PDF), sequential invoice generation via SELECT FOR UPDATE, 4-metric reporting dashboard, and sync delta extension with role-based quote filtering.

## What Was Built

### Task 1: Quote, Invoice, and Reporting Services with Repositories

**QuoteRepository** (`TenantScopedRepository[Quote]`):
- `get_with_line_items(quote_id)` — selectinload(line_items) + joinedload(job)
- `get_for_job(job_id)` — latest non-deleted, non-revised quote for a job
- `get_active_quotes()` — all non-deleted, non-revised quotes for tenant
- `QuoteTemplateRepository` — list/create/delete templates

**QuoteService** (`TenantScopedService[Quote]`):
- Full 7-state lifecycle: draft → sent → viewed → approved | declined | expired | revised
- `create_quote` — validates job in 'quote' status, creates with line items, appends status_history event
- `update_quote` — draft-only, full line item replacement via DELETE+INSERT
- `send_quote` — draft → sent, appends event, FCM to client (fire-and-forget)
- `record_view` — sets viewed_at only on first view (read receipt), sent → viewed
- `approve_quote` — validates expiry, sent/viewed → approved; checks expiry date
- `decline_quote` — sent/viewed → declined with reason/detail fields
- `revise_quote` — marks old as revised, creates new Quote at revision_number+1
- `extend_expiry` — updates expiry_date, resets expired → sent
- Template management: `create_template`, `save_as_template`, `load_template`, `list_templates`, `delete_template`
- `_append_status_history_event` helper: JSONB list replacement (not in-place mutation per Pitfall 3)

**InvoiceRepository** (`TenantScopedRepository[Invoice]`):
- `get_with_line_items(invoice_id)` — selectinload(line_items) + joinedload(job, quote)
- `get_for_job(job_id)` — most recent non-deleted invoice for a job

**InvoiceService** (`TenantScopedService[Invoice]`):
- `generate_from_quote` — validates job='complete' + approved quote exists, SELECT FOR UPDATE sequential numbering, copies quote line items, transitions job→invoiced
- `generate_manual` — direct invoice without quote, same numbering
- `update_invoice` — pre-finalization edit, full line item replacement
- `finalize_invoice` — sets finalized_at, prevents further edits
- `update_payment_status` — validates no paid→unpaid regression

**Sequential invoice numbering** (SELECT FOR UPDATE pattern):
```python
result = await self.db.execute(
    select(Company).where(Company.id == company_id).with_for_update()
)
company.invoice_sequence += 1
return f"{prefix}-{company.invoice_sequence:04d}"  # e.g. "INV-0001"
```

**ReportingService** (standalone, not TenantScopedService):
- `get_dashboard` — 4 aggregate queries (RLS enforced via middleware):
  1. Jobs by status: `COUNT(*) GROUP BY status`
  2. Revenue by month: `SUM(qty * price) CASE paid/unpaid GROUP BY YYYY-MM`
  3. Contractor utilization: booked hours (from bookings) vs available hours (workdays × 8h)
  4. Quote conversion: approved / (approved + declined), CASE expressions
- `get_contractor_stats` — limited view (no revenue), filtered to own jobs/bookings

**Company model updated** with `invoice_prefix` and `invoice_sequence` mapped columns (added by migration 0011 ALTER TABLE).

### Task 2: REST API Routers, Sync Extension, and main.py Wiring

**Quotes router** (`/api/v1/quotes`):
- 14 endpoints total; static routes (`/templates`, `/for-job/{job_id}`) declared BEFORE `/{quote_id}` to prevent FastAPI path shadowing
- GET `/{quote_id}` auto-calls `record_view()` for client role (read receipt)
- GET `/{quote_id}/pdf` streams WeasyPrint bytes as `application/pdf`

**Invoices router** (`/api/v1/invoices`):
- 8 endpoints; `/generate/{job_id}` and `/for-job/{job_id}` declared BEFORE `/{invoice_id}`
- PDF download included

**Reports router** (`/api/v1/reports`):
- GET `/dashboard` — admin only, all 4 metrics
- GET `/contractor` — contractor or admin, own utilization + job counts

**Sync delta extended** — Phase 8 entities added to `SyncResponse`:
```python
quotes: list[QuoteResponse] = []
quote_line_items: list[QuoteLineItemResponse] = []
invoices: list[InvoiceResponse] = []
invoice_line_items: list[InvoiceLineItemResponse] = []
```
- Client role: quotes filtered to `sent/viewed/approved/declined` only (drafts hidden)
- Line items included as separate flat arrays (consistent with existing sync pattern)

**main.py**: 3 new routers registered after existing Phase 7 routers.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Mapper registration side-effect imports required in repositories**
- **Found during:** Task 1 verification
- **Issue:** `QuoteRepository` at class level defines `eager_load_options = [selectinload(Quote.line_items)]` which triggers `configure_mappers()`. At that point, `Invoice` and `Booking` models were not yet registered, causing `InvalidRequestError`.
- **Fix:** Added `# isort: split` side-effect imports of `app.features.invoices.models`, `app.features.scheduling.models`, `app.features.users.models` in both `quotes/repository.py` and `invoices/repository.py` — same pattern as Phase 4 `jobs/router.py`.
- **Files modified:** `quotes/repository.py`, `invoices/repository.py`
- **Commit:** e3ff05e

**2. [Rule 1 - Bug] ExtendExpiryRequest inline class caused E402 ruff error**
- **Found during:** Task 2 ruff check
- **Issue:** `ExtendExpiryRequest(BaseModel)` was defined after the `# isort: split` block with an out-of-order `from pydantic import BaseModel` causing E402.
- **Fix:** Moved `ExtendExpiryRequest` to the top of `quotes/router.py` with `pydantic.BaseModel` imported at the top-level import block.
- **Files modified:** `quotes/router.py`
- **Commit:** a8ddc8c

**3. [Rule 2 - Missing] invoice_prefix/invoice_sequence missing from Company ORM model**
- **Found during:** Task 1 InvoiceService implementation
- **Issue:** Migration 0011 added `invoice_prefix` and `invoice_sequence` columns to `companies` via ALTER TABLE, but the `Company` ORM model had no mapped columns for them. The `SELECT FOR UPDATE` pattern requires the ORM to see these columns.
- **Fix:** Added `invoice_prefix: Mapped[str]` and `invoice_sequence: Mapped[int]` to `Company` model with matching `server_default` values.
- **Files modified:** `backend/app/features/companies/models.py`
- **Commit:** e3ff05e

## Self-Check: PASSED

All 8 created files exist on disk. Both task commits verified in git log (e3ff05e, a8ddc8c).
