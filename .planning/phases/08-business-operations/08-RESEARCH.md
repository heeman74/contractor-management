# Phase 8: Business Operations - Research

**Researched:** 2026-03-13
**Domain:** Digital quoting, invoice generation, PDF export, Flutter charting, offline sync extension
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Quote Structure & Line Items**
- Line items have two types: Labor and Material — each with description, quantity, unit, unit price, and subtotal
- Selectable unit of measurement per line item: each, hour, day, sqm, sqft, meter, liter, etc. Displayed as "Qty x Unit @ Price"
- Tax: single tax rate (%) applied to subtotal
- Discount: optional discount (% or fixed amount) applied before tax
- Quote always belongs to a job (at Quote stage) — no standalone quotes
- When job originated from a client request with budget range, show as reference banner in quote builder (e.g., "Client budget: $2,000–$3,000") — no auto-population
- Basic quote templates: admin can save a quote as a template and load it when creating new quotes (template CRUD)
- Optional expiry date: admin can set expiry; after expiry, client can view but can't approve; admin can extend and resend
- 1–100 line items per quote

**Quote Delivery & Approval**
- Clients receive quotes in-app via portal + push notification (Phase 7 FCM infrastructure) — no email/PDF delivery in v1
- Draft state: quotes start as draft (admin-only visible), admin can save/edit, then explicitly "send" to make visible to client
- Preview before send: admin sees quote as client will see it, confirms before sending
- Full line-item breakdown visible to client in portal (descriptions, quantities, unit prices, subtotals, discount, tax, total)
- Read receipts: admin sees "Viewed by client on [date]" when client opens the quote
- Decline flow: client picks a decline reason (too expensive, wrong scope, changed mind, other + text). Admin gets notified, can revise and resend
- Unlimited revisions: each revision is versioned (v1, v2, v3...). Client always sees latest version only — no revision history for clients
- Approval auto-transitions job from Quote → Scheduled (if contractor and dates assigned)
- Expired quotes block approval — show "Expired" badge, client can view but can't approve. Admin can extend expiry. No auto-decline
- Quote events (sent, viewed, approved, declined, revised) logged in job status_history JSONB — visible in History tab

**Invoice Generation & Format**
- One-tap generation from approved quote line items: admin taps "Generate Invoice" on a completed job
- Invoice auto-populates from quote (same items, quantities, prices, tax, discount) but is editable before finalizing — admin can add/remove/modify items for change orders
- In-app view + PDF download for both quotes and invoices — same PDF generation infrastructure serves both
- Sequential invoice numbers per company with optional admin-configurable prefix (e.g., INV-0001, ACME-0001)
- Optional due date on invoices — displayed on invoice and PDF
- Manual payment status tracking: Unpaid, Partially Paid, Paid — no actual payment processing (deferred to v2)
- Invoice generation transitions job to Invoiced status

**Reporting Dashboard**
- Four metrics: (1) Jobs by status bar/pie chart, (2) Revenue summary bar chart by month paid vs unpaid stacked, (3) Contractor utilization horizontal bar chart by utilization %, (4) Quote conversion rate approved vs declined
- Date range: quick presets (This Week, This Month, Last 30 Days, This Quarter, This Year, All Time) + custom date range picker
- Access: admin sees full dashboard; contractors see limited view (own utilization and job stats only, no revenue data)
- Real-time queries — live data on each load, no pre-computed aggregates
- No data export in v1 — deferred to v2 (ADV-03)
- New bottom nav tab "Reports" for admin; contractors see simpler version in their nav

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

### Deferred Ideas (OUT OF SCOPE)
- Email delivery of quotes/invoices with PDF attachment — future enhancement
- In-app payment processing via Stripe/Square — v2 (PAY-01)
- Automated payment reminders — v2 (PAY-03)
- Data export to CSV/Excel from dashboard — v2 (ADV-03)
- QuickBooks/Xero accounting integration — v2 (ADV-05)
- Quote/invoice email notifications (beyond push) — future enhancement
- Advanced reporting and analytics — v2 (ADV-03)
- Recurring invoice automation — v2 (ADV-04)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BIZ-01 | Digital quoting/estimates with line items | Quote data model (backend migration 0011), Drift tables v6, line item types (Labor/Material), template CRUD, admin quote builder UI |
| BIZ-02 | Quote approval flow (send to client, client approves/declines) | FCM notification reuse (Phase 7), client portal tab extension, draft→sent state, revision versioning, read receipt pattern via viewed_at timestamp |
| BIZ-03 | Digital invoicing generated from completed jobs | One-tap generation endpoint, invoice data model (migration 0011), Drift tables, PDF download via WeasyPrint, sequential numbering pattern |
| BIZ-04 | Basic reporting dashboard (jobs by status, revenue, contractor utilization) | fl_chart 1.2.0 for BarChart/PieChart, real-time backend aggregate queries, new Reports tab in AppShell/StatefulShellRoute |
</phase_requirements>

---

## Summary

Phase 8 adds four interconnected business operations capabilities to an already-complete Phase 7 codebase: digital quoting, quote approval flow, invoice generation, and a reporting dashboard. The codebase is mature with well-established patterns for sync, RLS, tenant scoping, and Flutter state management — new entities follow exactly the same patterns as JobNote, Attachment, and TimeEntry from Phase 6.

