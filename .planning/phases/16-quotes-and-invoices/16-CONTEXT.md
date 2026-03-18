# Phase 16: Quotes and Invoices - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Admins can create, edit, and send quotes from the web dashboard with line items, view and manage invoices with payment recording, and download PDFs for both. Web frontend only — the full backend API (quotes CRUD, lifecycle, invoices, PDF generation) was built in Phase 8 (v1.0). One backend addition: `amount_paid` field on invoices for payment amount tracking.

Requirements: QUOTE-01, QUOTE-02, QUOTE-03, QUOTE-04, INV-01, INV-02, INV-03

</domain>

<decisions>
## Implementation Decisions

### Quote builder UX
- Inline table rows (spreadsheet-style): each row directly editable in-place with Type, Description, Qty, Unit, Price, Total columns
- Add Row button at bottom, delete (×) button per row, tab between cells
- Drag handle per row for reordering (grip icon on left side, sort_order saved to backend)
- "Load from template" dropdown at top of builder — selecting a template populates line items + tax rate, admin modifies before saving
- Preview tab/toggle: switch between Edit and Preview modes. Preview shows styled read-only view matching PDF layout
- Financial summary (subtotal, discount, tax, total) as sticky footer — always visible, updates live as values change
- Quote always created from job detail page ("Create Quote" button on jobs in Quote status) — job pre-selected and locked, no standalone quote creation or job picker
- "Send to Client" action shows confirmation dialog: "Send quote to [Client Name]? They will be notified and can approve or decline."

### Quote detail & lifecycle display
- Two-column layout (mirrors Phase 14 job detail): main content (~65%) + right sidebar (~35%)
- Main content: line items table (read-only) + admin notes + revision history
- Right sidebar: status badge, client info, job link, financial summary (subtotal/discount/tax/total), expiry date, read receipt ("Viewed by client"), action buttons
- Context-sensitive action buttons — show only valid actions for current status:
  - Draft: [Edit] [Send] [Download PDF]
  - Sent/Viewed: [Revise] [Extend Expiry] [Download PDF]
  - Approved: [Download PDF] [Generate Invoice] (when job is complete)
  - Declined: [Revise] [Download PDF]
  - Expired: [Extend Expiry] [Revise] [Download PDF]
- Both compact status stepper in sidebar AND detailed activity log in main content for timeline/read receipts
- Declined quotes: red/orange inline alert banner at top: "Declined by client: [reason]" with prominent [Revise & Resend] button
- Expired quotes: amber warning banner at top: "This quote expired on [date]. Client cannot approve." with [Extend Expiry] and [Revise] buttons. StatusBadge shows "Expired" in amber/orange
- Revise action: opens quote builder pre-filled with current line items/tax/discount. Save creates new revision (v2, v3...) via POST /{id}/revise
- Generate Invoice button available on quote detail when quote is approved and job is complete
- Sidebar shows linked invoice card if one exists: "Invoice #INV-0042 — $4,500 — Paid" with link to invoice detail

### Invoice payment recording
- Extend backend: add `amount_paid` Decimal field to invoice model (additive migration, no existing field changes)
- Running total approach: single `amount_paid` field on invoice, not a payment ledger table
- UI shows: Total $X | Paid $Y | Balance $Z
- Status buttons: "Record Payment" (opens inline form for amount) and "Mark Fully Paid"
- MarkPaidRequest schema extended to include optional `amount_paid` field
- Overdue invoices (past due_date, not fully paid): red "Overdue" StatusBadge + subtle red left border on list rows + red alert banner on detail page
- Invoice editable until finalized (draft state after generation). Admin can edit line items for change orders before clicking "Finalize". After finalization, invoice is locked.
- Two-column detail layout mirrors quote detail: main content (line items read-only + payment section) + sidebar (status, payment summary, client/job links, actions)

### List page presentation
- Quotes list: Phase 14 DataTable + horizontal status tabs pattern
  - Tabs: All | Draft | Sent | Viewed | Approved | Declined | Expired (with count badges)
  - Columns: Quote #, Job, Client, Total, Status, Date
  - Click row → detail page. Sortable, searchable, server-side paginated
  - No "New Quote" button — creation only from job detail page
- Invoices list: payment-focused tabs
  - Tabs: All | Unpaid | Partially Paid | Paid | Overdue | Draft (with count badges)
  - Overdue is computed (unpaid/partial + past due_date)
  - Columns: Invoice #, Job, Client, Total, Paid, Balance, Status, Due Date
  - Overdue rows get subtle red left border highlight
- Quotes and Invoices as separate sidebar nav items (matching Phase 13 module order: Dashboard > Jobs > Schedule > Quotes > Invoices > Clients > Contractors > Reports)

### Claude's Discretion
- Drag-and-drop library for line item reordering (dnd-kit, @hello-pangea/dnd, or react-beautiful-dnd)
- react-hook-form + useFieldArray configuration details
- Exact skeleton loading shapes for list and detail pages
- Template management CRUD UI (inline in builder or separate settings page)
- Exact spacing, typography, and component sizing
- Preview tab styling to match PDF layout
- Search debounce timing
- Empty state messages for zero quotes/invoices
- Pagination controls styling
- Exact status stepper component design

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Backend API — Quotes
- `backend/app/features/quotes/router.py` — All quote endpoints: CRUD, templates, send, approve, decline, revise, extend expiry, PDF download
- `backend/app/features/quotes/schemas.py` — QuoteCreate, QuoteUpdate, QuoteResponse (with computed totals), QuoteLineItemCreate, QuoteTemplateCreate/Response, DeclineQuoteRequest
- `backend/app/features/quotes/service.py` — QuoteService: create, update, send, approve, decline, revise, extend_expiry, record_view, template CRUD
- `backend/app/features/quotes/models.py` — Quote model, QuoteLineItem model, QuoteTemplate model

