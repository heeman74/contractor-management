# Phase 8: Business Operations - Context

**Gathered:** 2026-03-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Admins create digital quotes with line items for Quote-stage jobs, send them to clients for approval via the portal, generate invoices from completed jobs, and view a reporting dashboard showing business performance metrics. Actual payment processing is deferred to v2 (PAY-01).

Requirements: BIZ-01, BIZ-02, BIZ-03, BIZ-04

</domain>

<decisions>
## Implementation Decisions

### Quote Structure & Line Items
- Line items have two types: **Labor** and **Material** — each with description, quantity, unit, unit price, and subtotal
- Selectable **unit of measurement** per line item: each, hour, day, sqm, sqft, meter, liter, etc. Displayed as "Qty x Unit @ Price"
- **Tax**: single tax rate (%) applied to subtotal
- **Discount**: optional discount (% or fixed amount) applied before tax
- Quote always **belongs to a job** (at Quote stage) — no standalone quotes
- When job originated from a client request with budget range, show as **reference banner** in quote builder (e.g., "Client budget: $2,000–$3,000") — no auto-population
- **Basic quote templates**: admin can save a quote as a template and load it when creating new quotes (template CRUD)
- **Optional expiry date**: admin can set expiry; after expiry, client can view but can't approve; admin can extend and resend
- **1–100 line items** per quote

### Quote Delivery & Approval
- Clients receive quotes **in-app via portal + push notification** (Phase 7 FCM infrastructure) — no email/PDF delivery in v1
- **Draft state**: quotes start as draft (admin-only visible), admin can save/edit, then explicitly "send" to make visible to client
- **Preview before send**: admin sees quote as client will see it, confirms before sending
- **Full line-item breakdown** visible to client in portal (descriptions, quantities, unit prices, subtotals, discount, tax, total)
- **Read receipts**: admin sees "Viewed by client on [date]" when client opens the quote
- **Decline flow**: client picks a decline reason (too expensive, wrong scope, changed mind, other + text). Admin gets notified, can revise and resend
- **Unlimited revisions**: each revision is versioned (v1, v2, v3...). Client always sees latest version only — no revision history for clients
- **Approval auto-transitions** job from Quote → Scheduled (if contractor and dates assigned)
- **Expired quotes block approval** — show "Expired" badge, client can view but can't approve. Admin can extend expiry. No auto-decline
- Quote events (sent, viewed, approved, declined, revised) logged in **job status_history** JSONB — visible in History tab

### Invoice Generation & Format
- **One-tap generation** from approved quote line items: admin taps "Generate Invoice" on a completed job
- Invoice **auto-populates** from quote (same items, quantities, prices, tax, discount) but is **editable before finalizing** — admin can add/remove/modify items for change orders
- **In-app view + PDF download** for both quotes and invoices — same PDF generation infrastructure serves both
- **Sequential invoice numbers per company** with optional admin-configurable prefix (e.g., INV-0001, ACME-0001)
- **Optional due date** on invoices — displayed on invoice and PDF
- **Manual payment status tracking**: Unpaid, Partially Paid, Paid — no actual payment processing (deferred to v2)
- Invoice generation transitions job to **Invoiced** status

### Reporting Dashboard
- **Four metrics**:
  1. Jobs by status — bar or pie chart showing count per lifecycle stage
  2. Revenue summary — bar chart by month, showing paid vs unpaid stacked
  3. Contractor utilization — horizontal bar chart ranking all contractors by utilization %, booked vs available hours
  4. Quote conversion rate — approved vs declined percentage
- **Date range**: quick presets (This Week, This Month, Last 30 Days, This Quarter, This Year, All Time) + custom date range picker
- **Access**: admin sees full dashboard; contractors see limited view (own utilization and job stats only, no revenue data)
- **Real-time queries** — live data on each load, no pre-computed aggregates
- **No data export** in v1 — deferred to v2 (ADV-03)
- **New bottom nav tab** "Reports" for admin; contractors see simpler version in their nav

### Claude's Discretion
- Quote/invoice data model schemas (tables, columns, types)
- Alembic migration structure
- PDF generation library selection and template design
- Chart library selection for Flutter reporting (fl_chart, syncfusion, etc.)
- Quote template storage design
- Read receipt implementation approach
- Dashboard layout and card arrangement
- Contractor limited dashboard layout
- Drift table design for offline quote/invoice data
- Sync handler registration for new entity types

</decisions>

<specifics>
## Specific Ideas

- The quote builder should feel like a professional estimating tool — not a toy form. Units, line item types, tax/discount give it credibility
- Templates save time for contractors who do similar jobs repeatedly (e.g., "Standard hot water cylinder replacement")
- Read receipts are important for follow-up — admin knows whether to call the client or wait
- One-tap invoice generation from quote data is the key convenience — completing a job and invoicing should take seconds, not minutes
- Draft quotes let admins build quotes over time (check material prices, consult team) before committing
- The dashboard should give admins a "pulse check" on their business at a glance — the most common question is "how are we doing this month?"
- Contractors seeing their own utilization motivates them and reduces "am I busy enough?" conversations with admin

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TenantScopedModel` / `TenantScopedService` / `TenantScopedRepository` — base classes for quote, invoice, line_item models
- `Job` model with `status` (StrEnum) and `status_history` (JSONB) — quote/invoice events append here
- `JobStatus` enum includes `invoiced` — already wired in state machine transitions
- `ClientPortalScreen` (Phase 7) — extend with quote view and invoice view for clients
- `JobProgressStepper` widget — shows lifecycle stages including Invoiced
- `NotificationService` + FCM infrastructure (Phase 7) — reuse for quote/invoice notifications
- `client_job_detail_screen.dart` — add Quote and Invoice tabs
- `job_wizard_screen.dart` — quote builder could be accessed from wizard or job detail
- `KanbanBoard` widget — job pipeline already shows Invoiced column
- `SyncEngine` + `SyncHandler` pattern — register handlers for quotes, invoices

### Established Patterns
- Feature-first Flutter structure: `lib/features/` — add `quotes/`, `invoices/`, `reports/` features
- Drift streams + StreamProvider for reactive UI
- JSONB for flexible data (status_history) — reuse for line items or quote versions
- Backend OOP architecture: inherit from base classes
- UUID client-generated PKs for offline-first sync
- StatefulShellRoute for bottom navigation — add Reports tab

### Integration Points
- Alembic migration — new tables for quotes, quote_line_items, invoices, invoice_line_items, quote_templates
- Job model — add quote_id and invoice_id foreign keys (or one-to-one relationship)
- JobService — add quote approval → Scheduled transition logic
- NotificationService — add quote/invoice notification triggers
- GoRouter — add routes for quote builder, invoice view, reporting dashboard
- AppShell bottom nav — add Reports tab for admin (and limited for contractor)
- Client portal — add quote detail and invoice detail screens
- Sync delta endpoint — include quotes and invoices in sync response
- PDF generation — new backend endpoint for quote/invoice PDF rendering

</code_context>

<deferred>
## Deferred Ideas

- Email delivery of quotes/invoices with PDF attachment — future enhancement
- In-app payment processing via Stripe/Square — v2 (PAY-01)
- Automated payment reminders — v2 (PAY-03)
- Data export to CSV/Excel from dashboard — v2 (ADV-03)
- QuickBooks/Xero accounting integration — v2 (ADV-05)
- Quote/invoice email notifications (beyond push) — future enhancement
- Advanced reporting and analytics — v2 (ADV-03)
- Recurring invoice automation — v2 (ADV-04)

</deferred>

---

*Phase: 08-business-operations*
*Context gathered: 2026-03-13*
