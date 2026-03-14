---
phase: 08-business-operations
plan: "01"
subsystem: backend
tags: [quotes, invoices, pdf, migration, orm, schemas, weasyprint]
dependency_graph:
  requires: []
  provides:
    - backend/migrations/versions/0011_business_operations_tables.py
    - backend/app/features/quotes/models.py
    - backend/app/features/invoices/models.py
    - backend/app/features/quotes/schemas.py
    - backend/app/features/invoices/schemas.py
    - backend/app/features/reports/schemas.py
    - backend/app/features/pdf/service.py
  affects:
    - backend/app/features/jobs/models.py (quotes/invoices FK to jobs)
    - backend/app/features/companies/models.py (invoice_prefix/sequence columns added)
tech_stack:
  added:
    - weasyprint>=68.1 (PDF generation from HTML via libpango/libcairo)
    - jinja2>=3.1.0 (HTML template rendering)
  patterns:
    - TenantScopedModel inheritance for all 5 new ORM entities
    - lazy="raise" on all relationships (N+1 guard)
    - Thread pool executor for blocking WeasyPrint PDF conversion
    - Computed totals via from_orm_with_totals() classmethod
    - Graceful WeasyPrint import error at call time (not import time)
key_files:
  created:
    - backend/migrations/versions/0011_business_operations_tables.py
    - backend/app/features/quotes/__init__.py
    - backend/app/features/quotes/models.py
    - backend/app/features/quotes/schemas.py
    - backend/app/features/invoices/__init__.py
    - backend/app/features/invoices/models.py
    - backend/app/features/invoices/schemas.py
    - backend/app/features/reports/__init__.py
    - backend/app/features/reports/schemas.py
    - backend/app/features/pdf/__init__.py
    - backend/app/features/pdf/service.py
    - backend/app/features/pdf/templates/quote.html
    - backend/app/features/pdf/templates/invoice.html
  modified:
    - backend/requirements.txt (added weasyprint, jinja2)
decisions:
  - "WeasyPrint import deferred to call time — OSError on system lib absence raised as RuntimeError with clear install link, not import error"
  - "PDF templates use inline CSS only — no external stylesheets or web fonts for WeasyPrint compatibility"
  - "from_orm_with_totals() classmethod on QuoteResponse/InvoiceResponse computes subtotal/discount/tax/total inline — not stored columns"
  - "line_items_json stored as TEXT in QuoteTemplate — avoids join table for templates, parsed at service layer"
  - "invoice_prefix/invoice_sequence added via ALTER TABLE in migration 0011 — not a new table"
  - "Module-level pdf_service singleton — no DB dependency, safe to instantiate at import time"
metrics:
  duration: "8 min"
  completed_date: "2026-03-13"
  tasks_completed: 2
  files_created: 13
  files_modified: 1
---

# Phase 8 Plan 01: Business Operations Data Foundation Summary

**One-liner:** Migration 0011 + ORM models + Pydantic schemas for quotes/invoices/templates, with WeasyPrint PDF generation service using Jinja2 HTML templates.

## What Was Built

### Task 1: Migration 0011 and ORM Models

**Alembic migration 0011** creates 5 new tables with RLS tenant isolation:
- `quotes` — 7-status machine (draft/sent/viewed/approved/declined/expired/revised), revision number, tax/discount fields, audit timestamps
- `quote_line_items` — labor/material items with CASCADE delete from parent quote
- `quote_templates` — reusable line item JSON collections for fast quote creation
- `invoices` — payment tracking (unpaid/partially_paid/paid), links to job and optional quote
- `invoice_line_items` — items with CASCADE delete from parent invoice

Also adds `invoice_prefix` and `invoice_sequence` columns to `companies` table for sequential invoice number generation.

All 5 tables get:
- RLS with `tenant_isolation` policy using `app.current_company_id`
- `set_updated_at` trigger (function created in migration 0002)
- FK indexes for efficient joins

