# Phase 25: Per-Trade Billing - Research

**Researched:** 2026-03-25
**Domain:** Billing extensions — quote/invoice trade-scoping, milestone progress billing, project-level aggregation
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Add optional `trade_scope_id` FK to existing `quotes` table — quotes can be either job-scoped (legacy) or trade-scope-scoped. New quotes default to trade-scope-scoped. Existing job-scoped quotes continue to work unchanged.
- **D-02:** Quote creation flow on mobile: GC navigates to a trade scope detail screen → taps "Create Quote" → line item editor pre-populated with the trade scope name. Same existing line item editor UI, just scoped to the trade.
- **D-03:** Trade-scoped quotes are independent — creating/editing one does not affect quotes for other trade scopes on the same project.
- **D-04:** Add optional `trade_scope_id` FK to existing `invoices` table — same dual-scope pattern as quotes.
- **D-05:** "Generate Invoice" button on trade scope detail screen when scope has completed tasks. Auto-populates line items from completed work items (task titles + hours logged as labor line items). GC can edit/add/remove line items before sending.
- **D-06:** Invoice inherits tax rate and discount settings from the quote if one exists for that trade scope, otherwise uses company defaults.
- **D-07:** Project-level quote summary is a read-only aggregation view — not a separate entity. Sums all trade-scope quotes into a single total with per-trade breakdown table. No editing at project level.
- **D-08:** Project-level invoice summary shows total billed, total paid, total outstanding across all trades. Same read-only aggregation pattern — a summary screen, not a new entity.
- **D-09:** Both aggregation views accessible from the project detail screen as new sections/tabs below existing content.
- **D-10:** New `billing_milestones` table — GC defines milestones per trade scope (e.g., "Rough-in complete: 40%", "Final trim: 60%"). Each milestone has a name, percentage, and optional description.
- **D-11:** Progress invoice is a regular invoice with a `milestone_id` FK linking it to the billing milestone. The invoice amount is calculated as milestone percentage × trade scope quote total.
- **D-12:** GC can create a progress invoice by selecting a milestone from the trade scope's milestone list. The milestone is marked as "invoiced" to prevent double-billing.

### Claude's Discretion
- Migration strategy for adding trade_scope_id to existing quotes/invoices tables (nullable FK, backfill approach)
- Project-level summary screen layout (single scrollable page vs tabs)
- Billing milestone CRUD UI pattern (inline editing vs modal form)
- Invoice number sequence handling for trade-scoped vs job-scoped invoices
- How completed work items map to invoice line items (grouping, description format)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BILL-01 | GC can create a quote per trade scope with line items | D-01/D-02: nullable trade_scope_id on quotes; QuoteService.create_quote extended with trade_scope_id param; TradeScopeDetailScreen gets "Create Quote" button |
| BILL-02 | Trade quotes aggregate to a project-level quote for client approval | D-07: read-only aggregation query over trade-scoped quotes grouped by project; no new entity needed |
| BILL-03 | GC can generate invoices per trade scope from completed work | D-04/D-05: nullable trade_scope_id on invoices; generate_from_trade_scope service method auto-populates line items from completed tasks |
| BILL-04 | Trade invoices aggregate to a project-level invoice | D-08: aggregation query (total billed/paid/outstanding) across all trade-scoped invoices for a project |
| BILL-05 | GC can do progress billing — invoice at milestones within a trade scope | D-10/D-11/D-12: billing_milestones table; progress invoice links milestone_id; milestone marked "invoiced" to prevent double-billing |
</phase_requirements>

## Summary

Phase 25 extends the existing billing infrastructure (quotes + invoices) to operate at the trade-scope level rather than the job level. The core work is: (1) adding nullable `trade_scope_id` FKs to both `quotes` and `invoices` tables while preserving backward compatibility with job-scoped records; (2) introducing a new `billing_milestones` table for progress billing; (3) extending QuoteService and InvoiceService with trade-scope-aware methods; (4) adding UI sections to TradeScopeDetailScreen and ProjectDetailScreen; and (5) extending the Drift schema from v12 to v13 with the same dual-write offline pattern.

