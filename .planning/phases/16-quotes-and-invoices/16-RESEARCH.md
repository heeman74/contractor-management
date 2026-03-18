# Phase 16: Quotes and Invoices - Research

**Researched:** 2026-03-17
**Domain:** Next.js 16 App Router / React 19 / TanStack Query — quotes and invoices frontend, plus additive backend migration
**Confidence:** HIGH

## Summary

Phase 16 is primarily a web frontend build. The backend API (quotes CRUD, lifecycle, invoice generation, PDF download) was fully implemented in Phase 8. The only backend work is an additive migration adding `amount_paid` to the invoices table and extending the `MarkPaidRequest` schema to accept it.

The frontend has five main surfaces: a quotes list page, a quote detail/builder page, an invoices list page, an invoice detail page, and a job detail integration (Create Quote button, Generate Invoice button). All five follow patterns already established in Phase 14 (jobs): DataTable + status tabs, two-column detail layout, TanStack Query for server state, URL-driven search params, `Suspense` wrapping `useSearchParams`, shadcn/ui primitives.

One critical gap discovered: the backend routers expose no `GET /quotes/` or `GET /invoices/` list endpoint. The repository has `get_active_quotes()` and `list_all()` via base, but no router exposes them. These endpoints must be added as part of this phase before the list pages can function.

**Primary recommendation:** Build list endpoints first (Wave 0), then list pages, then detail pages, then builder, then PDF download.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Quote builder UX**
- Inline table rows (spreadsheet-style): each row directly editable in-place with Type, Description, Qty, Unit, Price, Total columns
- Add Row button at bottom, delete (x) button per row, tab between cells
- Drag handle per row for reordering (grip icon on left side, sort_order saved to backend)
- "Load from template" dropdown at top of builder — selecting a template populates line items + tax rate, admin modifies before saving
- Preview tab/toggle: switch between Edit and Preview modes. Preview shows styled read-only view matching PDF layout
- Financial summary (subtotal, discount, tax, total) as sticky footer — always visible, updates live as values change
- Quote always created from job detail page ("Create Quote" button on jobs in Quote status) — job pre-selected and locked, no standalone quote creation or job picker
- "Send to Client" action shows confirmation dialog: "Send quote to [Client Name]? They will be notified and can approve or decline."

**Quote detail & lifecycle display**
- Two-column layout (mirrors Phase 14 job detail): main content (~65%) + right sidebar (~35%)
- Main content: line items table (read-only) + admin notes + revision history
- Right sidebar: status badge, client info, job link, financial summary (subtotal/discount/tax/total), expiry date, read receipt ("Viewed by client"), action buttons
- Context-sensitive action buttons by status:
  - Draft: [Edit] [Send] [Download PDF]
  - Sent/Viewed: [Revise] [Extend Expiry] [Download PDF]
  - Approved: [Download PDF] [Generate Invoice] (when job is complete)
  - Declined: [Revise] [Download PDF]
  - Expired: [Extend Expiry] [Revise] [Download PDF]
- Both compact status stepper in sidebar AND detailed activity log in main content
- Declined: red/orange inline alert banner "Declined by client: [reason]" with [Revise & Resend] button
- Expired: amber warning banner "This quote expired on [date]." with [Extend Expiry] and [Revise] buttons
- Revise action: opens quote builder pre-filled. Save creates new revision via POST /{id}/revise
- Generate Invoice button on quote detail when quote is approved and job is complete
- Sidebar shows linked invoice card if one exists

**Invoice payment recording**
- Extend backend: add `amount_paid` Decimal field to invoice model (additive migration)
- Running total approach: single `amount_paid` field, not a ledger table
- UI: Total $X | Paid $Y | Balance $Z
- Status buttons: "Record Payment" (opens inline form for amount) and "Mark Fully Paid"
- MarkPaidRequest schema extended to include optional `amount_paid` field
- Overdue invoices: red "Overdue" StatusBadge + subtle red left border on list rows + red alert banner on detail
- Invoice editable until finalized. Admin can edit line items before clicking "Finalize". After finalization, locked.
- Two-column detail layout mirrors quote detail