**ORM Models** (all inherit `TenantScopedModel`):
- `Quote` — with `job`, `line_items`, `invoices` relationships (all `lazy="raise"`)
- `QuoteLineItem` — with `quote` back-reference
- `QuoteTemplate` — `line_items_json` as Text, parsed at service layer
- `Invoice` — with `job`, `quote`, `line_items` relationships
- `InvoiceLineItem` — with `invoice` back-reference

**Pydantic Schemas:**
- `QuoteCreate`, `QuoteUpdate`, `QuoteResponse`, `QuoteLineItemCreate/Response`, `QuoteTemplateCreate/Response`, `DeclineQuoteRequest`
- `InvoiceCreate`, `InvoiceUpdate`, `InvoiceResponse`, `InvoiceLineItemCreate/Response`, `MarkPaidRequest`
- `QuoteResponse.from_orm_with_totals()` and `InvoiceResponse.from_orm_with_totals()` compute subtotal/discount/tax/total from loaded line items
- Discount validation: `percent` type cannot exceed 100, `discount_type` required when `discount_value > 0`

**Report Schemas:**
- `DashboardResponse` combining `JobsByStatusItem`, `RevenueByMonthItem`, `ContractorUtilizationItem`, `QuoteConversionItem`
- `DateRangeFilter` query parameter schema

### Task 2: PDF Generation Service

**PdfService class:**
- `generate_quote_pdf(quote, company) -> bytes` — renders `quote.html` Jinja2 template
- `generate_invoice_pdf(invoice, company) -> bytes` — renders `invoice.html` Jinja2 template
- Both methods compute financial totals inline before template rendering
- `_html_to_pdf()` runs synchronously in `run_in_executor()` thread pool — never blocks event loop
- WeasyPrint import deferred to call time with clear `RuntimeError` if system libs absent

**Jinja2 HTML Templates:**
- `quote.html` — company header, revision badge, status badge, meta grid, line items table, totals, admin notes, decline details
- `invoice.html` — invoice number, payment status badge, overdue alert, PAID stamp, line items table, totals, payment section
- Both use A4 page dimensions with inline CSS (WeasyPrint requires inline styles — no external CSS files)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] WeasyPrint system library handling**
- **Found during:** Task 2 verification
- **Issue:** WeasyPrint Python package installed but macOS development machine lacks libpango system library — `import weasyprint` raises `OSError` on this platform
- **Fix:** Deferred WeasyPrint import inside `_html_to_pdf()` method — import error at call time with a clear message and install link, not at module import time. Service instantiation and template loading still work. Production deployments with libpango will work correctly.
- **Files modified:** `backend/app/features/pdf/service.py`
- **Commit:** 9d8651a

**2. [Rule 1 - Auto-fix] Ruff linting errors in new files**
- **Found during:** Both tasks
- **Issue:** `I001` (import sorting), `SIM102` (nested `if` → single `and` condition)
- **Fix:** `ruff check --fix` for import sorting; manual fix for SIM102 (combine nested ifs into single `if` with `and`)
- **Commits:** 7a8a3cd, 9d8651a

## Self-Check: PASSED

Files verified:
- `backend/migrations/versions/0011_business_operations_tables.py` — FOUND
- `backend/app/features/quotes/models.py` — FOUND
- `backend/app/features/invoices/models.py` — FOUND
- `backend/app/features/quotes/schemas.py` — FOUND
- `backend/app/features/invoices/schemas.py` — FOUND
- `backend/app/features/reports/schemas.py` — FOUND
- `backend/app/features/pdf/service.py` — FOUND
- `backend/app/features/pdf/templates/quote.html` — FOUND
- `backend/app/features/pdf/templates/invoice.html` — FOUND

Commits verified:
- `7a8a3cd` feat(08-01): add migration 0011 and ORM models
- `9d8651a` feat(08-01): add PDF generation service with WeasyPrint and Jinja2 templates

Import verification: All models and schemas imported successfully. PdfService instantiated with templates loaded.