The project has mature billing infrastructure: QuoteService with full lifecycle (draft→sent→viewed→approved), InvoiceService with sequential numbering (SELECT FOR UPDATE on company row), and InvoiceDao with transactional outbox dual-write. All these can be extended by adding an optional parameter rather than rewritten. The aggregation views (BILL-02, BILL-04) require no new tables — they are pure SQLAlchemy aggregate queries and Drift in-memory computations from existing data.

**Primary recommendation:** Extend existing services with trade_scope_id=None defaults so all existing job-scoped billing paths remain untouched. Add BillingMilestone as a new first-class model with its own service, repository, and DAO. Project-level aggregation is a new backend endpoint + a computed Flutter widget, not a new stored entity.

## Standard Stack

### Core (established — no new packages needed)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SQLAlchemy async | existing | ORM for new billing_milestones model | Same pattern as all other models in codebase |
| Alembic | existing | Migration 0023 for billing changes | Project standard, follows 0022_inspection_workflow pattern |
| Drift | v12 → v13 | Mobile schema bump for billing_milestones + FK columns | Established offline-first pattern |
| FastAPI | existing | New billing endpoints under /api/trade-scopes/{id}/billing | Project standard |
| Riverpod | existing | Providers for billing milestones, quote/invoice streams | All providers use AsyncNotifier or StreamProvider pattern |

### No New Packages Required

All required functionality is available in the current dependency set. The aggregation views are computed in-process from existing queries. PDF generation already exists in `backend/app/features/pdf/service.py`.

## Architecture Patterns

### Current Billing Infrastructure (What Exists)

**Backend:**
- `quotes` table: `job_id` (NOT NULL), `trade_scope_id` (to be added as nullable)
- `invoices` table: `job_id` (NOT NULL), `trade_scope_id` (to be added as nullable)
- `QuoteService`: inherits `TenantScopedService[Quote]`; methods: create_quote, update_quote, send_quote, approve_quote, decline_quote, revise_quote
- `InvoiceService`: inherits `TenantScopedService[Invoice]`; key method: `_generate_invoice_number` uses `SELECT FOR UPDATE` on company row + `companies.invoice_sequence`
- Quote status machine: `draft -> sent -> viewed -> approved | declined | expired | revised`
- Invoice status: `unpaid | partially_paid | paid`

**Mobile:**
- `InvoiceDao`: transactional outbox dual-write; `watchInvoicesForJob(String jobId)` — needs `watchInvoicesForScope(String scopeId)` added
- `InvoiceEntity`: computed totals (subtotal, discountAmount, taxAmount, total); `jobId` field — needs `tradeScopeId` nullable field
- `QuoteDao`: same dual-write pattern; needs `watchQuotesForScope(String scopeId)`
- Current Drift schema: **v12** (phase 24 added task_inspections, site_walk_flags, punch_list_items)
- Next migration: **v13** (this phase)

### Recommended Project Structure for New Code

```
backend/app/features/
├── quotes/
│   ├── models.py          # Add trade_scope_id nullable FK to Quote
│   └── service.py         # Add create_for_scope(), list_by_scope(), aggregate_by_project()
├── invoices/
│   ├── models.py          # Add trade_scope_id nullable FK to Invoice
│   └── service.py         # Add generate_from_scope(), generate_progress_invoice()
└── billing_milestones/    # NEW feature module
    ├── models.py           # BillingMilestone model
    ├── schemas.py          # Request/response schemas
    ├── repository.py       # BillingMilestoneRepository(TenantScopedRepository)
    ├── service.py          # BillingMilestoneService(TenantScopedService)
    └── router.py           # CRUD endpoints

backend/migrations/versions/
└── 0023_per_trade_billing.py   # ALTER quotes/invoices + CREATE billing_milestones

mobile/lib/
├── core/database/
│   ├── app_database.dart        # schemaVersion => 13; register BillingMilestones table
│   └── tables/
│       └── billing_milestones.dart   # NEW Drift table
├── features/
│   ├── quotes/data/
│   │   └── quote_dao.dart       # Add watchQuotesForScope(), watchProjectQuoteSummary()
│   ├── invoices/
│   │   ├── data/invoice_dao.dart    # Add watchInvoicesForScope(), watchProjectInvoiceSummary()
│   │   └── domain/invoice_entity.dart  # Add tradeScopeId nullable field
│   └── billing_milestones/     # NEW feature
│       ├── data/billing_milestone_dao.dart
│       ├── domain/billing_milestone_entity.dart
│       └── presentation/
│           └── providers/billing_milestone_providers.dart
├── features/projects/presentation/
│   └── screens/
│       ├── trade_scope_detail_screen.dart   # Add billing sections
│       └── project_detail_screen.dart       # Add aggregation sections
```