**List page presentation**
- Quotes list: Phase 14 DataTable + horizontal status tabs pattern
  - Tabs: All | Draft | Sent | Viewed | Approved | Declined | Expired (with count badges)
  - Columns: Quote #, Job, Client, Total, Status, Date
  - Click row -> detail page. Sortable, searchable, server-side paginated
  - No "New Quote" button
- Invoices list: payment-focused tabs
  - Tabs: All | Unpaid | Partially Paid | Paid | Overdue | Draft (with count badges)
  - Overdue is computed (unpaid/partial + past due_date)
  - Columns: Invoice #, Job, Client, Total, Paid, Balance, Status, Due Date
  - Overdue rows: subtle red left border highlight
- Quotes and Invoices as separate sidebar nav items (already wired in sidebar.tsx)

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

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| QUOTE-01 | Admin can view all quotes in a list with status indicators (draft, sent, approved, declined) | Requires new GET /quotes/ backend endpoint; frontend uses Phase 14 DataTable pattern with status tabs |
| QUOTE-02 | Admin can create and edit quotes with line items, taxes, and descriptions | POST /quotes/ and PATCH /quotes/{id} exist; react-hook-form + useFieldArray + inline table editing |
| QUOTE-03 | Admin can send a quote to the client and track approval status | POST /quotes/{id}/send exists; confirmation dialog; status stepper in sidebar |
| QUOTE-04 | Admin can download a quote as PDF | GET /quotes/{id}/pdf exists; fetch as blob, browser download trigger |
| INV-01 | Admin can view all invoices in a list with payment status indicators | Requires new GET /invoices/ backend endpoint; Overdue computed client-side |
| INV-02 | Admin can record full or partial payments on an invoice | PATCH /invoices/{id}/payment exists; requires amount_paid migration + schema extension |
| INV-03 | Admin can download an invoice as PDF | GET /invoices/{id}/pdf exists; same blob download pattern as quotes |
</phase_requirements>

---

## Standard Stack

### Core (already installed — no new installs)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| react-hook-form | ^7.71.2 | Form state, validation, `useFieldArray` for line items | Already in package.json; useFieldArray is the canonical pattern for dynamic field arrays |
| @hookform/resolvers | ^5.2.2 | Zod schema integration with react-hook-form | Already in package.json |
| zod | ^4.3.6 | Runtime validation schemas | Already in package.json |
| @tanstack/react-query | ^5.90.21 | Server state, caching, mutations | Established pattern in phases 14-15 |
| shadcn/ui | via @base-ui/react | Card, Table, Tabs, Dialog, Input, Button, Skeleton, Badge | Established pattern |
| lucide-react | ^0.577.0 | Icons (GripVertical for drag handle, X for delete row, etc.) | Established pattern |

### New — Drag-and-Drop (Claude's Discretion)
| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| @dnd-kit/core + @dnd-kit/sortable | ^6.x | Line item reordering | Most actively maintained (2024-2025), tree-shakeable, React 18/19 compatible, no deprecated dependencies. dnd-kit is the current ecosystem standard. react-beautiful-dnd is archived/unmaintained. @hello-pangea/dnd is a rbd fork but dnd-kit is more idiomatic for new code. |

**Recommendation:** Use dnd-kit. `@dnd-kit/sortable` provides `SortableContext`, `useSortable`, `arrayMove` — exactly what's needed for inline row reordering.

**Installation:**
```bash
cd web && npm install @dnd-kit/core @dnd-kit/sortable @dnd-kit/utilities
```

### Backend (additive only)
| What | Details |
|------|---------|
| Alembic migration | Add `amount_paid NUMERIC(10,2) DEFAULT 0 NOT NULL` to `invoices` table |
| Invoice model | Add `amount_paid: Mapped[Decimal]` field |
| InvoiceResponse schema | Add `amount_paid: Decimal` field |
| MarkPaidRequest schema | Add `amount_paid: Decimal | None = None` optional field |
| InvoiceService.update_payment_status | Accept and persist `amount_paid` |
| GET /quotes/ list endpoint | New route returning `list[QuoteResponse]` with optional `status` filter |
| GET /invoices/ list endpoint | New route returning `list[InvoiceResponse]` with optional `status` filter |