The two new external dependencies are: **fl_chart 1.2.0** (Flutter chart library, MIT, zero native dependencies) for the reporting dashboard, and **WeasyPrint 68.1** (Python HTML-to-PDF) for PDF export of quotes and invoices. Both are well-established, production-ready, and straightforward to integrate. WeasyPrint is synchronous and must be wrapped in `asyncio.get_event_loop().run_in_executor()` to avoid blocking FastAPI's async event loop.

The primary architectural challenge is the Drift schema version bump (v5 → v6) to add five new tables (quotes, quote_line_items, invoices, invoice_line_items, quote_templates), the corresponding Alembic migration (0011), and registering four new SyncHandlers. The reporting dashboard uses live backend queries — no pre-computed aggregates, no new Drift tables for dashboard data. The Reports tab requires a new StatefulShellBranch (Branch 7) in AppShell with role-based visibility.

**Primary recommendation:** Follow established Phase 6 patterns exactly — new models inherit TenantScopedModel, new services inherit TenantScopedService, new Drift tables get SyncHandlers, and the AppDatabase schemaVersion bumps to 6 with explicit migration steps.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| fl_chart | 1.2.0 | Flutter charting (bar, pie, line, radar) | Most popular Flutter chart library (7k+ likes, 1M+ downloads), MIT license, no native dependencies, renders BarChart/PieChart for all 4 dashboard metrics |
| WeasyPrint | 68.1 | Python HTML-to-PDF for quote/invoice PDFs | Converts HTML+CSS to PDF; simpler than ReportLab for invoice-style layouts; actively maintained (Feb 2026 release); Python 3.12 compatible |
| SQLAlchemy 2.0 | existing | ORM for Quote, Invoice models | Already in stack; inherit TenantScopedModel per CLAUDE.md rules |
| Drift 2.32 | existing | Local SQLite for offline quote/invoice access | Already in stack; new tables added via schema migration v6 |
| FastAPI 0.115 | existing | REST endpoints for quotes, invoices, reporting | Already in stack |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Jinja2 | existing (FastAPI dep) | HTML template rendering for WeasyPrint | PDF template — already available as FastAPI transitive dependency |
| aiofiles | 24.1.0 | Async file write (already in stack) | PDF file caching if needed |
| firebase-admin 6.6.0 | existing | FCM notifications for quote events | Already wired in Phase 7; reuse for quote sent/approved/declined notifications |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| fl_chart | syncfusion_flutter_charts | Syncfusion requires commercial license for production apps, community license has attribution requirements; fl_chart is MIT |
| fl_chart | charts_flutter | charts_flutter is abandoned (Google ceased maintenance); fl_chart is actively maintained |
| WeasyPrint | ReportLab | ReportLab uses Python drawing API (complex, verbose for invoice layouts); WeasyPrint accepts HTML/CSS (familiar, easier to design) |
| WeasyPrint | Playwright PDF | Playwright requires Chromium binary (~400MB); too heavy for a backend server |
| Live reporting queries | Pre-computed aggregates | Pre-computed aggregates need cache invalidation strategy; "real-time queries on each load" is locked decision; dataset size small enough that live queries are fast |

**Installation (backend):**
```bash
# From backend/ directory
uv add weasyprint
```

**Installation (Flutter):**
```yaml
# In mobile/pubspec.yaml dependencies:
fl_chart: ^1.2.0
```

---

## Architecture Patterns

### Recommended Project Structure

**Backend — new feature directories:**
```
backend/app/features/
├── quotes/
│   ├── __init__.py
│   ├── models.py          # Quote, QuoteLineItem, QuoteTemplate
│   ├── repository.py      # TenantScopedRepository subclass
│   ├── schemas.py         # Pydantic request/response schemas
│   ├── service.py         # TenantScopedService subclass
│   └── router.py          # CRUDRouter mixin + custom endpoints
├── invoices/
│   ├── __init__.py
│   ├── models.py          # Invoice, InvoiceLineItem
│   ├── repository.py
│   ├── schemas.py
│   ├── service.py         # includes generate_from_quote(), PDF download
│   └── router.py
├── reports/
│   ├── __init__.py
│   ├── schemas.py         # ReportingDashboardResponse, metric schemas
│   ├── service.py         # Live aggregate queries
│   └── router.py          # GET /reports/dashboard + /reports/contractor
└── pdf/
    ├── __init__.py
    ├── templates/
    │   ├── quote.html     # Jinja2 template for quote PDF
    │   └── invoice.html   # Jinja2 template for invoice PDF
    └── service.py         # PDF generation via WeasyPrint + run_in_executor
```

**Flutter — new feature directories:**
```
mobile/lib/features/
├── quotes/
│   ├── data/
│   │   ├── quote_dao.dart
│   │   └── quote_sync_handler.dart
│   ├── domain/
│   │   ├── quote_entity.dart
│   │   └── line_item_entity.dart
│   └── presentation/
│       ├── providers/quote_providers.dart
│       ├── screens/
│       │   ├── quote_builder_screen.dart   # admin: create/edit quote
│       │   ├── quote_preview_screen.dart   # admin: preview before send
│       │   └── quote_detail_screen.dart    # client: view + approve/decline
│       └── widgets/
│           ├── line_item_form.dart
│           └── quote_summary_card.dart
├── invoices/
│   ├── data/
│   │   ├── invoice_dao.dart
│   │   └── invoice_sync_handler.dart
│   ├── domain/invoice_entity.dart
│   └── presentation/
│       ├── providers/invoice_providers.dart
│       └── screens/invoice_detail_screen.dart
└── reports/
    └── presentation/
        ├── providers/reports_providers.dart    # AsyncNotifier, live API calls
        └── screens/
            ├── admin_reports_screen.dart
            └── contractor_reports_screen.dart
```