### Pattern 1: Nullable FK Extension (D-01, D-04)

**What:** Add `trade_scope_id UUID NULLABLE` to `quotes` and `invoices` with `ON DELETE SET NULL`.
**When to use:** Backwards-compatible extension of existing tables. Legacy rows keep `job_id` non-null and `trade_scope_id` null. New trade-scoped rows set both FKs (job can be inferred via trade_scope → project linkage, or left null for fully trade-scoped workflows).

**Migration pattern:**
```python
# Source: established Alembic pattern in this codebase (0022_inspection_workflow.py)
op.add_column(
    "quotes",
    sa.Column("trade_scope_id", sa.UUID(), nullable=True),
)
op.create_foreign_key(
    "fk_quotes_trade_scope_id",
    "quotes", "trade_scopes",
    ["trade_scope_id"], ["id"],
    ondelete="SET NULL",
)
op.create_index("ix_quotes_trade_scope_id", "quotes", ["trade_scope_id"])
# Same pattern for invoices
```

**IMPORTANT — `job_id` constraint:** Current `quotes.job_id` and `invoices.job_id` are NOT NULL. For fully trade-scoped quotes/invoices that have no associated job, the migration must either:
- Make `job_id` nullable (simpler, recommended) — add a migration step, update CHECK constraints
- Or keep `job_id` NOT NULL and require a placeholder/sentinel job_id value (NOT recommended — pollutes data)

**Recommendation:** Make `job_id` nullable in the same migration for both quotes and invoices. Trade-scoped records set `trade_scope_id`; job-scoped records keep `job_id`. Mutual exclusion enforced at application layer, not DB constraint.

### Pattern 2: BillingMilestone Model (D-10, D-11, D-12)

**What:** New table `billing_milestones` with `trade_scope_id`, `name`, `percentage`, `description`, `is_invoiced`. Follow TenantScopedModel pattern exactly.

```python
# Source: established model pattern (backend/app/features/projects/models.py)
class BillingMilestone(TenantScopedModel):
    __tablename__ = "billing_milestones"

    trade_scope_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trade_scopes.id", ondelete="CASCADE"),
        nullable=False,
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    percentage: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_invoiced: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    __table_args__ = (
        CheckConstraint("percentage > 0 AND percentage <= 100", name="billing_milestones_pct_check"),
    )

    trade_scope: Mapped[TradeScope] = relationship("TradeScope", lazy="raise")
```

### Pattern 3: Project-Level Aggregation (D-07, D-08)

**What:** Backend returns an aggregate response from a single query. Mobile computes aggregation client-side from Drift streams.

**Backend approach (no new table):**
```python
# Source: SQLAlchemy aggregation pattern
from sqlalchemy import func, select

async def get_project_quote_summary(self, project_id: uuid.UUID) -> dict:
    result = await self.db.execute(
        select(
            TradeScope.id,
            TradeScope.trade_name,
            func.count(Quote.id).label("quote_count"),
            func.sum(QuoteLineItem.quantity * QuoteLineItem.unit_price).label("scope_subtotal"),
        )
        .select_from(TradeScope)
        .outerjoin(Quote, Quote.trade_scope_id == TradeScope.id)
        .outerjoin(QuoteLineItem, QuoteLineItem.quote_id == Quote.id)
        .where(
            TradeScope.project_id == project_id,
            TradeScope.deleted_at.is_(None),
        )
        .group_by(TradeScope.id, TradeScope.trade_name)
    )
    ...
```