---

## Architecture Patterns

### Recommended File Structure
```
web/src/app/(dashboard)/
├── quotes/
│   ├── page.tsx                  # Quotes list (DataTable + status tabs)
│   └── [id]/
│       ├── page.tsx              # Quote detail (two-column layout)
│       └── edit/
│           └── page.tsx          # Quote builder (react-hook-form + useFieldArray)
├── invoices/
│   ├── page.tsx                  # Invoices list
│   └── [id]/
│       └── page.tsx              # Invoice detail + payment recording

web/src/types/api.ts               # Add QuoteLineItem, Quote, QuoteTemplate, Invoice types

backend/app/features/invoices/
├── models.py                      # Add amount_paid field
├── schemas.py                     # Extend InvoiceResponse + MarkPaidRequest
├── service.py                     # Handle amount_paid in update_payment_status
└── router.py                      # Add GET / list endpoint

backend/app/features/quotes/
└── router.py                      # Add GET / list endpoint

backend/alembic/versions/
└── xxxx_add_amount_paid_to_invoices.py
```

### Pattern 1: List Page (replicate from Phase 14)
**What:** DataTable with URL-driven tab/page/sort/search state, `useQueries` for per-status counts, `Suspense` boundary around `useSearchParams`.
**When to use:** Quotes list, Invoices list.

```typescript
// Source: web/src/app/(dashboard)/jobs/page.tsx (established pattern)
export default function QuotesPage() {
  return (
    <Suspense>
      <QuotesPageContent />
    </Suspense>
  );
}

function QuotesPageContent() {
  const searchParams = useSearchParams();
  const activeTab = searchParams.get("tab") ?? "all";
  // ...useQuery with queryKey including tab/page/search/sort
}
```

**Key detail for Overdue tab (invoices):** Overdue is computed client-side from the returned list — filter where `status in ('unpaid','partially_paid') && due_date < today`. No separate backend filter needed (the backend does not have an "overdue" status).

### Pattern 2: Two-Column Detail Layout (replicate from Phase 14)
**What:** `grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8` with Card components.
**When to use:** Quote detail, Invoice detail.

```typescript
// Source: web/src/app/(dashboard)/jobs/[id]/page.tsx (established pattern)
<div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
  <div className="space-y-6">  {/* main column */}
    {/* line items table, notes, activity log */}
  </div>
  <div className="space-y-4">  {/* sidebar */}
    {/* status badge, financial summary, actions */}
  </div>
</div>
```

### Pattern 3: react-hook-form useFieldArray for Line Items
**What:** Dynamic field array where each row is directly editable.
**When to use:** Quote builder, Invoice edit (pre-finalize).

```typescript
// react-hook-form useFieldArray pattern
const { control, register, watch } = useForm<QuoteFormValues>({
  defaultValues: { line_items: [] }
});
const { fields, append, remove, move } = useFieldArray({
  control,
  name: "line_items",
});

// Live total calculation — watch the field array
const lineItems = watch("line_items");
const subtotal = lineItems.reduce(
  (sum, item) => sum + (parseFloat(item.quantity) || 0) * (parseFloat(item.unit_price) || 0),
  0
);
```

**Critical:** `useFieldArray` requires each field to have a stable `id` (RHF generates one automatically). When pre-filling from API data (revise, edit), pass line items as `defaultValues` — do not use `setValue` after mount for the full array.

### Pattern 4: dnd-kit Sortable for Row Reordering
**What:** Wrap the field array table in `DndContext + SortableContext`. Each row uses `useSortable`.
**When to use:** Quote builder line item drag-reorder.