**New Drift tables (mobile/lib/core/database/tables/):**
```
tables/
├── quotes.dart
├── quote_line_items.dart
├── quote_templates.dart
├── invoices.dart
└── invoice_line_items.dart
```

### Pattern 1: Backend Quote/Invoice Model Design

**What:** TenantScopedModel subclasses for quotes and invoices with JSONB for flexible line item metadata when needed, but normalized line item tables for query efficiency.

**When to use:** Normalized tables (not JSONB) for line items because the reporting queries need to aggregate by line item type (Labor vs Material). JSONB is used only for metadata that is never queried (e.g., decline_reason_detail).

```python
# Source: established pattern from backend/app/features/jobs/models.py
class Quote(TenantScopedModel):
    __tablename__ = "quotes"

    job_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("jobs.id"), nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="draft")
    revision_number: Mapped[int] = mapped_column(Integer, nullable=False, server_default="1")
    tax_rate: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False, server_default="0")
    discount_type: Mapped[str | None] = mapped_column(Text, nullable=True)  # 'percent' | 'fixed'
    discount_value: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False, server_default="0")
    expiry_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    viewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    declined_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    decline_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    decline_detail: Mapped[str | None] = mapped_column(Text, nullable=True)
    admin_notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    __table_args__ = (
        CheckConstraint(
            "status IN ('draft','sent','viewed','approved','declined','expired','revised')",
            name="quotes_status_check",
        ),
        CheckConstraint(
            "discount_type IN ('percent','fixed') OR discount_type IS NULL",
            name="quotes_discount_type_check",
        ),
    )
    # relationships: job (joinedload many-to-one), line_items (selectinload one-to-many)
```

```python
class QuoteLineItem(TenantScopedModel):
    __tablename__ = "quote_line_items"

    quote_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("quotes.id"), nullable=False)
    item_type: Mapped[str] = mapped_column(Text, nullable=False)  # 'labor' | 'material'
    description: Mapped[str] = mapped_column(Text, nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    unit: Mapped[str] = mapped_column(Text, nullable=False)  # 'each','hour','day','sqm','sqft','meter','liter'
    unit_price: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    __table_args__ = (
        CheckConstraint("item_type IN ('labor','material')", name="quote_line_items_type_check"),
    )
```

```python
class Invoice(TenantScopedModel):
    __tablename__ = "invoices"

    job_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("jobs.id"), nullable=False)
    quote_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("quotes.id"), nullable=True)
    invoice_number: Mapped[str] = mapped_column(Text, nullable=False)  # e.g., "INV-0001"
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="unpaid")
    tax_rate: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False, server_default="0")
    discount_type: Mapped[str | None] = mapped_column(Text, nullable=True)
    discount_value: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False, server_default="0")
    due_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    finalized_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        CheckConstraint("status IN ('unpaid','partially_paid','paid')", name="invoices_status_check"),
        UniqueConstraint("company_id", "invoice_number", name="invoices_company_invoice_number_key"),
    )
```

### Pattern 2: Sequential Invoice Numbering

**What:** A company-level sequence counter that generates `{prefix}-{padded_number}` invoice numbers atomically.

**When to use:** Invoice generation — must be atomic to prevent duplicate numbers under concurrent requests.

```python
# Source: SQLAlchemy 2.0 pattern — SELECT FOR UPDATE SKIP LOCKED
async def generate_invoice_number(self, db: AsyncSession, company_id: uuid.UUID) -> str:
    """Atomically generate the next invoice number for the company.

    Uses SELECT FOR UPDATE to prevent concurrent duplicate generation.
    Company row must exist with invoice_prefix and invoice_sequence columns.
    """
    # Lock the company row during generation
    result = await db.execute(
        select(Company)
        .where(Company.id == company_id)
        .with_for_update()
    )
    company = result.scalar_one()
    next_seq = (company.invoice_sequence or 0) + 1
    company.invoice_sequence = next_seq
    prefix = company.invoice_prefix or "INV"
    return f"{prefix}-{next_seq:04d}"
    # db.flush() to get the number before outer commit
```

The Company model needs two new columns (migration 0011): `invoice_prefix TEXT DEFAULT 'INV'` and `invoice_sequence INTEGER DEFAULT 0`.

### Pattern 3: PDF Generation via WeasyPrint (Non-Blocking)

**What:** WeasyPrint is synchronous; must run in thread pool to avoid blocking FastAPI's async event loop.

**When to use:** All PDF generation endpoints — GET /quotes/{id}/pdf and GET /invoices/{id}/pdf.

```python
# Source: FastAPI async + blocking library pattern
import asyncio
from weasyprint import HTML
from fastapi.responses import Response
from jinja2 import Environment, FileSystemLoader

_jinja_env = Environment(loader=FileSystemLoader("app/features/pdf/templates"))

async def generate_pdf(template_name: str, context: dict) -> bytes:
    """Render HTML template and convert to PDF bytes in thread pool.

    WeasyPrint.write_pdf() is CPU-bound and blocking — must run in executor
    to avoid blocking the FastAPI event loop.
    """
    # Render HTML synchronously (fast, no I/O)
    template = _jinja_env.get_template(template_name)
    html_content = template.render(**context)

    # Run blocking WeasyPrint in thread pool
    loop = asyncio.get_event_loop()
    pdf_bytes = await loop.run_in_executor(
        None,
        lambda: HTML(string=html_content).write_pdf()
    )
    return pdf_bytes

# FastAPI endpoint
@router.get("/{quote_id}/pdf")
async def download_quote_pdf(
    quote_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> Response:
    quote = await quote_service.get_with_line_items(db, quote_id)
    pdf_bytes = await generate_pdf("quote.html", {"quote": quote, "company": ...})
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=quote-{quote.revision_number}.pdf"},
    )
```