**Mobile approach:** Combine two Drift streams with `StreamZip` or `Rx.combineLatest`:
```dart
// watchProjectQuoteSummary — derived from watchQuotesForScope() per scope
// Compute in-memory: sum line item totals per scope, aggregate to project total
// Use Provider.family(projectId) that combines all scope quote streams
```

### Pattern 4: Trade-Scope Invoice Generation from Completed Work (D-05)

**What:** Query tasks with `status='complete'` for the scope, convert to labor line items.

**Line item mapping rules:**
- Each completed task → one line item
- `description`: task.title
- `item_type`: 'labor'
- `quantity`: task.estimated_hours (default 1.0 if null)
- `unit`: 'hr'
- `unit_price`: 0.00 (GC fills in, or derives from quote if one exists)
- `sort_order`: task's sort_order

**Backend method:**
```python
async def generate_from_scope(
    self,
    trade_scope_id: uuid.UUID,
    user_id: uuid.UUID,
    milestone_id: uuid.UUID | None = None,  # for progress billing
) -> Invoice:
    # 1. Load trade scope + project
    # 2. Query completed tasks for scope (selectinload not needed — just title/hours)
    # 3. If milestone_id: mark milestone is_invoiced=True; amount = pct * quote_total
    # 4. Inherit tax/discount from approved quote for scope (if exists), else company defaults
    # 5. Generate invoice_number via _generate_invoice_number (same SELECT FOR UPDATE)
    # 6. Create Invoice with trade_scope_id set, job_id=None
    # 7. Create InvoiceLineItems from completed tasks
```

### Pattern 5: Drift Schema v13 (Mobile)

**What:** Bump `schemaVersion` from 12 to 13. Add new table and new columns.

```dart
// In app_database.dart onUpgrade:
if (from < 13) {
  // Phase 25: Per-trade billing data layer
  await m.createTable(billingMilestones);
  await _addColumnIfMissing(m, 'quotes', 'trade_scope_id',
      quotes, quotes.tradeScopeId);
  await _addColumnIfMissing(m, 'invoices', 'trade_scope_id',
      invoices, invoices.tradeScopeId);
}
```