```typescript
// dnd-kit sortable row
import { DndContext, closestCenter } from "@dnd-kit/core";
import { SortableContext, verticalListSortingStrategy, useSortable, arrayMove } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";

function SortableRow({ id, ...rowProps }) {
  const { attributes, listeners, setNodeRef, transform, transition } = useSortable({ id });
  const style = { transform: CSS.Transform.toString(transform), transition };
  return (
    <tr ref={setNodeRef} style={style}>
      <td>
        <button {...attributes} {...listeners}>
          <GripVertical className="h-4 w-4 text-gray-400" />
        </button>
      </td>
      {/* ... other cells */}
    </tr>
  );
}

// In parent: onDragEnd updates field array order
function handleDragEnd(event) {
  const { active, over } = event;
  if (active.id !== over?.id) {
    const oldIndex = fields.findIndex(f => f.id === active.id);
    const newIndex = fields.findIndex(f => f.id === over.id);
    move(oldIndex, newIndex); // react-hook-form move()
  }
}
```

### Pattern 5: PDF Blob Download
**What:** Fetch PDF endpoint via `apiClient` with `responseType: blob` equivalent, create object URL, trigger download.
**When to use:** Quote PDF, Invoice PDF.

```typescript
// PDF download pattern — use raw fetch (not apiClient) to get blob
async function downloadPdf(quoteId: string) {
  const resp = await fetch(`/api/proxy?path=${encodeURIComponent(`/api/v1/quotes/${quoteId}/pdf`)}`, {
    method: "GET",
  });
  if (!resp.ok) throw new Error("PDF download failed");
  const blob = await resp.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `quote-${quoteId}.pdf`;
  a.click();
  URL.revokeObjectURL(url);
}
```

**Critical:** The existing `apiClient` wrapper calls `resp.json()` at the end — it cannot be used directly for binary responses. Use raw `fetch` with the same proxy URL pattern, or add an `apiFetchRaw` helper.

### Pattern 6: Backend List Endpoints (new, minimal)
**What:** Simple `GET /` with optional `status` query param, delegates to repository.
**When to use:** Quote list, Invoice list.

```python
@router.get("/", response_model=list[QuoteResponse])
async def list_quotes(
    status: str | None = None,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[QuoteResponse]:
    """List all quotes for the current tenant (admin only).
    Optional ?status= filter.
    """
    _require_admin(current_user)
    svc = QuoteService(db)
    quotes = await svc.repository.get_active_quotes()
    if status:
        quotes = [q for q in quotes if q.status == status]
    return [QuoteResponse.from_orm_with_totals(q) for q in quotes]
```

**Important:** This route MUST be declared BEFORE `/{quote_id}` in the router file (same pattern as templates). Currently `router.py` already has a note about this — a new `GET /` at the top of the core routes section is safe.

### Anti-Patterns to Avoid
- **Using `apiClient` for PDF download:** It calls `.json()` on the response and will fail for binary content. Use raw `fetch` through the same proxy.
- **Calling `setValue` for the full line_items array after mount:** Use `defaultValues` to pre-fill; avoid resetting large arrays after render as it causes flicker and loss of focus.
- **Hooks in a loop for per-status counts:** Use `useQueries` (established in Phase 14) — never `useQuery` inside `.map()`.
- **`pumpAndSettle` in Drift stream tests:** Phase memory pattern — use `pump()` instead. Not directly applicable here (Playwright, not Flutter) but noted.
- **Forgetting `Suspense` boundary around `useSearchParams`:** Next.js App Router requires it for static generation. Established in Phase 14.
- **react-beautiful-dnd:** Archived, unmaintained. Do not use.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Line item drag-reorder | Custom HTML5 drag events | dnd-kit/sortable | Handles touch, keyboard, accessibility, scroll containers, collision detection |
| Form array management | useState + manual splice | react-hook-form useFieldArray | Handles field IDs, dirty state, validation, performance |
| Zod validation in forms | Manual field validation | @hookform/resolvers/zod | One-liner schema binding, proper error message mapping |
| Sequential invoice numbers | Frontend number generation | Backend SELECT FOR UPDATE pattern | Already implemented — call POST /invoices/generate/{job_id} |
| PDF generation | Frontend PDF rendering | Backend WeasyPrint endpoint | Already implemented — GET /{id}/pdf |
| Amount tracking | Custom payment ledger table | amount_paid field on invoice | Simpler, per CONTEXT.md decision |