### Pattern 4: Read Receipt Implementation

**What:** Track when a client first views a quote by updating `viewed_at` timestamp when the client fetches the quote detail.

**When to use:** Quote detail GET endpoint — update `viewed_at` only if it is currently NULL (first view only).

```python
# Source: established pattern — db.flush() for ID before commit (CLAUDE.md)
async def record_view(self, db: AsyncSession, quote_id: uuid.UUID, viewer_id: uuid.UUID) -> Quote:
    """Record first view by client. Idempotent — only sets viewed_at once."""
    quote = await self.repository.get(db, quote_id)
    if quote.viewed_at is None:
        quote.viewed_at = datetime.now(UTC)
        # Append event to job's status_history JSONB
        await self._append_status_history_event(
            db, quote.job_id, "quote_viewed", viewer_id
        )
    return quote
```

### Pattern 5: fl_chart Dashboard Widgets

**What:** fl_chart BarChart and PieChart for the four dashboard metrics. Use `AsyncNotifier` providers that call backend reporting API endpoints directly (no Drift caching for dashboard data).

**When to use:** Reports tab screens — live data on load.

```dart
// Source: fl_chart 1.2.0 pub.dev documentation
BarChart(
  BarChartData(
    barGroups: revenueData.map((month) => BarChartGroupData(
      x: month.index,
      barRods: [
        BarChartRodData(toY: month.paid, color: Colors.green),
        BarChartRodData(toY: month.unpaid, color: Colors.orange),
      ],
    )).toList(),
    titlesData: FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (value, meta) => Text(monthLabel(value.toInt())),
        ),
      ),
    ),
  ),
)
```

```dart
// Contractor utilization — horizontal bar chart
BarChart(
  BarChartData(
    barGroups: contractorData.mapIndexed((i, c) => BarChartGroupData(
      x: i,
      barRods: [BarChartRodData(toY: c.utilizationPercent, width: 20)],
    )).toList(),
    // rotationQuarterTurns: 1 for horizontal layout (fl_chart supports this)
  ),
)
```

### Pattern 6: New Reports Tab in AppShell

**What:** Add Branch 7 (Reports) to the StatefulShellRoute. AppShell already shows/hides tabs based on role — same pattern for Reports tab (admin full, contractor limited).

**When to use:** `_buildTabs()` in `app_shell.dart` — add Reports tab conditionally for admin and contractor.

```dart
// Source: mobile/lib/shared/widgets/app_shell.dart — follow existing _buildTabs pattern
// Add to AppShell._buildTabs():
_AppTab(
  label: 'Reports',
  icon: Icons.bar_chart_outlined,
  selectedIcon: Icons.bar_chart,
  branchIndex: 7,  // new Branch 7 in router
),
```

Router: add Branch 7 in `app_router.dart`:
```dart
// Branch 7: Reports (admin + contractor limited)
StatefulShellBranch(
  routes: [
    GoRoute(
      path: RouteNames.reports,
      builder: (context, state) {
        // Role-based screen selection — same pattern as Branch 2 (Schedule)
        final isAdmin = ...; // read from authNotifierProvider
        return isAdmin ? const AdminReportsScreen() : const ContractorReportsScreen();
      },
    ),
  ],
),
```

### Pattern 7: Drift Schema v6 Migration

**What:** Bump `schemaVersion` from 5 to 6 and add migration steps for five new tables. Follow exact pattern from `app_database.dart`.

**When to use:** `AppDatabase.migration` — add `if (from < 6)` block.

```dart
// Source: mobile/lib/core/database/app_database.dart — established pattern
if (from < 6) {
  await m.createTable(quotes);
  await m.createTable(quoteLineItems);
  await m.createTable(quoteTemplates);
  await m.createTable(invoices);
  await m.createTable(invoiceLineItems);
  // Add quote_id and invoice_id columns to jobs table
  await m.addColumn(jobs, jobs.quoteId);
  await m.addColumn(jobs, jobs.invoiceId);
}
```

### Pattern 8: SyncHandler Registration for New Entities

**What:** Four new SyncHandlers following the exact NoteSyncHandler pattern — one each for quotes, invoices, quote_line_items, invoice_line_items (or handle line items within parent handlers).

**Decision:** Line items are owned by their parent (quote/invoice). Handle line item sync inside the quote/invoice handler by pushing the full parent+items payload. This avoids four separate entity types in the sync queue for what is logically one operation.

```dart
// Source: mobile/lib/core/sync/sync_handler.dart + handlers/note_sync_handler.dart
class QuoteSyncHandler extends SyncHandler {
  @override
  String get entityType => 'quote';

  @override
  Future<void> push(SyncQueueData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    final jobId = payload['job_id'] as String;
    if (item.operation == 'CREATE') {
      await _dioClient.pushWithIdempotency('/jobs/$jobId/quotes', payload, item.id);
    } else if (item.operation == 'UPDATE') {
      await _dioClient.pushWithIdempotency(
        '/jobs/$jobId/quotes/${item.entityId}', payload, item.id, method: 'PATCH');
    }
  }
  // applyPulled: upsert Quote + clear/reinsert QuoteLineItems atomically
}
```

