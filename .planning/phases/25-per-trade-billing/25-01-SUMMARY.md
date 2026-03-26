---
phase: 25-per-trade-billing
plan: "01"
subsystem: backend
tags: [billing, migration, models, api, rls]
dependency_graph:
  requires: []
  provides:
    - billing_milestones_table
    - per_trade_quote_schema
    - per_trade_invoice_schema
    - billing_milestone_crud_api
  affects:
    - quotes_feature
    - invoices_feature
tech_stack:
  added:
    - billing_milestones SQLAlchemy model (TenantScopedModel)
    - BillingMilestoneService with atomic mark_invoiced
  patterns:
    - TenantScopedModel / TenantScopedRepository / TenantScopedService inheritance
    - Atomic UPDATE ... WHERE is_invoiced=FALSE for double-billing prevention
    - model_validator combining multiple validations in one method (Pydantic v2)
key_files:
  created:
    - backend/migrations/versions/0023_per_trade_billing.py
    - backend/app/features/billing_milestones/__init__.py
    - backend/app/features/billing_milestones/models.py
    - backend/app/features/billing_milestones/schemas.py
    - backend/app/features/billing_milestones/repository.py
    - backend/app/features/billing_milestones/service.py
    - backend/app/features/billing_milestones/router.py
  modified:
    - backend/app/features/quotes/models.py
    - backend/app/features/quotes/schemas.py
    - backend/app/features/invoices/models.py
    - backend/app/features/invoices/schemas.py
    - backend/app/main.py
decisions:
  - "Pydantic v2 model_validator: combine job/scope linkage check + discount validation in one @model_validator(mode=after) method — Pydantic only runs the last validator with same name"
  - "mark_invoiced uses raw SQL text() UPDATE ... WHERE is_invoiced=FALSE RETURNING id for atomic double-billing prevention — no ORM layer needed for this operation"
  - "Router enforces scope_id from URL over body trade_scope_id — consistency between URL param and payload"
metrics:
  duration: 306s
  completed: "2026-03-26T04:06:04Z"
  tasks_completed: 2
  files_created: 7
  files_modified: 5
---

# Phase 25 Plan 01: Per-Trade Billing Foundation Summary

Backend foundation for per-trade billing: Alembic migration 0023 creates the billing_milestones table with RLS, extends quotes and invoices with optional trade_scope_id FK and makes job_id nullable, and creates the full BillingMilestone feature module with atomic double-billing prevention via mark_invoiced.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Alembic migration 0023 and model extensions | cdd449e | 0023_per_trade_billing.py, quotes/models.py, quotes/schemas.py, invoices/models.py, invoices/schemas.py |
| 2 | BillingMilestone feature module | cc7f189 | billing_milestones/__init__.py, models.py, schemas.py, repository.py, service.py, router.py, main.py |

## What Was Built

### Migration 0023

- Creates `billing_milestones` table with: id (UUID PK), company_id, trade_scope_id (FK trade_scopes ON DELETE CASCADE), name, percentage (NUMERIC 5,2), description, is_invoiced (BOOLEAN DEFAULT FALSE), sort_order, version, timestamps, deleted_at
- CheckConstraint: `percentage > 0 AND percentage <= 100`
- Row Level Security policy using `app.current_company_id` setting (consistent with other tables)
- GRANT SELECT/INSERT/UPDATE/DELETE to appuser
- `set_updated_at` trigger for updated_at maintenance
- Adds `trade_scope_id` nullable FK (SET NULL) to `quotes` and `invoices`
- Adds `milestone_id` nullable FK (SET NULL) to `invoices`
- Makes `job_id` nullable on both `quotes` and `invoices`
- Indexes on all new FK columns

### Quote and Invoice Model Extensions

- `Quote.trade_scope_id`: nullable FK to trade_scopes with SET NULL on delete
- `Quote.job_id`: changed from NOT NULL to nullable (`Mapped[uuid.UUID | None]`)
- `Quote.trade_scope` relationship with `lazy="raise"`
- `Invoice.trade_scope_id`: nullable FK to trade_scopes
- `Invoice.milestone_id`: nullable FK to billing_milestones
- `Invoice.job_id`: changed to nullable
- `Invoice.trade_scope` and `Invoice.milestone` relationships with `lazy="raise"`

### Schema Updates

- `QuoteCreate`: `job_id` now `uuid.UUID | None = None`; added `trade_scope_id: uuid.UUID | None = None`; single `model_validator` enforces at least one of job_id/trade_scope_id
- `QuoteResponse`: `job_id` changed to `uuid.UUID | None`; added `trade_scope_id: uuid.UUID | None`
- `InvoiceCreate`: same pattern plus `milestone_id: uuid.UUID | None = None`
- `InvoiceResponse`: added `trade_scope_id` and `milestone_id` fields

### BillingMilestone Feature Module

- `BillingMilestone` (TenantScopedModel): full model with CheckConstraint and lazy="raise" relationship
- `BillingMilestoneRepository` (TenantScopedRepository): adds `list_by_scope` filtering by trade_scope_id ordered by sort_order
- `BillingMilestoneService` (TenantScopedService): CRUD + atomic `mark_invoiced` via raw SQL UPDATE ... WHERE is_invoiced=FALSE
- `BillingMilestoneCreate/Update/Response` schemas with `from_model` classmethod
- Router at `/api/v1/trade-scopes/{scope_id}/milestones` with admin-only write endpoints
- Endpoints: GET / (list), POST / (create), PUT /{id} (update), DELETE /{id} (soft delete, 204), POST /{id}/mark-invoiced (atomic, 409 on double-billing)
- Registered in main.py under Phase 25 comment

## Decisions Made

1. **Pydantic model_validator naming**: Pydantic v2 only executes the last `@model_validator(mode="after")` when two have the same name — combined job/scope linkage and discount validation into a single `validate_fields` method.

2. **Atomic mark_invoiced**: Uses `text("UPDATE ... WHERE is_invoiced=FALSE RETURNING id")` — if 0 rows returned, milestone was already invoiced; raises HTTP 409. No ORM layer can achieve this atomically without a separate SELECT.

3. **Router scope_id enforcement**: The URL `scope_id` parameter overrides the body's `trade_scope_id` for milestone creation — prevents clients from creating milestones under different scopes via body injection.

## Deviations from Plan

None — plan executed exactly as written. The only deviation was combining two `model_validator` methods into one (Pydantic v2 constraint, auto-fixed per Rule 1).

## Verification

- `ruff check app/ migrations/versions/0023_per_trade_billing.py` — all checks passed
- All acceptance criteria grep checks pass (8/8 for Task 1, 6/6 for Task 2)
- Module syntax verified with `python -m py_compile` on all new files

## Self-Check: PASSED

- Migration: `/Users/heechung/AndroidStudioProjects/contractormanagement/.claude/worktrees/agent-a3eff2ed/backend/migrations/versions/0023_per_trade_billing.py` — FOUND
- BillingMilestone module: `backend/app/features/billing_milestones/` — FOUND (6 files)
- Commits: cdd449e and cc7f189 — verified via git log