**Key insight:** The backend already handles the hard parts — PDF generation, sequential invoice numbering, quote lifecycle state machine, RLS tenant isolation. The frontend just calls the API.

---

## Common Pitfalls

### Pitfall 1: Missing List Endpoints
**What goes wrong:** Frontend calls `GET /api/v1/quotes/` or `GET /api/v1/invoices/` — both return 404 or 405, breaking the list pages entirely.
**Why it happens:** The Phase 8 backend built individual CRUD and lifecycle endpoints but never added list-all endpoints.
**How to avoid:** Add `GET /quotes/` and `GET /invoices/` routes in Wave 0 (before any frontend work). The repository already has `get_active_quotes()` and `list_all()` — just expose them.
**Warning signs:** 404s in browser network tab when loading list pages.

### Pitfall 2: apiClient Fails for PDF Blob
**What goes wrong:** Using `apiGet()` for PDF download — it calls `resp.json()` which throws `SyntaxError: JSON.parse` on binary content.
**Why it happens:** `api-client.ts` always calls `resp.json() as Promise<T>`. Binary blobs are not JSON.
**How to avoid:** Use raw `fetch(proxyUrl)` directly, then call `resp.blob()`. Alternatively add an `apiFetchRaw` helper to `api-client.ts`.
**Warning signs:** "SyntaxError: JSON.parse" or "Unexpected token" in console on PDF download.

### Pitfall 3: Quote Builder defaultValues vs setValue
**What goes wrong:** Loading an existing quote for edit/revise, then using `setValue("line_items", apiData.line_items)` — RHF loses track of field IDs, causing key collisions and incorrect sort_order on submit.
**Why it happens:** `useFieldArray` tracks fields by internal RHF ID, not sort_order. `setValue` on the whole array bypasses ID management.
**How to avoid:** Pass `defaultValues: { line_items: quote.line_items }` directly to `useForm`. For the revise flow (new component mount), this is natural since the page re-mounts with route navigation.
**Warning signs:** Line items appear in wrong order after drag-reorder, or duplicate rows appear after form reset.

### Pitfall 4: Overdue Computed Status Missing from StatusBadge
**What goes wrong:** `StatusBadge` receives `"overdue"` but the color map doesn't have it — falls back to gray instead of red.
**Why it happens:** "overdue" is a computed frontend concept, not a backend status. StatusBadge already has `overdue: "bg-red-100 text-red-800"` in its colorMap (confirmed in code), but `"partially_paid"`, `"finalized"`, `"viewed"`, `"expired"` are missing.
**How to avoid:** Extend the `colorMap` in `status-badge.tsx` with all new statuses before implementing list pages.
**Warning signs:** All new status badges showing gray in the list.

### Pitfall 5: Backend amount_paid Field Not in InvoiceResponse
**What goes wrong:** Migration adds `amount_paid` to DB, but `InvoiceResponse` schema doesn't include it — the field silently disappears from API responses. Frontend cannot show Paid $Y / Balance $Z.
**Why it happens:** Pydantic schemas must be updated alongside model changes.
**How to avoid:** Update model, schema, and service in the same plan/commit. Add `amount_paid` to `InvoiceResponse` and verify `MarkPaidRequest` accepts it.

### Pitfall 6: Status History on Quote vs Job
**What goes wrong:** Trying to render `quote.status_history` on the quote detail activity log — but the Quote model has no `status_history` field. Status events are appended to `job.status_history`, not the quote.
**Why it happens:** The quote service calls `_append_status_history_event` which writes to `job.status_history` JSONB. The `QuoteResponse` schema has no `status_history` field.
**How to avoid:** The activity log on quote detail must either: (a) fetch the job's status_history and filter for quote-related events (type: quote_created, quote_sent, quote_viewed, etc.), or (b) use the audit timestamps on QuoteResponse directly (sent_at, viewed_at, approved_at, declined_at) to reconstruct a timeline. Option (b) is simpler and doesn't require an extra API call.
**Warning signs:** `quote.status_history is undefined` runtime error in the activity log.