**SyncResponse extension** — add to backend `sync/schemas.py` (default empty list for backwards compat):
```python
# Phase 8 — business operations entities
quotes: list[QuoteResponse] = []
invoices: list[InvoiceResponse] = []
```

### Pattern 9: Reporting Aggregate Queries (Backend)

**What:** Live aggregate SQL queries using SQLAlchemy 2.0 `func` expressions. No ORM models for reports — raw query results returned as Pydantic schemas.

```python
# Source: SQLAlchemy 2.0 Core API — aggregate queries
from sqlalchemy import func, case, select

async def get_revenue_by_month(
    self, db: AsyncSession, company_id: uuid.UUID, since: date, until: date
) -> list[RevenueByMonthRow]:
    """Aggregate paid vs unpaid invoice totals by month. RLS auto-scopes by company."""
    result = await db.execute(
        select(
            func.date_trunc('month', Invoice.issued_at).label('month'),
            func.sum(
                case((Invoice.status == 'paid', Invoice.total_amount), else_=0)
            ).label('paid_total'),
            func.sum(
                case((Invoice.status != 'paid', Invoice.total_amount), else_=0)
            ).label('unpaid_total'),
        )
        .where(Invoice.issued_at.between(since, until))
        .group_by(func.date_trunc('month', Invoice.issued_at))
        .order_by(func.date_trunc('month', Invoice.issued_at))
    )
    return [RevenueByMonthRow(month=r.month, paid=r.paid_total, unpaid=r.unpaid_total)
            for r in result.all()]
```

Contractor utilization query joins time_entries with bookings to calculate booked hours vs available hours per contractor.

### Anti-Patterns to Avoid

- **JSONB for line items:** Do NOT store line items as JSONB array on the quote — use normalized table. Reporting queries need `GROUP BY item_type` which is impossible with JSONB.
- **Sync all dashboard data:** Do NOT add dashboard metrics to Drift. Reports are always live API calls — offline reports show a "Connect to view reports" placeholder.
- **Call WeasyPrint directly in async endpoint:** WeasyPrint.write_pdf() is blocking/CPU-bound. ALWAYS wrap in `run_in_executor`. Calling it directly in `async def` will block all other requests.
- **Overwrite quote on revision:** Each revision should create a new Quote row (or increment revision_number on the same row with history stored in status_history JSONB). Client sees only the latest — no hard deletion of old revision data.
- **Add invoice_number generation inside service without locking:** Invoice number generation requires a row-level lock (SELECT FOR UPDATE on company row) to prevent duplicates under concurrent requests. Do not use simple count()+1 without locking.
- **Store quote_id / invoice_id as FK on jobs table in Drift text column without nullable:** Quote and invoice are optional — jobs at Quote stage may not have a quote yet. Always nullable.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Chart rendering | Custom CustomPainter charts | fl_chart 1.2.0 | Correct axis scaling, touch events, legend, animation — all handled; chart rendering has many edge cases |
| HTML-to-PDF | Custom PDF layout engine | WeasyPrint 68.1 | CSS-based layout handles page breaks, header/footer, font sizing automatically |
| Quote numbering / sequential IDs | UUID-based quote refs | Dedicated invoice_sequence counter with SELECT FOR UPDATE | Concurrent users will generate duplicate numbers without atomic locking |
| Date range filtering | Custom calendar widget | Flutter's `showDateRangePicker()` (Material built-in) | Already available, consistent Material 3 UX |
| FCM notifications for quote events | New notification infrastructure | Phase 7 NotificationService (already wired) | `await notification_service.notify_user(client_id, title, body)` is one call |
| PDF serving | Store PDFs on disk and serve files | Generate on-demand, return bytes | On-demand generation avoids storage management; invoices are small |

**Key insight:** The chart library (fl_chart) and PDF library (WeasyPrint) together eliminate the two hardest custom-build problems in this phase. Everything else is pattern replication from existing phases.

---

## Common Pitfalls

### Pitfall 1: WeasyPrint Blocking the Event Loop
**What goes wrong:** Calling `HTML(string=html).write_pdf()` inside an `async def` endpoint blocks all other requests for the duration of PDF generation (typically 200-500ms per PDF).
**Why it happens:** WeasyPrint is a purely synchronous CSS layout engine — no async API exists.
**How to avoid:** Always use `await loop.run_in_executor(None, lambda: HTML(string=html).write_pdf())`.
**Warning signs:** Health check timeouts during PDF generation; all endpoints slow simultaneously during PDF downloads.

### Pitfall 2: Quote Revision Confusion
**What goes wrong:** Overwriting the quote row on revision means the client's approval/decline of "v1" is lost; admin has no audit trail of what was accepted.
**Why it happens:** Simple UPDATE seems natural for "editing."
**How to avoid:** On revision, update `revision_number += 1`, set `status = 'revised'`, log revision event in job `status_history` JSONB. All prior events remain in the JSONB array.
**Warning signs:** Client sees "Approved" but admin can't see what they approved.