**Drift table definition:**
```dart
class BillingMilestones extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get tradeScopeId => text()();  // soft FK to trade_scopes
  TextColumn get name => text()();
  RealColumn get percentage => real()();
  TextColumn get description => text().nullable()();
  BoolColumn get isInvoiced => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

**NOTE:** `tradeScopeId` in Drift uses soft FK (no `.references()` call) — consistent with Phase 20 TaskDependencyDao pattern and Phase 22 TaskNote.author_id pattern that avoids hard FK coupling between feature modules.

### Anti-Patterns to Avoid

- **Do NOT make `job_id` required on trade-scoped quotes/invoices.** Legacy code paths that query `WHERE job_id = ?` will still work on old records. New trade-scope creation sets `job_id=NULL`.
- **Do NOT aggregate at mobile in real-time with N+1 queries.** Use `asyncMap` on a combined stream of all scope quotes, not per-scope provider fan-out in the UI layer.
- **Do NOT write to sync_queue in `upsertFromSync`.** The existing InvoiceDao.upsertFromSync pattern is correct — never enqueue during sync pull.
- **Do NOT use `pumpAndSettle()` in Flutter tests for Drift stream widgets.** Use `pump()` — established project rule from MEMORY.md.
- **Do NOT call `db.commit()` in service methods.** `get_db` handles transaction lifecycle — project CLAUDE.md rule.
- **Do NOT use `async void` with plain `Interceptor`.** Use `QueuedInterceptor` for async operations — project rule.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Sequential invoice numbers | Custom UUID or timestamp-based IDs | Existing `_generate_invoice_number` with `SELECT FOR UPDATE` | Race condition under concurrent requests; already solved with row-level lock |
| Quote total computation | Re-implement subtotal/discount/tax math | Existing `InvoiceEntity` / `QuoteEntity` computed properties | Already tested and correct; reuse for milestone amount calculation |
| Trade-to-project aggregation entity | New `ProjectQuoteSummary` table | In-memory SQLAlchemy aggregate query + mobile Stream composition | No persistence needed; always derived from current quote/invoice state |
| Offline sync for billing milestones | Custom sync mechanism | Existing outbox dual-write pattern (sync_queue table) | `SyncQueueCompanion` + `insertOnConflictUpdate` is the established pattern |
| Double-billing prevention | Application-level flag checks | `is_invoiced` boolean on `billing_milestones` + DB unique constraint | Simple flag with CHECK is sufficient; no distributed lock needed |

## Common Pitfalls

### Pitfall 1: job_id NOT NULL Constraint Violation
**What goes wrong:** Creating a trade-scoped quote/invoice without providing `job_id` fails at the DB level because current column is NOT NULL.
**Why it happens:** Legacy schema requires `job_id` on both tables.
**How to avoid:** Migration 0023 must make `job_id` nullable on both tables before any trade-scoped records are inserted. Add migration step: `op.alter_column("quotes", "job_id", nullable=True)`.
**Warning signs:** `IntegrityError: NOT NULL constraint failed` on quote/invoice creation.

### Pitfall 2: QuoteService.create_quote Has No trade_scope_id Parameter
**What goes wrong:** Calling existing `create_quote` without modification silently creates a job-scoped quote even when a `trade_scope_id` is passed in the body.
**Why it happens:** Service methods were written for job-scope only.
**How to avoid:** Add `trade_scope_id: uuid.UUID | None = None` to `QuoteCreate` schema and service method. Pass through to model constructor. Validate that exactly one of `job_id` or `trade_scope_id` is provided.
**Warning signs:** Quotes appear in job list, not scope list; filtering by scope returns empty.

### Pitfall 3: Drift Schema Drift Between Table Definition and Migration
**What goes wrong:** Drift `schemaVersion` bumped to 13 but `onUpgrade` block doesn't add new columns, causing `NoSuchColumnException` at runtime.
**Why it happens:** Drift table definition and migration block must be kept in sync.
**How to avoid:** Always add `_addColumnIfMissing` in the `from < 13` block for every new column added to existing tables. Verify with `dart run drift_dev schema generate` before committing.
**Warning signs:** `NoSuchColumnException` or `SchemaVersionMismatch` on app start.

### Pitfall 4: Aggregation N+1 on Mobile
**What goes wrong:** Project-level summary renders slowly because it opens one Drift query per trade scope.
**Why it happens:** Reactive UI that watches `tradeScopesProvider(projectId)` then fans out to per-scope invoice providers.
**How to avoid:** Implement `watchProjectInvoiceSummary(String projectId)` as a single Drift query using `JoinedSelectStatement` across scopes + invoices, or use `asyncMap` on the combined scopes stream.
**Warning signs:** Noticeable frame drop on projects with 5+ trade scopes.

### Pitfall 5: Milestone Double-Billing Race Condition
**What goes wrong:** GC taps "Invoice" on milestone twice before the first request completes, generating two invoices for the same milestone.
**Why it happens:** `is_invoiced` flag is checked then set in two separate DB operations without a lock.
**How to avoid:** Use `UPDATE billing_milestones SET is_invoiced=TRUE WHERE id=? AND is_invoiced=FALSE RETURNING id` — atomic check-and-set. If 0 rows returned, raise 409 Conflict. In Flutter, disable the "Generate Invoice" button immediately on tap (optimistic UI lock).
**Warning signs:** Duplicate invoices with the same `milestone_id` in the invoices table.

### Pitfall 6: SQLAlchemy lazy="raise" on New Relationships
**What goes wrong:** Adding `trade_scope` relationship to `Quote` model without `selectinload` in every query that needs it causes `MissingGreenlet` / `lazy="raise"` errors.
**Why it happens:** All relationships in this codebase use `lazy="raise"` per CLAUDE.md.
**How to avoid:** Whenever a query on quotes/invoices needs the trade scope name (e.g., for PDF, for aggregation), use `.options(joinedload(Quote.trade_scope))`. Document this in every method that accesses `quote.trade_scope`.
**Warning signs:** `sqlalchemy.exc.InvalidRequestError: 'Trade scope' is not available due to lazy='raise'`.

## Code Examples

### Quote Schema Extension (Backend)
```python
# Source: established pattern from backend/app/features/quotes/schemas.py
from pydantic import model_validator