### Pitfall 7: Generate Invoice Preconditions
**What goes wrong:** The "Generate Invoice" button is shown on quote detail, admin clicks it, gets a 409 from `POST /invoices/generate/{job_id}` — "Job must be in 'complete' status to generate an invoice".
**Why it happens:** Generate Invoice requires job.status === 'complete'. Quote detail page may not have the job status.
**How to avoid:** Fetch the job (or include job.status in QuoteResponse) before showing the Generate Invoice button. Only show it when quote.status === 'approved' AND job.status === 'complete'. The quote detail page should query the job via `GET /api/v1/jobs/{quote.job_id}`.

---

## Code Examples

### TypeScript Types to Add (web/src/types/api.ts)
```typescript
// Source: backend/app/features/quotes/schemas.py + models.py

export type QuoteStatus = "draft" | "sent" | "viewed" | "approved" | "declined" | "expired" | "revised";
export type InvoiceStatus = "unpaid" | "partially_paid" | "paid";
export type ItemType = "labor" | "material";
export type DiscountType = "percent" | "fixed";

export interface QuoteLineItem {
  id: string;
  quote_id: string;
  item_type: ItemType;
  description: string;
  quantity: string;  // Decimal serialized as string from FastAPI
  unit: string;
  unit_price: string;
  sort_order: number;
}

export interface Quote {
  id: string;
  company_id: string;
  job_id: string;
  status: QuoteStatus;
  revision_number: number;
  tax_rate: string;
  discount_type: DiscountType | null;
  discount_value: string;
  expiry_date: string | null;  // ISO date
  sent_at: string | null;
  viewed_at: string | null;
  approved_at: string | null;
  declined_at: string | null;
  decline_reason: string | null;
  decline_detail: string | null;
  admin_notes: string | null;
  line_items: QuoteLineItem[];
  // Computed totals (from_orm_with_totals)
  subtotal: string;
  discount_amount: string;
  tax_amount: string;
  total: string;
  version: number;
  created_at: string;
  updated_at: string;
}

export interface QuoteTemplate {
  id: string;
  company_id: string;
  name: string;
  description: string | null;
  line_items_json: string;  // JSON string — parse before use
  tax_rate: string;
}

export interface InvoiceLineItem {
  id: string;
  invoice_id: string;
  item_type: ItemType;
  description: string;
  quantity: string;
  unit: string;
  unit_price: string;
  sort_order: number;
}

export interface Invoice {
  id: string;
  company_id: string;
  job_id: string;
  quote_id: string | null;
  invoice_number: string;
  status: InvoiceStatus;
  tax_rate: string;
  discount_type: DiscountType | null;
  discount_value: string;
  due_date: string | null;
  issued_at: string;
  finalized_at: string | null;
  amount_paid: string;  // NEW field after migration
  line_items: InvoiceLineItem[];
  subtotal: string;
  discount_amount: string;
  tax_amount: string;
  total: string;
  version: number;
  created_at: string;
  updated_at: string;
}
```

**Note on Decimal:** FastAPI serializes Python `Decimal` as a JSON number or string depending on the field. Treat all financial fields as strings in TypeScript and use `parseFloat()` or `Number()` only for display calculations.

### StatusBadge Extensions (web/src/components/shared/status-badge.tsx)
```typescript
// Source: web/src/components/shared/status-badge.tsx — add to colorMap
const colorMap: Record<string, string> = {
  // existing entries ...
  // Quote statuses
  viewed: "bg-purple-100 text-purple-800",
  expired: "bg-orange-100 text-orange-800",
  revised: "bg-gray-100 text-gray-700",
  // Invoice statuses
  unpaid: "bg-yellow-100 text-yellow-800",
  partially_paid: "bg-blue-100 text-blue-800",
  finalized: "bg-teal-100 text-teal-800",
  // Computed
  overdue: "bg-red-100 text-red-800",  // already exists
};
```

