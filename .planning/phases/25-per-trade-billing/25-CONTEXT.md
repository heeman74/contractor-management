# Phase 25: Per-Trade Billing - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

GCs can create quotes and invoices scoped to each trade scope (not just per-job), aggregate them to a project-level view for client approval, and create progress invoices at milestones within a trade scope.

</domain>

<decisions>
## Implementation Decisions

### Quote Scope Transition
- **D-01:** Add optional `trade_scope_id` FK to existing `quotes` table — quotes can be either job-scoped (legacy) or trade-scope-scoped. New quotes default to trade-scope-scoped. Existing job-scoped quotes continue to work unchanged.
- **D-02:** Quote creation flow on mobile: GC navigates to a trade scope detail screen → taps "Create Quote" → line item editor pre-populated with the trade scope name. Same existing line item editor UI, just scoped to the trade.
- **D-03:** Trade-scoped quotes are independent — creating/editing one does not affect quotes for other trade scopes on the same project.

### Invoice Generation from Completed Work
- **D-04:** Add optional `trade_scope_id` FK to existing `invoices` table — same dual-scope pattern as quotes.
- **D-05:** "Generate Invoice" button on trade scope detail screen when scope has completed tasks. Auto-populates line items from completed work items (task titles + hours logged as labor line items). GC can edit/add/remove line items before sending.
- **D-06:** Invoice inherits tax rate and discount settings from the quote if one exists for that trade scope, otherwise uses company defaults.

### Project-Level Aggregation
- **D-07:** Project-level quote summary is a read-only aggregation view — not a separate entity. Sums all trade-scope quotes into a single total with per-trade breakdown table. No editing at project level.
- **D-08:** Project-level invoice summary shows total billed, total paid, total outstanding across all trades. Same read-only aggregation pattern — a summary screen, not a new entity.
- **D-09:** Both aggregation views accessible from the project detail screen as new sections/tabs below existing content.

### Progress Billing / Milestones
- **D-10:** New `billing_milestones` table — GC defines milestones per trade scope (e.g., "Rough-in complete: 40%", "Final trim: 60%"). Each milestone has a name, percentage, and optional description.
- **D-11:** Progress invoice is a regular invoice with a `milestone_id` FK linking it to the billing milestone. The invoice amount is calculated as milestone percentage × trade scope quote total.
- **D-12:** GC can create a progress invoice by selecting a milestone from the trade scope's milestone list. The milestone is marked as "invoiced" to prevent double-billing.

### Claude's Discretion
- Migration strategy for adding trade_scope_id to existing quotes/invoices tables (nullable FK, backfill approach)
- Project-level summary screen layout (single scrollable page vs tabs)
- Billing milestone CRUD UI pattern (inline editing vs modal form)
- Invoice number sequence handling for trade-scoped vs job-scoped invoices
- How completed work items map to invoice line items (grouping, description format)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Invoice/Quote Infrastructure
- `backend/app/features/invoices/models.py` — Current Invoice + InvoiceLineItem models (job_id FK, status machine)
- `backend/app/features/invoices/service.py` — InvoiceService with invoice_number generation from company sequence
- `backend/app/features/invoices/router.py` — Existing invoice endpoints
- `backend/app/features/quotes/models.py` — Current Quote + QuoteLineItem models (job_id FK)
- `backend/app/features/quotes/service.py` — QuoteService
- `backend/app/features/quotes/router.py` — Existing quote endpoints

### Mobile Data Layer
- `mobile/lib/features/invoices/data/invoice_dao.dart` — Drift DAO for invoices
- `mobile/lib/features/invoices/domain/invoice_entity.dart` — Invoice entity with computed totals
- `mobile/lib/features/invoices/presentation/screens/invoice_detail_screen.dart` — Existing invoice detail UI
- `mobile/lib/features/quotes/domain/line_item_entity.dart` — Shared line item entity

### Trade Scope Infrastructure (Phase 19)
- `backend/app/features/projects/models.py` — TradeScope model (project_id, contractor_id, status)
- `mobile/lib/features/projects/presentation/screens/trade_scope_detail_screen.dart` — Trade scope detail screen to extend

### Requirements
- `.planning/REQUIREMENTS.md` §BILL-01 through BILL-05 — Per-trade billing requirements

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **InvoiceService**: Full CRUD with invoice_number generation from `companies.invoice_sequence`. Extend for trade_scope_id support.
- **QuoteService**: Full CRUD with line item management. Extend for trade_scope_id support.
- **InvoiceDao / InvoiceEntity**: Drift DAO with computed totals (subtotal, discount, tax, total). Reuse for trade-scoped queries.
- **LineItemEntity**: Shared between quotes and invoices. No changes needed.
- **PDF generation**: `backend/app/features/pdf/service.py` — existing quote/invoice PDF. Extend for trade-scope context.
- **TradeScopeDetailScreen**: Already shows tasks, punch items. Add quote/invoice/milestone sections.

### Established Patterns
- **Job-scoped billing**: Invoices and quotes currently FK to `jobs.id`. Adding `trade_scope_id` as nullable FK preserves backwards compatibility.
- **Offline-first dual-write**: All Drift DAOs use entity table + sync_queue atomic transactions.
- **Invoice number sequence**: `companies.invoice_sequence` column, incremented atomically in service layer.

### Integration Points
- **TradeScopeDetailScreen**: Add "Create Quote", "Generate Invoice", "Milestones" sections
- **ProjectDetailScreen**: Add project-level quote/invoice summary sections
- **Alembic migration**: Add `trade_scope_id` nullable FK to `quotes` and `invoices`, create `billing_milestones` table
- **Drift schema**: Bump to v13, add `tradeScopeId` column to existing tables, add `BillingMilestones` table

</code_context>

<specifics>
## Specific Ideas

- Trade-scope quotes and invoices are the primary flow going forward — job-scoped is legacy
- Project-level views are read-only aggregations, not editable entities
- Progress billing via milestones prevents double-billing with the "invoiced" flag
- Auto-population of invoice line items from completed work saves GC time

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 25-per-trade-billing*
*Context gathered: 2026-03-25 via --auto mode*