### Pitfall 3: fl_chart BarChart Stacked vs Grouped
**What goes wrong:** Revenue chart shows bars side-by-side instead of stacked (paid vs unpaid).
**Why it happens:** fl_chart uses `BarChartRodData.rodStackItems` for stacked bars, not multiple `barRods`.
**How to avoid:** Use a single `BarChartRodData` with `rodStackItems: [BarChartRodStackItem(0, paid, Colors.green), BarChartRodStackItem(paid, paid+unpaid, Colors.orange)]`.
**Warning signs:** Two separate bars per month instead of one stacked bar.

### Pitfall 4: Invoice Number Uniqueness Under Concurrency
**What goes wrong:** Two admins generate invoices simultaneously and get the same invoice number (e.g., both get INV-0005).
**Why it happens:** `SELECT MAX(invoice_sequence) + 1` is not atomic — both reads happen before either write.
**How to avoid:** Use `SELECT FOR UPDATE` on the company row to lock during generation, or use a PostgreSQL SEQUENCE. `SELECT FOR UPDATE` is the simplest approach consistent with existing patterns.
**Warning signs:** Duplicate invoice numbers appear in the database; `UniqueConstraint` violation errors.

### Pitfall 5: Drift Schema Version Not Bumped
**What goes wrong:** App crash on upgrade from v5 to v6 because migration code exists but `schemaVersion` was not incremented.
**Why it happens:** Drift's `MigrationStrategy.onUpgrade` is only called when the new `schemaVersion` exceeds the stored version.
**How to avoid:** Bump `schemaVersion` to 6 when adding `if (from < 6)` migration block.
**Warning signs:** `DatabaseException: no such table: quotes` on app launch after update.

### Pitfall 6: Reports Provider Using Drift Streams
**What goes wrong:** `StreamProvider` for dashboard data that never emits because there's no Drift table to watch.
**Why it happens:** Trying to apply the offline-first Drift pattern to dashboard data that is backend-only.
**How to avoid:** Use `AsyncNotifier` (or `FutureProvider`) for dashboard providers — they make one API call and return the result. Show "Connect to view reports" when offline.
**Warning signs:** Provider stuck in loading state; no data appears even when online.

### Pitfall 7: Missing TRUNCATE for New Tables in conftest.py
**What goes wrong:** Cross-test data contamination — invoice from test A appears in test B.
**Why it happens:** New tables (quotes, quote_line_items, invoices, invoice_line_items, quote_templates) not added to the TRUNCATE statement in `clean_tables` fixture.
**How to avoid:** Add all five new table names to the TRUNCATE TABLE list in `backend/tests/conftest.py`, in correct FK order (line items before parents, parents before jobs).
**Warning signs:** Test failures that only occur when run together, not individually.

### Pitfall 8: Quote Approval Without Checking Expiry
**What goes wrong:** Expired quote gets approved — backend should block this but client-side shows success.
**Why it happens:** Approval endpoint doesn't check `expiry_date`.
**How to avoid:** In the approve endpoint: if `quote.expiry_date` is not None and `date.today() > quote.expiry_date`, raise `HTTP 422` with message "Quote has expired."
**Warning signs:** Expired quotes in "approved" state with Invoiced job status.

---

## Code Examples

### Quote Status Enum (Backend)

```python
# Source: established StrEnum pattern from backend/app/features/jobs/schemas.py
from enum import StrEnum

class QuoteStatus(StrEnum):
    draft = "draft"
    sent = "sent"
    viewed = "viewed"
    approved = "approved"
    declined = "declined"
    expired = "expired"
    revised = "revised"
```

### Drift Quote Table Definition

```dart
// Source: established Drift table pattern from mobile/lib/core/database/tables/jobs.dart
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'companies.dart';

class Quotes extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get jobId => text()();  // references Jobs — no ORM-level FK in Drift
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get revisionNumber => integer().withDefault(const Constant(1))();
  RealColumn get taxRate => real().withDefault(const Constant(0.0))();
  TextColumn get discountType => text().nullable()();
  RealColumn get discountValue => real().withDefault(const Constant(0.0))();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  DateTimeColumn get sentAt => dateTime().nullable()();
  DateTimeColumn get viewedAt => dateTime().nullable()();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  DateTimeColumn get declinedAt => dateTime().nullable()();
  TextColumn get declineReason => text().nullable()();
  TextColumn get adminNotes => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### Reporting Provider (Flutter AsyncNotifier)

```dart
// Source: established AsyncNotifier pattern from Riverpod 3.2.1
// Note: Riverpod 3.2.1 uses .value NOT .valueOrNull (Phase 6 P05 pitfall)
import 'package:flutter_riverpod/flutter_riverpod.dart';

@riverpod
class AdminDashboardNotifier extends AsyncNotifier<AdminDashboardData> {
  @override
  Future<AdminDashboardData> build() async {
    // No streaming — single load on build
    return _fetchDashboard(dateRange: DateRange.thisMonth());
  }

  Future<void> refresh(DateRange range) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchDashboard(dateRange: range));
  }

  Future<AdminDashboardData> _fetchDashboard({required DateRange dateRange}) async {
    final dio = ref.read(dioClientProvider);
    final response = await dio.get(
      '/reports/dashboard',
      queryParameters: {'since': dateRange.start.toIso8601String(), 'until': dateRange.end.toIso8601String()},
    );
    return AdminDashboardData.fromJson(response.data as Map<String, dynamic>);
  }
}
```

### Alembic Migration 0011 Structure

```python
# Source: established raw SQL migration pattern from backend/migrations/versions/0007_scheduling_tables.py
# Use op.execute() for new tables — autogenerate unreliable for CHECK constraints (Phase 3 decision)