### Backend: amount_paid Migration Pattern
```python
# Source: existing migration pattern in backend/alembic/
# Add to new migration file:
def upgrade() -> None:
    op.add_column(
        "invoices",
        sa.Column(
            "amount_paid",
            sa.Numeric(10, 2),
            nullable=False,
            server_default="0",
        ),
    )

def downgrade() -> None:
    op.drop_column("invoices", "amount_paid")
```

### Quote Builder Financial Summary Calculation
```typescript
// Live totals computed from watched form values
const lineItems = watch("line_items");
const taxRate = watch("tax_rate");
const discountType = watch("discount_type");
const discountValue = watch("discount_value");

const subtotal = lineItems.reduce(
  (sum, item) => sum + (Number(item.quantity) || 0) * (Number(item.unit_price) || 0),
  0
);
const discountAmount =
  discountType === "percent"
    ? (subtotal * Number(discountValue)) / 100
    : discountType === "fixed"
    ? Math.min(Number(discountValue), subtotal)
    : 0;
const taxAmount = ((subtotal - discountAmount) * Number(taxRate)) / 100;
const total = subtotal - discountAmount + taxAmount;
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| react-beautiful-dnd | dnd-kit | 2022 (rbd archived) | Must use dnd-kit for new drag-drop |
| Pages Router + getServerSideProps | App Router + useSearchParams + Suspense | Phase 13 | Suspense boundary required |
| useQuery for all state | TanStack Query (server) + Redux (UI only) | Phase 13 decision | URL params for bookmarkable lists |

**Deprecated/outdated:**
- react-beautiful-dnd: archived, no React 19 support
- @hello-pangea/dnd: maintained fork of rbd but dnd-kit is preferred for new code

---

## Open Questions

1. **Does QuoteResponse include job.client info (client_name, client_id)?**
   - What we know: `QuoteResponse` has `job_id`. `Quote.job` relationship is joinedloaded in repository. But `QuoteResponse` schema only has `job_id`, not the job object itself.
   - What's unclear: How does the quote detail sidebar show "Client Name"? Must make a second `GET /api/v1/jobs/{job_id}` call, or the backend list endpoint must be enhanced to include job/client info.
   - Recommendation: Fetch the job separately in the detail page (`useQuery` for job using `quote.job_id`). For the list page, client name can be omitted or fetched per row lazily, or the backend list endpoint can be enhanced to embed a `client_name` field (additive-only).

2. **Quote list — does the backend support status filter on GET /quotes/?**
   - What we know: `get_active_quotes()` returns all non-deleted non-revised quotes. The new list endpoint should add optional `?status=` filter.
   - What's unclear: Whether per-status count queries can be done efficiently client-side (fetch all, count) vs separate requests.
   - Recommendation: Fetch all quotes once (they are tenant-scoped and typically small datasets), count per-status client-side. This matches Phase 14 jobs pattern.

3. **Alembic migration file location**
   - What we know: `backend/alembic/versions/` returns no files via Glob (directory may be empty or have a different path).
   - What's unclear: Whether migrations use Alembic or a different tool.
   - Recommendation: Check `backend/alembic/` directory structure in Wave 0. If empty, may be a fresh migration setup — create the first version file.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Playwright 1.58.2 (web E2E) + pytest (backend integration) |
| Config file | `web/playwright.config.ts` |
| Quick run command | `cd web && npm run test-e2e:chromium -- --grep "quotes"` |
| Full suite command | `cd web && npm run test-e2e` |
| Backend quick run | `cd backend && uv run python -m pytest tests/test_phase_16_e2e.py -x` |
| Backend full suite | `cd backend && uv run python -m pytest` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| QUOTE-01 | Quotes list shows all quotes with status tabs and badges | E2E (Playwright) | `npm run test-e2e:chromium -- --grep "quotes list"` | Wave 0 |
| QUOTE-02 | Quote builder: add row, edit inline, drag reorder, load template, preview toggle | E2E (Playwright) | `npm run test-e2e:chromium -- --grep "quote builder"` | Wave 0 |
| QUOTE-03 | Send quote: confirmation dialog, status transitions to sent | E2E (Playwright) | `npm run test-e2e:chromium -- --grep "send quote"` | Wave 0 |
| QUOTE-04 | PDF download: blob response triggers file download | E2E (Playwright) | `npm run test-e2e:chromium -- --grep "quote pdf"` | Wave 0 |
| INV-01 | Invoices list with payment status tabs, overdue computed row highlight | E2E (Playwright) | `npm run test-e2e:chromium -- --grep "invoices list"` | Wave 0 |
| INV-02 | Record partial payment updates Paid/Balance display, Mark Fully Paid works | E2E (Playwright) | `npm run test-e2e:chromium -- --grep "invoice payment"` | Wave 0 |
| INV-03 | Invoice PDF download triggers file | E2E (Playwright) | `npm run test-e2e:chromium -- --grep "invoice pdf"` | Wave 0 |
| Backend migration | amount_paid field present, MarkPaidRequest accepts amount | Integration (pytest) | `uv run python -m pytest tests/test_phase_16_e2e.py -x` | Wave 0 |
| Backend list endpoints | GET /quotes/ and GET /invoices/ return 200 with list | Integration (pytest) | `uv run python -m pytest tests/test_phase_16_e2e.py -x` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd web && npm run test-e2e:chromium -- --grep "phase-16" --reporter=line` (smoke test)
- **Per wave merge:** `cd web && npm run test-e2e:chromium` (full chromium suite)
- **Phase gate:** Full Playwright suite + `uv run python -m pytest` green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `web/tests/phase-16-quotes.spec.ts` — covers QUOTE-01 through QUOTE-04
- [ ] `web/tests/phase-16-invoices.spec.ts` — covers INV-01 through INV-03
- [ ] `backend/tests/test_phase_16_e2e.py` — covers list endpoints, amount_paid migration, payment recording
- [ ] Backend Alembic migration file for `amount_paid` — run `cd backend && alembic revision --autogenerate -m "add_amount_paid_to_invoices"`