class QuoteCreate(BaseModel):
    job_id: uuid.UUID | None = None
    trade_scope_id: uuid.UUID | None = None
    tax_rate: Decimal = Decimal("0")
    # ... other fields

    @model_validator(mode="after")
    def validate_scope(self) -> "QuoteCreate":
        if self.job_id is None and self.trade_scope_id is None:
            raise ValueError("Either job_id or trade_scope_id must be provided")
        return self
```

### BillingMilestoneDao (Mobile — Drift pattern)
```dart
// Source: established Drift DAO pattern from invoice_dao.dart
@DriftAccessor(tables: [BillingMilestones, SyncQueue])
class BillingMilestoneDao extends DatabaseAccessor<AppDatabase>
    with _$BillingMilestoneDaoMixin {
  BillingMilestoneDao(super.db);

  Stream<List<BillingMilestone>> watchByScope(String scopeId) {
    return (select(billingMilestones)
          ..where((tbl) =>
              tbl.tradeScopeId.equals(scopeId) & tbl.deletedAt.isNull())
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.sortOrder)]))
        .watch();
  }

  Future<String> createMilestone(BillingMilestoneEntity entity) async {
    await db.transaction(() async {
      await into(billingMilestones).insert(/* companion */);
      await into(syncQueue).insert(
        _buildQueueEntry(entityType: 'billing_milestone', /* ... */),
      );
    });
    return entity.id;
  }
}
```

### Progress Invoice Amount Calculation
```python
# Source: D-11 — milestone_percentage × quote_total
async def _get_scope_quote_total(self, trade_scope_id: uuid.UUID) -> Decimal:
    """Sum line items of the approved quote for the given scope."""
    result = await self.db.execute(
        select(func.sum(QuoteLineItem.quantity * QuoteLineItem.unit_price))
        .select_from(Quote)
        .join(QuoteLineItem, QuoteLineItem.quote_id == Quote.id)
        .where(
            Quote.trade_scope_id == trade_scope_id,
            Quote.status == "approved",
            Quote.deleted_at.is_(None),
        )
    )
    return result.scalar() or Decimal("0")

async def generate_progress_invoice(
    self, trade_scope_id: uuid.UUID, milestone_id: uuid.UUID, user_id: uuid.UUID
) -> Invoice:
    milestone = await self.db.get(BillingMilestone, milestone_id)
    if milestone is None or milestone.is_invoiced:
        raise HTTPException(status_code=409, detail="Milestone already invoiced or not found")

    quote_total = await self._get_scope_quote_total(trade_scope_id)
    amount = quote_total * milestone.percentage / 100

    # Atomic: mark invoiced only if currently False
    rows_updated = await self.db.execute(
        update(BillingMilestone)
        .where(BillingMilestone.id == milestone_id, BillingMilestone.is_invoiced.is_(False))
        .values(is_invoiced=True)
        .returning(BillingMilestone.id)
    )
    if not rows_updated.fetchone():
        raise HTTPException(status_code=409, detail="Milestone already invoiced (concurrent request)")

    # Create invoice with single line item for milestone amount
    invoice_number = await self._generate_invoice_number(self._require_tenant_id())
    invoice = Invoice(
        company_id=self._require_tenant_id(),
        trade_scope_id=trade_scope_id,
        milestone_id=milestone_id,
        invoice_number=invoice_number,
        status="unpaid",
        issued_at=datetime.now(UTC),
        # inherit tax/discount from scope's approved quote or company defaults
    )
    ...
```

### Flutter: TradeScopeDetailScreen Billing Section
```dart
// Source: established ConsumerWidget pattern (trade_scope_detail_screen.dart)
// Add to the ListView children in TradeScopeDetailScreen.build():