def upgrade() -> None:
    # Quote templates (no FK to quotes — standalone)
    op.execute("""
        CREATE TABLE quote_templates (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id UUID NOT NULL REFERENCES companies(id),
            name TEXT NOT NULL,
            line_items JSONB NOT NULL DEFAULT '[]'::jsonb,
            tax_rate NUMERIC(5,2) NOT NULL DEFAULT 0,
            version INTEGER NOT NULL DEFAULT 1,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at TIMESTAMPTZ
        )
    """)
    # quotes, quote_line_items, invoices, invoice_line_items tables
    # Add invoice_prefix, invoice_sequence to companies
    # Add RLS policies for all new tables
    # set_updated_at() trigger on all new tables (Phase 2 pattern)
```

**CRITICAL:** Add RLS policies for all new tables. Pattern from existing tables:
```sql
ALTER TABLE quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE quotes FORCE ROW LEVEL SECURITY;
CREATE POLICY quotes_tenant_isolation ON quotes
  USING (company_id = current_setting('app.current_company_id')::uuid);
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| charts_flutter (Google) | fl_chart (community) | 2021 — Google abandoned charts_flutter | Must use fl_chart; charts_flutter is unmaintained |
| ReportLab for invoice PDFs | WeasyPrint HTML-to-PDF | 2022+ trend | WeasyPrint is simpler for invoice layouts; no low-level drawing API required |
| Syncfusion charts (licensed) | fl_chart (MIT) | Ongoing | No license cost or attribution requirement with fl_chart |
| Pre-computed report aggregates | Live queries on load | Design decision | Small dataset (hundreds of jobs) — live queries are fast; no cache invalidation needed |

**Deprecated/outdated:**
- `charts_flutter`: Google ceased maintenance — do not use.
- `syncfusion_flutter_charts` community license: requires attribution in published app.

---

## Open Questions

1. **Quote template storage: JSONB vs normalized line items table**
   - What we know: Templates need to store a list of line item "starters" — not real quote_line_items (no quote_id)
   - What's unclear: Whether templates need to be queried/filtered by line item type
   - Recommendation: Store template line items as JSONB on quote_templates (they are never aggregated or queried individually — just loaded and copied). This avoids a template_line_items join table.

2. **Offline quote creation — what's accessible offline?**
   - What we know: Quote creation requires job context (job_id); jobs sync to Drift
   - What's unclear: Whether clients should be able to view quotes offline (they are pushed to Drift via sync)
   - Recommendation: Sync quotes/invoices to Drift for offline read access. Quote creation and approval actions always require connectivity (push to sync_queue). Show "Pending sync" state for actions queued offline.

3. **Quote approval → job transition race condition**
   - What we know: Approval auto-transitions job from Quote → Scheduled IF contractor and dates are assigned; if not assigned, quote can still be approved but job stays in Quote status
   - What's unclear: Exact condition — does "dates assigned" mean bookings exist?
   - Recommendation: Check `job.contractor_id is not None AND len(job.bookings) > 0` before auto-transitioning. If condition not met, approve the quote but leave job in Quote status. Add a note to job status_history explaining why transition didn't happen.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Backend framework | pytest 8.3.4 + pytest-asyncio 0.25.3 |