---

## Sources

### Primary (HIGH confidence)
- Direct code inspection: `backend/app/features/quotes/router.py`, `schemas.py`, `models.py`, `service.py`, `repository.py`
- Direct code inspection: `backend/app/features/invoices/router.py`, `schemas.py`, `models.py`, `service.py`, `repository.py`
- Direct code inspection: `web/src/app/(dashboard)/jobs/page.tsx` — DataTable pattern
- Direct code inspection: `web/src/app/(dashboard)/jobs/[id]/page.tsx` — two-column detail pattern
- Direct code inspection: `web/src/lib/api-client.ts` — proxy pattern, binary limitation
- Direct code inspection: `web/src/components/shared/status-badge.tsx` — colorMap
- Direct code inspection: `web/src/components/layout/sidebar.tsx` — Quotes/Invoices already in navItems
- Direct code inspection: `web/package.json` — confirmed installed packages

### Secondary (MEDIUM confidence)
- dnd-kit as current standard over react-beautiful-dnd: archived status of rbd is documented fact (https://github.com/atlassian/react-beautiful-dnd); dnd-kit npm downloads and maintenance verified by package inspection
- react-hook-form useFieldArray pattern: confirmed in installed version ^7.71.2; API stable since v7

### Tertiary (LOW confidence)
- Alembic migration file structure: could not locate migration files at `backend/alembic/versions/` — may be different path or empty. Verify before Wave 0.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages confirmed in package.json; no new packages except dnd-kit
- Architecture: HIGH — patterns copied directly from Phase 14 code; API surface fully inspected
- Pitfalls: HIGH — all derived from direct code inspection, not inference
- Backend gaps (missing list endpoints): HIGH — confirmed by reading both router files end-to-end; no GET / exists

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (stable stack)