// Billing section header
if (isGcOrAdmin) ...[
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text('Billing', style: textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    )),
  ),
  _BillingActionsCard(scopeId: scopeId, projectId: projectId),
],
```

### Backend: New Router Endpoints for Trade-Scoped Billing
```python
# Recommended endpoint structure under trade scopes router:
# POST   /api/trade-scopes/{scope_id}/quotes          — create trade-scoped quote
# GET    /api/trade-scopes/{scope_id}/quotes          — list quotes for scope
# GET    /api/projects/{project_id}/quote-summary     — aggregated project quote view
# POST   /api/trade-scopes/{scope_id}/invoices/generate — generate from completed tasks
# POST   /api/trade-scopes/{scope_id}/invoices/progress  — generate progress invoice
# GET    /api/trade-scopes/{scope_id}/milestones      — list milestones
# POST   /api/trade-scopes/{scope_id}/milestones      — create milestone
# PUT    /api/trade-scopes/{scope_id}/milestones/{id} — update milestone
# DELETE /api/trade-scopes/{scope_id}/milestones/{id} — delete milestone
# GET    /api/projects/{project_id}/invoice-summary   — aggregated invoice view
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Job-scoped billing (invoices.job_id NOT NULL) | Dual-scope: trade_scope_id nullable FK alongside job_id | Phase 25 | Trade scopes get independent billing; legacy job flows unchanged |
| No milestone concept | billing_milestones table with percentage + is_invoiced | Phase 25 | Progress billing without custom amount math per invoice |
| No project-level billing view | Read-only aggregation endpoint + computed Flutter widget | Phase 25 | GC sees cross-trade financial picture in one place |

**Deprecated/outdated for this phase:**
- `InvoiceService.generate_from_quote(job_id)` — still valid for legacy job-scoped invoices. New trade-scope path uses `generate_from_scope(trade_scope_id)`. Both co-exist.
- `QuoteService.create_quote(job_id required)` — `job_id` becomes optional; validator ensures one of `job_id` or `trade_scope_id` is present.

## Open Questions

1. **Should `job_id` be fully optional on new trade-scoped quotes/invoices, or always required?**
   - What we know: Current DB schema has `job_id NOT NULL` on both tables. D-01/D-04 add nullable `trade_scope_id`. The CONTEXT.md is silent on whether `job_id` must remain non-null for trade-scoped records.
   - What's unclear: If `job_id` stays NOT NULL for trade-scoped records, what value is used? Null sentinel? Project's implicit "billing job"?
   - Recommendation: Make `job_id` nullable in migration 0023. Set `job_id=NULL` on trade-scoped quotes/invoices. Application code validates that at least one is set. This is the simplest backwards-compatible approach.

2. **Invoice number sequence: shared or per-scope?**
   - What we know: D-discretion item. Current `_generate_invoice_number` uses `companies.invoice_sequence` — sequential across all invoices company-wide (e.g., "INV-0001", "INV-0002").
   - What's unclear: Whether GCs want trade-scoped numbers (e.g., "INV-PLUMB-0001") or a global company sequence.
   - Recommendation: Keep the single company-wide sequence. The `invoice_number` format stays "INV-XXXX". Trade scope context is conveyed by the invoice content, not the number. Adding per-scope sequences would require new columns on `trade_scopes` and significant extra complexity.

3. **Milestone percentage validation: sum-to-100 constraint?**
   - What we know: D-10 says milestones have a `percentage` field. No mention of enforcing that milestone percentages sum to 100%.
   - What's unclear: Whether GCs expect enforcement (e.g., can't add milestone if cumulative > 100%).
   - Recommendation: No DB-level sum constraint — check constraint only validates 0 < percentage <= 100 per row. Service layer can provide a warning but not block. GCs may legitimately have overlapping milestones or choose not to cover 100%.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework (backend) | pytest + ASGI client (established) |