| Backend config | `backend/pyproject.toml` (asyncio_mode=auto) |
| Flutter framework | flutter_test + mocktail 1.0.4 |
| Backend quick run | `cd backend && uv run python -m pytest tests/integration/test_phase_8_e2e.py -x` |
| Backend full suite | `cd backend && uv run python -m pytest` |
| Flutter quick run | `cd mobile && flutter test test/e2e/phase_8_business_ops_e2e_test.dart` |
| Flutter full suite | `cd mobile && flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BIZ-01 | Admin creates quote with Labor+Material line items, tax, discount | integration | `pytest tests/integration/test_phase_8_e2e.py::test_create_quote_with_line_items -x` | ❌ Wave 0 |
| BIZ-01 | Quote template save and load | integration | `pytest tests/integration/test_phase_8_e2e.py::test_quote_template_crud -x` | ❌ Wave 0 |
| BIZ-01 | Line item count 1-100 enforced | unit | `pytest tests/unit/test_quote_validation.py -x` | ❌ Wave 0 |
| BIZ-02 | Admin sends quote → FCM notification fires | integration | `pytest tests/integration/test_phase_8_e2e.py::test_send_quote_triggers_notification -x` | ❌ Wave 0 |
| BIZ-02 | Client views quote → read receipt recorded | integration | `pytest tests/integration/test_phase_8_e2e.py::test_quote_read_receipt -x` | ❌ Wave 0 |
| BIZ-02 | Client approves quote → job transitions to Scheduled | integration | `pytest tests/integration/test_phase_8_e2e.py::test_quote_approval_job_transition -x` | ❌ Wave 0 |
| BIZ-02 | Client declines quote with reason → admin can revise | integration | `pytest tests/integration/test_phase_8_e2e.py::test_quote_decline_and_revise -x` | ❌ Wave 0 |
| BIZ-02 | Expired quote blocks approval | unit | `pytest tests/unit/test_quote_validation.py::test_expired_quote_blocks_approval -x` | ❌ Wave 0 |
| BIZ-02 | Full quote flow E2E (Flutter) | E2E | `flutter test test/e2e/phase_8_business_ops_e2e_test.dart -t quote_flow` | ❌ Wave 0 |
| BIZ-03 | Generate invoice from completed job (one-tap) | integration | `pytest tests/integration/test_phase_8_e2e.py::test_generate_invoice_from_job -x` | ❌ Wave 0 |
| BIZ-03 | Invoice number sequential, unique per company | integration | `pytest tests/integration/test_phase_8_e2e.py::test_invoice_number_sequential -x` | ❌ Wave 0 |
| BIZ-03 | Invoice line items pre-populated from quote | integration | `pytest tests/integration/test_phase_8_e2e.py::test_invoice_prefilled_from_quote -x` | ❌ Wave 0 |
| BIZ-03 | Invoice generation transitions job to Invoiced | integration | `pytest tests/integration/test_phase_8_e2e.py::test_invoice_transitions_job_to_invoiced -x` | ❌ Wave 0 |
| BIZ-03 | PDF download endpoint returns valid PDF bytes | integration | `pytest tests/integration/test_phase_8_e2e.py::test_pdf_download -x` | ❌ Wave 0 |
| BIZ-04 | Dashboard jobs-by-status returns counts per status | integration | `pytest tests/integration/test_phase_8_e2e.py::test_dashboard_jobs_by_status -x` | ❌ Wave 0 |
| BIZ-04 | Revenue summary groups by month with paid/unpaid split | integration | `pytest tests/integration/test_phase_8_e2e.py::test_dashboard_revenue_by_month -x` | ❌ Wave 0 |
| BIZ-04 | Contractor utilization returns per-contractor hours | integration | `pytest tests/integration/test_phase_8_e2e.py::test_dashboard_contractor_utilization -x` | ❌ Wave 0 |
| BIZ-04 | Admin sees full dashboard; contractor sees limited view | integration | `pytest tests/integration/test_phase_8_e2e.py::test_dashboard_role_scoping -x` | ❌ Wave 0 |
| BIZ-04 | Dashboard date range filter applied correctly | integration | `pytest tests/integration/test_phase_8_e2e.py::test_dashboard_date_range_filter -x` | ❌ Wave 0 |
| ALL | Full quote-to-invoice E2E Flutter flow | E2E | `flutter test test/e2e/phase_8_business_ops_e2e_test.dart` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `cd backend && uv run python -m pytest tests/integration/test_phase_8_e2e.py -x -q`
- **Per wave merge:** `cd backend && uv run python -m pytest && cd ../mobile && flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `backend/tests/integration/test_phase_8_e2e.py` — covers BIZ-01 through BIZ-04
- [ ] `backend/tests/unit/test_quote_validation.py` — covers validation edge cases
- [ ] `mobile/test/e2e/phase_8_business_ops_e2e_test.dart` — covers full Flutter quote-to-invoice flow
- [ ] Add `quotes, quote_line_items, invoices, invoice_line_items, quote_templates` to TRUNCATE in `backend/tests/conftest.py`
- [ ] Backend install: `cd backend && uv add weasyprint`
- [ ] Flutter install: add `fl_chart: ^1.2.0` to `mobile/pubspec.yaml`

---

## Sources

### Primary (HIGH confidence)
- Codebase inspection — `backend/app/features/jobs/models.py` (TenantScopedModel pattern)
- Codebase inspection — `mobile/lib/core/database/app_database.dart` (schema v5, migration strategy)
- Codebase inspection — `mobile/lib/core/sync/handlers/note_sync_handler.dart` (SyncHandler pattern)
- Codebase inspection — `mobile/lib/shared/widgets/app_shell.dart` + `app_router.dart` (tab/branch pattern)
- Codebase inspection — `backend/tests/conftest.py` (clean_tables TRUNCATE pattern)
- Codebase inspection — `backend/app/features/sync/schemas.py` (SyncResponse extension pattern)
- [fl_chart 1.2.0 pub.dev](https://pub.dev/packages/fl_chart) — version, chart types, Flutter compatibility
- [WeasyPrint 68.1 PyPI](https://pypi.org/project/weasyprint/) — version (Feb 2026), Python 3.12 support

### Secondary (MEDIUM confidence)
- [FastAPI async + run_in_executor pattern](https://sentry.io/answers/fastapi-difference-between-run-in-executor-and-run-in-threadpool/) — WeasyPrint thread pool pattern
- [fl_chart changelog](https://pub.dev/packages/fl_chart/changelog) — 1.2.0 latest confirmed
- [WeasyPrint documentation](https://doc.courtbouillon.org/weasyprint/stable/common_use_cases.html) — invoice use case

### Tertiary (LOW confidence)
- WeasyPrint vs ReportLab comparison (community articles) — corroborated by official docs

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — fl_chart and WeasyPrint versions verified against pub.dev and PyPI; all other libraries are existing project dependencies
- Architecture: HIGH — patterns are direct extensions of existing Phase 6/7 code; no novel patterns required
- Pitfalls: HIGH — most are derived from established project decisions (StrEnum, lazy="raise", TRUNCATE pattern, run_in_executor for sync libs)
- Reporting queries: MEDIUM — SQLAlchemy 2.0 aggregate patterns are well-established; specific query structure will be refined during implementation

**Research date:** 2026-03-13
**Valid until:** 2026-04-13 (fl_chart and WeasyPrint are stable; 30-day validity)