### Backend API — Invoices
- `backend/app/features/invoices/router.py` — All invoice endpoints: generate from quote, manual create, update, finalize, payment status, PDF download
- `backend/app/features/invoices/schemas.py` — InvoiceCreate, InvoiceUpdate, InvoiceResponse (with computed totals), InvoiceLineItemCreate, MarkPaidRequest
- `backend/app/features/invoices/service.py` — InvoiceService: generate_from_quote, generate_manual, update, finalize, update_payment_status
- `backend/app/features/invoices/models.py` — Invoice model, InvoiceLineItem model

### Backend API — PDF Generation
- `backend/app/features/pdf/service.py` — PdfService: generate_quote_pdf, generate_invoice_pdf (WeasyPrint + Jinja2)
- `backend/app/features/pdf/templates/quote.html` — Quote PDF Jinja2 template
- `backend/app/features/pdf/templates/invoice.html` — Invoice PDF Jinja2 template

### Web Foundation (Phase 13)
- `web/src/lib/api-client.ts` — apiClient with 401 auto-refresh proxy pattern
- `web/src/components/shared/status-badge.tsx` — StatusBadge with semantic color map (reuse for quote/invoice statuses)
- `web/src/components/shared/kpi-card.tsx` — KPI card component (dashboard uses Pending Quotes and Overdue Invoices cards)
- `web/src/components/layout/sidebar.tsx` — Sidebar navigation (add Quotes and Invoices routes)
- `web/src/components/layout/topbar.tsx` — Topbar with breadcrumbs
- `web/src/store/slices/` — Redux slices for UI state

### Web UI Components
- `web/src/components/ui/` — shadcn/ui: Card, Badge, Button, Input, Table, Tabs, Dialog, Sheet, Skeleton, Sonner (toast), DropdownMenu, Textarea, Label, Separator

### Phase 14 Patterns (reuse)
- `web/src/app/(dashboard)/jobs/` — DataTable + status tabs + count badges + sortable columns pattern to replicate
- Job detail two-column layout pattern to replicate for quote/invoice detail pages

### Requirements
- `.planning/REQUIREMENTS.md` — QUOTE-01 through QUOTE-04, INV-01 through INV-03

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **StatusBadge** (`web/src/components/shared/status-badge.tsx`): Needs new status mappings for quote statuses (draft, sent, viewed, approved, declined, expired) and invoice statuses (unpaid, partially_paid, paid, overdue, draft, finalized)
- **apiClient** (`web/src/lib/api-client.ts`): GET/POST/PATCH/DELETE with proxy and 401 refresh — use for all quote/invoice API calls
- **Table, Tabs, Card, Dialog** (`web/src/components/ui/`): shadcn/ui primitives for DataTable, status tabs, detail cards, confirmation dialogs
- **Sonner toast**: Success/error toasts (error persists with `duration: Infinity`)
- **Phase 14 DataTable pattern**: Jobs list implementation provides the exact DataTable + tabs + pagination + sorting template to replicate

### Established Patterns
- **TanStack Query for server state**: All API data fetched/cached via TanStack Query (useQuery, useMutation with optimistic updates)
- **Redux for UI state only**: Tab state, filter state, sidebar collapse
- **httpOnly cookie auth**: All API calls through /api/proxy route handler
- **URL-driven state**: searchParams for bookmarkable list views (tabs, page, sort)
- **Two-column detail layout**: Established in Phase 14 jobs — replicate for quotes and invoices

### Integration Points
- **Sidebar nav**: Add "Quotes" and "Invoices" routes to sidebar items array
- **Dashboard route group**: New pages at `web/src/app/(dashboard)/quotes/` and `web/src/app/(dashboard)/invoices/`
- **Job detail page**: Add "Create Quote" button for jobs in Quote status, "Generate Invoice" button for completed jobs with approved quotes
- **Backend migration**: Add `amount_paid` Decimal field to invoices table (additive-only, nullable, default 0)
- **MarkPaidRequest schema**: Extend to accept optional `amount_paid` field alongside status
- **Dashboard KPI cards**: "Pending Quotes" and "Overdue Invoices" cards already exist on dashboard home — they'll link to the new list pages

</code_context>

<specifics>
## Specific Ideas

- Quote builder should feel like a professional estimating tool — spreadsheet-style inline editing, not a toy form (from Phase 8 context)
- Financial summary always visible (sticky footer) so admin never loses sight of the total while editing line items
- Revise flow is key for declined quotes — pre-fill builder with existing data so admin only changes what's needed
- One-click invoice generation from approved quote is the main convenience win — completing a job and invoicing should take seconds
- Overdue invoices need to be impossible to miss — red badge, row highlight, and detail banner together

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 16-quotes-and-invoices*
*Context gathered: 2026-03-17*