| Framework (mobile) | flutter test + mocktail + Drift in-memory |
| Config file | backend/pytest.ini + mobile/test/ |
| Quick run command | `cd backend && uv run python -m pytest tests/test_billing_milestones.py -x` |
| Full suite command | `cd backend && uv run python -m pytest` + `cd mobile && flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BILL-01 | GC creates trade-scoped quote with line items | integration | `pytest tests/test_phase_25_e2e.py::test_create_trade_scope_quote -x` | ❌ Wave 0 |
| BILL-02 | Project-level quote summary aggregates trade quotes | integration | `pytest tests/test_phase_25_e2e.py::test_project_quote_summary -x` | ❌ Wave 0 |
| BILL-03 | Invoice generated from completed scope tasks | integration | `pytest tests/test_phase_25_e2e.py::test_generate_scope_invoice -x` | ❌ Wave 0 |
| BILL-04 | Project-level invoice summary (billed/paid/outstanding) | integration | `pytest tests/test_phase_25_e2e.py::test_project_invoice_summary -x` | ❌ Wave 0 |
| BILL-05 | Progress invoice created from milestone (no double-billing) | integration | `pytest tests/test_phase_25_e2e.py::test_progress_billing_milestone -x` | ❌ Wave 0 |
| BILL-05 | Duplicate milestone invoice blocked | unit | `pytest tests/test_billing_milestones.py::test_double_billing_prevented -x` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** Quick run on the new test file for that task
- **Per wave merge:** Full pytest + flutter test suite
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `backend/tests/test_phase_25_e2e.py` — covers BILL-01 through BILL-05 end-to-end
- [ ] `backend/tests/test_billing_milestones.py` — unit tests for BillingMilestoneService (create, update, delete, double-billing prevention)
- [ ] `mobile/test/e2e/phase_25_per_trade_billing_e2e_test.dart` — Flutter E2E covering TradeScopeDetailScreen billing sections, milestone CRUD, progress invoice flow
- [ ] `mobile/test/features/billing_milestones/billing_milestone_dao_test.dart` — Drift in-memory DAO tests for watchByScope, createMilestone, markInvoiced

## Sources

### Primary (HIGH confidence)
- Direct code inspection: `backend/app/features/invoices/models.py` — confirmed `job_id NOT NULL`, no `trade_scope_id` exists
- Direct code inspection: `backend/app/features/invoices/service.py` — confirmed `_generate_invoice_number` with `SELECT FOR UPDATE`; method signatures
- Direct code inspection: `backend/app/features/quotes/models.py` — confirmed `job_id NOT NULL`, Quote status machine
- Direct code inspection: `mobile/lib/core/database/app_database.dart` — confirmed `schemaVersion => 12`, migration structure, existing table registrations
- Direct code inspection: `mobile/lib/core/database/tables/invoices.dart` + `quotes.dart` — confirmed current column layout
- Direct code inspection: `mobile/lib/features/invoices/data/invoice_dao.dart` — confirmed outbox dual-write pattern, `watchInvoicesForJob` signature
- Direct code inspection: `mobile/lib/features/projects/presentation/screens/trade_scope_detail_screen.dart` — confirmed current screen structure (tasks + punch list)
- Direct code inspection: `backend/migrations/versions/0022_inspection_workflow.py` — confirmed latest migration is 0022; next is 0023
- Direct code inspection: `.planning/config.json` — `nyquist_validation: true`

### Secondary (MEDIUM confidence)
- `.planning/STATE.md` accumulated decisions — established patterns for Drift DAOs, soft FKs, Riverpod providers, sync queue
- CLAUDE.md — mandatory OOP inheritance chain, lazy="raise", no db.commit(), QueuedInterceptor rules

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries are existing project dependencies; no new packages needed
- Architecture: HIGH — patterns derived from direct code inspection of existing invoice/quote/milestone infrastructure
- Pitfalls: HIGH — based on actual model constraints found in code (job_id NOT NULL); and known project patterns (lazy="raise", pumpAndSettle)
- Migration path: HIGH — confirmed latest migration is 0022, Drift schema is v12; next is 0023 / v13

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (stable domain — no fast-moving dependencies)
