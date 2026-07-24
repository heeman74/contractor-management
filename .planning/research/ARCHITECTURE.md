# Architecture Research

**Domain:** Financial intelligence integration into an existing multi-trade construction management platform (FastAPI + PostgreSQL RLS backend, Next.js web, Flutter mobile)
**Researched:** 2026-07-24
**Confidence:** HIGH — grounded in direct reading of the existing codebase (models, services, routers, migrations, scheduler, RBAC catalog), not external ecosystem research.

*(Supersedes the previous ARCHITECTURE.md, which covered v3.0 AI/chat/dependency-engine research — that milestone has since shipped through Phase 26.)*

## Standard Architecture

### System Overview

```
┌───────────────────────────────────────────────────────────────────────────┐
│                        Existing Revenue Side (unchanged)                    │
│  Quote (job_id | trade_scope_id) ──► Invoice (job_id|trade_scope_id|        │
│  QuoteLineItem (labor/material)       milestone_id|quote_id, amount_paid)   │
│  BillingMilestone (trade_scope_id)                                         │
├───────────────────────────────────────────────────────────────────────────┤
│                    NEW Cost Side (v4.0 — this milestone)                    │
│  ┌────────────┐   ┌──────────────┐   ┌────────────┐   ┌────────────────┐   │
│  │ CostEntry  │   │ LaborRate    │   │ Budget     │   │ TimeEntry (ext) │   │
│  │ material/  │   │ user_id +    │   │ job_id |   │   │ + trade_scope_  │   │
│  │ subcontr.  │   │ effective_   │   │ trade_     │   │   id / task_id  │   │
│  │ job_id |   │   │ hourly_rate  │   │ scope_id + │   │ (nullable, XOR  │   │
│  │ trade_     │   │              │   │ amount     │   │  with job_id)   │   │
│  │ scope_id   │   │              │   │            │   │                 │   │
│  └─────┬──────┘   └──────┬───────┘   └─────┬──────┘   └────────┬────────┘   │
│        └─────────────────┴─────────────────┴───────────────────┘           │
│                                  │                                          │
│                     FinanceService (aggregation, on-the-fly)               │
│                  revenue (quotes/invoices) − costs (CostEntry +            │
│                  TimeEntry×LaborRate) = margin, vs Budget = overrun risk   │
├───────────────────────────────────────────────────────────────────────────┤
│  finance.* permission gate (require_permission, owner+PM default)          │
├───────────────────────────────────────────────────────────────────────────┤
│  AI Profitability Analyzer          │  AI Quote Estimator                  │
│  (APScheduler cron, reuses          │  (on-demand Claude tool-use call,    │
│   DashboardAlert + AIService        │   reuses AIService pattern, prices   │
│   Claude tool-use pattern)          │   from historical QuoteLineItem +    │
│                                      │   LaborRate)                         │
├───────────────────────────────────────────────────────────────────────────┤
│  Web: features/finance/ + (dashboard)/projects/[id] "Financials" tab,     │
│  cost-entry forms, budget setup, margin charts — TanStack Query via       │
│  /api/proxy, gated by finance.* on both nav and data                      │
└───────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|-------------------------|
| `CostEntry` (new model) | Record a single actual-cost transaction (material purchase or subcontractor invoice) against a job or trade scope | `TenantScopedModel`, polymorphic `job_id`/`trade_scope_id` (nullable pair, XOR via Pydantic `model_validator`, mirroring `Quote`/`Invoice`) |
| `LaborRate` (new model) | Effective-dated hourly cost rate per user, used to derive labor cost from time worked | `TenantScopedModel`, `user_id` FK + `hourly_rate` Numeric + `effective_from` date |
| `Budget` (new model) | Target spend ceiling for a project or trade scope | `TenantScopedModel`, polymorphic `project_id`/`trade_scope_id`, `amount`, `category` (optional: labor/material/subcontractor/total) |
| `TimeEntry` (extend existing) | Source of actual labor hours | Add nullable `trade_scope_id`, `task_id`; relax `job_id` to nullable; XOR validator (job vs trade scope) so project-hierarchy work can be clocked |
| `FinanceService` (new, non-CRUD analytical service) | Compute revenue, actual cost, margin, budget-vs-actual for a job/project/trade scope | Plain class like `ReportingService` — not entity CRUD, so it does **not** need `BaseService`/`repository_class`; takes `AsyncSession`, runs aggregate SQL across `Quote`/`Invoice`/`CostEntry`/`TimeEntry`/`LaborRate` |
| `DashboardAlert` (extend existing, don't duplicate) | Surface AI-generated profitability/margin-erosion/budget-overrun alerts | Add new `alert_type` values (`margin_erosion`, `budget_overrun_risk`) to the existing table already keyed by `project_id`/`trade_scope_id` with `severity`/`impact_text`/`remediation_text` |
| Financial analysis cron job (new) | Nightly per-company profitability scan → Claude call → persist `DashboardAlert` rows | New function in `app/core/scheduler.py`, reuses `_run_for_all_companies` helper exactly like `run_morning_checklists`/`run_alert_detection` |
| AI quote estimator (new method on AI-adjacent service) | Single-shot structured generation of labor+material line items priced from company history | Reuses Claude tool-use plumbing from `app/features/ai/service.py` (`AIService`) but as a synchronous, non-conversational call — closer to checklist generation than to the intake interview |
| `finance.*` permission keys (extend `app/core/permissions.py`) | Gate all financial reads/writes | New catalog entries in a "Finance" group; excluded from `admin`'s auto-derived set; explicitly granted to `owner` (already wildcard) and `project_manager` |
| Web `features/finance/` (new) | Cost entry forms, budget setup, margin dashboard, AI insight panel | Matches existing `web/src/features/{tasks,chat,ai,media}` convention; new routes under `(dashboard)/projects/[id]` (Financials tab) and a top-level `(dashboard)/finance` or `(dashboard)/reports` extension |

## Recommended Project Structure

```
backend/app/features/finance/          # NEW feature module — mirrors billing_milestones/ shape
├── __init__.py
├── models.py            # CostEntry, LaborRate, Budget
├── schemas.py           # Create/Update/Response schemas + XOR model_validators
├── repository.py        # CostEntryRepository, LaborRateRepository, BudgetRepository
│                         #   (each: TenantScopedRepository subclass, plain CRUD)
├── service.py            # CostEntryService, LaborRateService, BudgetService (CRUD)
│                         # + FinanceService (aggregation/read-only — NOT entity CRUD)
├── router.py             # /finance/costs, /finance/labor-rates, /finance/budgets,
│                         # /finance/projects/{id}/margin, /finance/jobs/{id}/margin
└── ai_quotes.py           # QuoteEstimatorService — on-demand Claude tool-use call
                          # (kept out of router.py per "small functions" — separate concern)

backend/app/features/jobs/
└── models.py             # TimeEntry EXTENDED (not new file) — nullable trade_scope_id,
                          # task_id columns added; job_id relaxed to nullable

backend/app/features/dashboard/
└── models.py / service.py  # DashboardAlert EXTENDED — new alert_type values, no new table

backend/migrations/versions/
└── 0030_financial_intelligence.py   # cost_entries, labor_rates, budgets tables,
                                      # time_entries ALTER, finance.* permission seed

web/src/features/finance/            # NEW — mirrors features/{tasks,ai,media}
├── components/          # MarginSummaryCard, CostEntryForm, BudgetForm, FinanceAlertPanel
└── hooks/                # useProjectMargin, useCostEntries, useBudgets (TanStack Query)

web/src/app/(dashboard)/projects/[id]/financials/   # NEW route — permission-gated tab
web/src/app/(dashboard)/reports/                    # EXTENDED — company-wide margin report
```

### Structure Rationale

- **One `finance/` backend module, not scattered additions** — CostEntry/LaborRate/Budget are new concerns with their own lifecycle and permission surface; bundling them mirrors how `billing_milestones/` was split out from `quotes/`/`invoices/` in v3.0 rather than bolted onto those modules.
- **`FinanceService` lives in the same file as the CRUD services but is architecturally distinct** — it has no `repository_class`/entity to own; it's a read/aggregation service like `ReportingService` (`app/features/reports/service.py`), which is the existing precedent for "plain class, not `BaseService[T]`" when the job is cross-table analytics rather than owning one entity.
- **`TimeEntry` is extended in place, not duplicated** — creating a parallel `ProjectTimeEntry` table would fork the labor-tracking source of truth and double the mobile clock-in UI surface. Extending the existing table (nullable `job_id`, new nullable `trade_scope_id`/`task_id`, XOR validator) is consistent with how `Quote`/`Invoice` already solved the identical "job vs trade scope" duality.
- **`DashboardAlert` is reused, not forked** — it is already a generic (`project_id`, `trade_scope_id`, `severity`, `alert_type`, `impact_text`, `remediation_text`) alert envelope built for exactly this "AI flags a problem, GC/PM sees it in a feed" shape. A new `FinancialAlert` table would duplicate that envelope for no benefit and would require a second alerts-feed UI component.

## Architectural Patterns

### Pattern 1: Polymorphic job-or-trade-scope attachment (XOR via Pydantic validator, not DB constraint)

**What:** Every v4.0 financial table that needs to attach to "the billable unit" uses the exact pattern already established by `Quote`/`Invoice`: two nullable FK columns (`job_id`, `trade_scope_id`), enforced mutually-exclusive-and-at-least-one by a `@model_validator(mode="after")` in the Pydantic create schema — not a DB `CHECK` constraint (the codebase does not use DB-level XOR checks for this; it validates at the schema layer, confirmed in `app/features/quotes/schemas.py`).

**When to use:** `CostEntry` and `Budget` both need this. `LaborRate` does not (it's purely `user_id`-scoped, no billable-unit attachment).

**Why this matters here:** Jobs (v1.0, single-trade, standalone) and Projects→TradeScopes (v3.0, multi-trade hierarchy) are **parallel, non-overlapping systems** — a `Job` has no `project_id` and a `TradeScope` has no direct job link (confirmed by grepping both models). Revenue already flows through both paths independently (`Quote.job_id` XOR `Quote.trade_scope_id`, `Invoice.job_id` XOR `Invoice.trade_scope_id`). Costs and budgets must follow the identical fork or margin computation will have two incompatible cost-attachment models to reconcile.

**Trade-offs:** Two nullable columns instead of a single polymorphic `(entity_type, entity_id)` pair is slightly more verbose per table, but it's what three existing tables (`Quote`, `Invoice`, and now these) already do — consistency with the established convention outweighs the marginal DRY loss.

**Example (schema layer, mirroring `quotes/schemas.py`):**
```python
class CostEntryCreate(BaseModel):
    job_id: uuid.UUID | None = None
    trade_scope_id: uuid.UUID | None = None
    cost_type: str  # 'material' | 'subcontractor' | 'other'
    amount: Decimal
    ...

    @model_validator(mode="after")
    def validate_attachment(self) -> "CostEntryCreate":
        if self.job_id is None and self.trade_scope_id is None:
            raise ValueError("Either job_id or trade_scope_id must be provided")
        if self.job_id is not None and self.trade_scope_id is not None:
            raise ValueError("Provide only one of job_id or trade_scope_id")
        return self
```

### Pattern 2: Effective-dated labor rate, not a single mutable column

**What:** `LaborRate` is a small append-mostly table (`user_id`, `hourly_rate`, `effective_from`) rather than a `hourly_rate` column on `User`. Labor cost for a given `TimeEntry` is computed by looking up the rate whose `effective_from` is the latest one `<=` the entry's `clocked_in_at` date.

**When to use:** Any time labor cost needs to be derived after the fact for historical time entries.

**Trade-offs:** A single `User.hourly_rate` column is simpler to build and query, but it silently corrupts historical margin data the first time a company gives a worker a raise — every past job's computed labor cost would retroactively change on next read (see Anti-Pattern 2). An effective-dated table costs one extra join and a `get_rate_as_of(user_id, date)` helper, but keeps historical margin figures stable. Given this is explicitly a "profit visibility" feature, correctness of historical numbers matters more than the marginal complexity — recommended as the default. If the team wants to ship the simplest possible v1 cut and accept that historical margins can drift on rate changes, a plain `User.default_hourly_rate` column is the fallback, but should be treated as a known, explicit simplification rather than silently assumed equivalent.

**Example:**
```python
class LaborRate(TenantScopedModel):
    __tablename__ = "labor_rates"
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    hourly_rate: Mapped[Decimal] = mapped_column(Numeric(8, 2), nullable=False)
    effective_from: Mapped[date] = mapped_column(Date, nullable=False, server_default="CURRENT_DATE")
```

### Pattern 3: On-the-fly margin aggregation (no materialized/snapshot table)

**What:** `FinanceService.get_project_margin(project_id)` / `get_job_margin(job_id)` run live SQL: `SUM(Invoice line-item or Quote total)` for revenue, `SUM(CostEntry.amount)` + `SUM(TimeEntry.duration_seconds/3600 × LaborRate.hourly_rate)` for cost, computed on every request — no `project_financial_snapshots` table, no triggers, no dual-write.

**When to use:** All margin/budget-vs-actual reads, both the web dashboard and the AI analyzer's nightly scan.

**Trade-offs:** This matches the existing precedent set by `ReportingService` (`_get_revenue_by_month`, `_get_contractor_utilization`, `get_utilization_heatmap`, etc.), which already computes cross-table aggregates live rather than maintaining rollup tables. At this project's scale (SMB contractors, tens of active projects and hundreds of time entries/cost entries per company) live aggregation is fast and — critically — always correct, avoiding the invalidation-on-every-cost-entry-write problem a materialized/snapshot approach would introduce. If a specific company later has thousands of cost entries per project and dashboard queries become slow, add a targeted composite index first (`(company_id, trade_scope_id)` on `cost_entries`, matching the style of the existing `0021_performance_indexes.py` migration) before reaching for materialization.

### Pattern 4: Reuse the AIService/scheduler tool-use pattern for both AI features, but at different call shapes

**What:** Both new AI features build on the Claude tool-use plumbing already in `app/features/ai/service.py` (`AIService`), but they are **not** the same shape as the existing conversational intake/interview flow:
- **AI profitability analyzer** = scheduled, batch, one Claude call per project-with-a-signal (mirrors `DashboardService.detect_schedule_slips` → `_find_slip_candidates` → `gather_with_concurrency` → `_call_claude_for_slip`-style helper → `_persist_alerts`, wired into `scheduler.py` via `_run_for_all_companies`).
- **AI quote estimator** = on-demand, single-turn, structured-output call triggered from the "New Quote" UI action (closer to `ChecklistService.generate_daily_checklists`'s single-shot structured generation than to the multi-turn `AIConversation` used for intake).

**When to use:** Analyzer → cron. Estimator → synchronous request/response endpoint (`POST /finance/quotes/estimate`), not a background job.

**Trade-offs:** Forcing the quote estimator into the conversational `AIConversation` model (used for intake/interview) would add unnecessary state-machine complexity for what is fundamentally "given this job/trade-scope description, propose priced line items" — a single request/response. Keep it stateless.

**Example (scheduler addition, mirrors `run_alert_detection`):**
```python
async def run_financial_analysis() -> None:
    from app.features.finance.service import FinanceService

    today = datetime.now(UTC).date()
    await _run_for_all_companies(
        job_name="run_financial_analysis",
        service_class=FinanceService,
        method_name="analyze_profitability",
        target_date=today,
    )

# in lifespan():
scheduler.add_job(
    run_financial_analysis,
    trigger=CronTrigger(hour=20, minute=0),  # end of day, after time entries close out
    id="financial_analysis",
    replace_existing=True,
    misfire_grace_time=ALERT_MISFIRE_GRACE_SECONDS,
)
```

## Data Flow

### Request Flow — Margin dashboard read

```
GC/PM opens Project → Financials tab (web)
    ↓
GET /api/proxy → /finance/projects/{id}/margin  [require_permission("finance.margin.view")]
    ↓
FinanceRouter → FinanceService.get_project_margin(project_id)
    ↓ (parallel aggregate queries, no N+1 loops)
  revenue: SUM(Invoice.amount_paid / line items) across trade_scopes under project
  cost:    SUM(CostEntry.amount) + SUM(TimeEntry.duration_seconds × LaborRate.hourly_rate)
  budget:  Budget.amount per trade_scope, compared to cost
    ↓
FinanceService returns {revenue, actual_cost, margin, margin_pct, budget_status per trade_scope}
    ↓
TanStack Query caches response → MarginSummaryCard, BudgetProgressBar render
```

### Request Flow — Actual-cost capture (materials/subcontractor)

```
Foreman/PM logs a material receipt (web or mobile form)
    ↓
POST /finance/costs { trade_scope_id | job_id, cost_type, amount, vendor, incurred_date, attachment_id? }
    ↓ [require_permission("finance.costs.create")]
CostEntryService.create() → CostEntryRepository (TenantScopedRepository — RLS applies via company_id)
    ↓
Next FinanceService read for that project/job reflects the new spend immediately (on-the-fly, no cache invalidation step needed)
```

### Request Flow — AI profitability analyzer (nightly)

```
APScheduler cron (20:00 UTC) → run_financial_analysis()
    ↓
_run_for_all_companies iterates active companies (bounded concurrency, per-company DB session + tenant context)
    ↓
FinanceService.analyze_profitability(company_id, target_date):
  1. Compute margin/budget-status for every active project/trade_scope (Pattern 3)
  2. Filter to ones crossing a threshold (margin_pct dropped, budget_status = at_risk/over)
  3. gather_with_concurrency → Claude tool-use call per flagged item → structured
     {severity, impact_text, remediation_text}
  4. Persist as DashboardAlert rows with alert_type='margin_erosion' | 'budget_overrun_risk'
    ↓
Existing monitoring dashboard alert feed (web + mobile) shows the new alert types —
but the alerts list endpoint MUST filter financial alert_types out for callers
lacking finance.* (see Anti-Pattern 1 below)
```

### Key Data Flows

1. **Labor cost derivation:** `TimeEntry` (extended with `trade_scope_id`/`task_id`) × `LaborRate` (effective-dated by `user_id`) → computed labor cost, never stored — always derived at read time by `FinanceService`.
2. **Revenue side is untouched:** `Quote`/`Invoice`/`BillingMilestone` already exist and already carry the job-vs-trade-scope duality; v4.0 only *reads* them, adding zero new revenue-side tables or columns.
3. **Permission boundary is centralized, not per-field:** financial numbers are only ever returned by `/finance/*` endpoints and the alert feed filter — never added as extra fields on the existing `Project`/`Job`/`TradeScope` response schemas (see Anti-Pattern 1).

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|---------------------------|
| Current (SMB contractors, tens of projects/company) | On-the-fly `FinanceService` aggregation is fine; no snapshot tables needed |
| Growth (hundreds of cost entries + time entries per project) | Add composite indexes: `(company_id, trade_scope_id)` and `(company_id, job_id)` on `cost_entries`, `(trade_scope_id)`/`(task_id)` on `time_entries` — same style as the existing `0021_performance_indexes.py` |
| Large scale (thousands of projects/company, dashboard latency) | Only then consider a nightly-refreshed `project_financial_snapshot` rollup table populated by the same `run_financial_analysis` cron job that already runs nightly — the AI analyzer job is the natural place to also persist a snapshot, since it already computes the numbers |

### Scaling Priorities

1. **First bottleneck:** `FinanceService` margin query doing a live join across `CostEntry` + `TimeEntry` + `LaborRate` for every project on every dashboard page load — fixed with targeted indexes, not materialization, until proven insufficient.
2. **Second bottleneck (unlikely at this project's scale):** nightly AI analyzer scanning every active project across every company sequentially — already mitigated by the existing `AI_CONCURRENCY_LIMIT` semaphore and per-company bounded concurrency pattern in `_run_for_all_companies`.

## Anti-Patterns

### Anti-Pattern 1: Embedding margin/cost fields directly on `Project`/`Job`/`TradeScope` response schemas

**What people do:** Add `margin_pct`, `actual_cost`, `budget_status` as extra fields on the existing project/job detail response so the frontend gets everything in one call.

**Why it's wrong:** `finance.*` permission enforcement then has to happen at the field-serialization level (conditionally omit fields per caller), which is easy to get wrong and easy to regress — a future unrelated change to `ProjectResponse` could accidentally leak margin data to a `foreman` or `client` role. It also couples the always-fast project-detail endpoint to a heavier financial aggregation query for every caller, even those without finance access.

**Do this instead:** Keep financial data behind dedicated `/finance/*` endpoints, each independently gated by `require_permission("finance.X")`. The web Financials tab makes a second request. This mirrors how `billing_milestones` already lives in its own module rather than being inlined onto `TradeScope`.

### Anti-Pattern 2: Adding a `hourly_rate` column to `User` and treating it as always-current

**What people do:** Ship the fastest possible version — one column, no history.

**Why it's wrong:** The first pay-rate change silently rewrites the computed labor cost (and therefore margin) of every historical job/project for that worker, since cost is derived at read time from whatever the "current" rate is. Historical profit reports become non-reproducible.

**Do this instead:** Use the effective-dated `LaborRate` table (Pattern 2). If simplicity is prioritized for a v1 cut, at minimum snapshot the rate used onto a computed field when `FinanceService` runs the nightly AI analysis, so historical alerts remain explainable even if the live dashboard figure can still drift.

### Anti-Pattern 3: Forking `TimeEntry` into a separate project-side time-tracking table

**What people do:** Since `TimeEntry.job_id` is `NOT NULL` today and jobs/projects are parallel systems, create a new `TaskTimeEntry` table for trade-scope/task-based clock-in rather than touching the existing table.

**Why it's wrong:** Splits the single source of truth for "hours worked" into two tables that both need their own mobile clock-in UI, their own sync/offline handling (mobile Drift cache), and their own aggregation logic in `FinanceService` — doubling the surface area for a distinction (job vs. trade scope) that `Quote`/`Invoice` already solved once with nullable-pair columns.

**Do this instead:** Extend `TimeEntry` (Pattern 1) — relax `job_id` to nullable, add nullable `trade_scope_id`/`task_id`, one XOR validator. One clock-in flow, one table, one aggregation path.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|----------------------|-------|
| Claude API (Anthropic) | Already integrated via `app/features/ai/service.py` (`AIService`) and `app/core/ai_utils.py` (`AI_CONCURRENCY_LIMIT`, retry helper `_call_with_retry`) | Reuse directly — no new API client, no new credential. Both new AI features are additional tool-use call sites, not a new integration. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|----------------|-------|
| `finance/` ↔ `jobs/` (Job) | Direct FK reference (`CostEntry.job_id`, extended `TimeEntry.job_id`) | Read-only from `finance/`'s perspective; no changes to `Job`/`JobService` needed beyond the `TimeEntry` extension living in `jobs/models.py` |
| `finance/` ↔ `projects/` (TradeScope, Task) | Direct FK reference (`CostEntry.trade_scope_id`, `Budget.trade_scope_id`, extended `TimeEntry.trade_scope_id`/`task_id`) | Same read-only relationship; `Task.estimated_cost`/`estimated_hours` (existing) can seed AI quote-estimator context but are not written to by `finance/` |
| `finance/` ↔ `quotes/` + `invoices/` | Read-only query for revenue aggregation (`FinanceService`) and for historical pricing (`QuoteEstimatorService` reading past `QuoteLineItem.unit_price` grouped by `description`) | No FK changes to `Quote`/`Invoice`; purely SELECT queries |
| `finance/` ↔ `dashboard/` (DashboardAlert) | `finance/`'s scheduled analyzer writes rows into the existing `dashboard_alerts` table with new `alert_type` values | `dashboard/service.py`'s alert-list endpoint needs a small permission-aware filter added so `margin_erosion`/`budget_overrun_risk` alert types are excluded from the response for callers without `finance.*` — this is a **required modification**, not purely additive |
| `finance/` ↔ `rbac/` (`app/core/permissions.py`) | New catalog entries + default-matrix changes | Must add finance keys to the "keys excluded from admin's auto-derived set" (currently `_OWNER_ONLY_KEYS`) so `admin` does not silently inherit financial access, and explicitly add them to `project_manager`'s hand-maintained list — **owner needs no change** (already wildcard, and unaffected by `_OWNER_ONLY_KEYS`) |
| `finance/` ↔ web `features/finance/` | REST via `/api/proxy`, TanStack Query | Follows existing proxy pattern used by every other web feature module |
| `finance/` ↔ mobile (Flutter/Drift) | Not required for v4.0 core scope per milestone framing (owner/PM-only, web-dashboard-oriented) — but the `TimeEntry` extension (Pattern 1/Anti-Pattern 3) **does** touch mobile clock-in flow if project/trade-scope time tracking is to work at all, since that's where clock-in currently happens | Flag for roadmap: decide whether trade-scope/task clock-in ships in mobile UI this milestone, or whether v4.0 labor-cost-from-time-entries is initially job-only (simpler) with project/trade-scope time tracking following the extended schema in a later milestone |

## Suggested Build Order

Dependency-constrained: cost capture and labor rates must exist before margin can be computed; margin must exist before budgeting-vs-actual and the AI analyzer can be meaningful; the web dashboard consumes backend endpoints as they land.

```
1. Foundation: schema + permissions (no feature dependencies — pure DB + RBAC)
   - Migration 0030: cost_entries, labor_rates, budgets tables
   - Alter time_entries: job_id → nullable, add trade_scope_id/task_id, XOR validator
   - Add finance.* keys to PERMISSION_CATALOG; exclude from admin's auto-derived set;
     add explicitly to project_manager's default list (owner unaffected — wildcard)
   Deliverable: schema exists, RBAC gate exists, nothing reads/writes through it yet

2. Actual-cost capture (materials + subcontractor)
   - CostEntry model/schema/repository/service/router (standard CRUD, follows
     BaseService/TenantScopedRepository/CRUDRouter conventions)
   - Web: CostEntryForm under project/trade-scope detail
   Deliverable: PM/owner can log material and subcontractor spend against a job or trade scope

3. Labor rate management
   - LaborRate model/schema/repository/service/router (CRUD)
   - Web: rate management under Team/Settings
   Deliverable: owner/PM can set effective-dated hourly cost rates per user

4. TimeEntry extension for project-based work
   - Backend: accept trade_scope_id/task_id on clock-in for project hierarchy work
   - Mobile: clock-in flow gains a trade-scope/task target when working project-side
     (decide scope here — see "mobile" integration point flag above; can be deferred
     to job-only labor cost for a leaner v1 if mobile clock-in UI work is out of budget)
   Deliverable: hours worked are attributable to a trade scope/task, not just a job

5. Margin computation (FinanceService)
   - Read-only aggregation: revenue (Quote/Invoice) − cost (CostEntry + TimeEntry×LaborRate)
   - Endpoints: GET /finance/projects/{id}/margin, GET /finance/jobs/{id}/margin
   Deliverable: profit margin tracking — the core v4.0 requirement — is live via API
   Depends on: 2, 3, 4

6. Budgeting + overrun-risk
   - Budget model/schema/repository/service/router (CRUD)
   - FinanceService: budget-vs-actual comparison, overrun-risk threshold flag
   Deliverable: PM/owner can set budgets and see spend-vs-budget status
   Depends on: 5

7. Web financial dashboard
   - features/finance/ (components + hooks), Financials tab on project detail,
     company-wide margin view under Reports
   - Permission-gated nav item (only rendered when finance.* granted)
   Deliverable: owner/PM see margin, budget status, cost entries in the UI
   Depends on: 2, 3, 5, 6 (consumes their endpoints)

8. AI profitability analyzer
   - FinanceService.analyze_profitability(), scheduler.py: run_financial_analysis
     (mirrors run_alert_detection), DashboardAlert extended with new alert_type values
   - dashboard alert-list endpoint: filter financial alert_types by finance.* permission
   Deliverable: AI flags margin erosion / budget overrun risk automatically, nightly
   Depends on: 5, 6

9. AI quote planning (can run in parallel with 6-8 once 3 is done)
   - QuoteEstimatorService: on-demand Claude tool-use call, single-shot structured
     line-item generation, priced from historical QuoteLineItem.unit_price + LaborRate
   - Web: "AI-assist" action on New Quote flow
   Deliverable: AI proposes priced labor+material line items for a new quote
   Depends on: 3 (labor rates); loosely depends on 2/5 (richer historical cost data
   improves suggestions but isn't strictly required to ship a first version)
```

**Rationale for this order:** cost capture (2) and labor rates (3) are independent, low-risk CRUD slices that can be built and tested in isolation and in parallel — they're the foundation every other feature reads from. Margin computation (5) is the single highest-value deliverable (it directly satisfies "profit margin tracking") and should land as soon as its two inputs exist, even before budgeting or AI. Budgeting (6) and the AI analyzer (8) both consume margin output, so they naturally follow. The AI quote estimator (9) is the most independent of the AI features — it only needs historical pricing data, not the margin/budget machinery — so it can be pulled forward or parallelized with the team's AI-focused workstream without blocking on 5-8 if sequencing constraints require it.

## Sources

All findings are grounded in direct inspection of the existing codebase at `/Users/heechung/AndroidStudioProjects/contractormanagement`:

- `backend/app/features/jobs/models.py` — `Job`, `TimeEntry` (confirms `job_id` NOT NULL, no `trade_scope_id`/`task_id` link today)
- `backend/app/features/projects/models.py` — `Project`, `TradeScope`, `Task` (confirms no `project_id` on `Job`, `estimated_hours`/`estimated_cost` on `Task` but no actual/spent tracking anywhere)
- `backend/app/features/quotes/models.py`, `backend/app/features/quotes/schemas.py` — polymorphic `job_id`/`trade_scope_id` pattern and its `model_validator` XOR enforcement (source of Pattern 1)
- `backend/app/features/invoices/models.py` — `job_id`/`trade_scope_id`/`milestone_id`/`quote_id`, `amount_paid` (revenue-side read target for `FinanceService`)
- `backend/app/features/billing_milestones/models.py` — precedent for a small, focused finance-adjacent module
- `backend/app/features/dashboard/models.py`, `backend/app/features/dashboard/service.py` (`DashboardAlert`, `detect_schedule_slips`) — source of Pattern 4 / alert reuse strategy
- `backend/app/core/scheduler.py` — `_run_for_all_companies`, `run_morning_checklists`, `run_alert_detection`, `lifespan` cron wiring (source of the `run_financial_analysis` proposal)
- `backend/app/features/ai/service.py` — `AIService` Claude tool-use plumbing (`_call_with_retry`, `stream_turn`, `validate_tool_input`) reused by both new AI features
- `backend/app/core/permissions.py` — `PERMISSION_CATALOG`, `DEFAULT_ROLE_PERMISSIONS`, `_OWNER_ONLY_KEYS`, `expand()` (source of the RBAC integration finding, including the admin-auto-inherit gotcha)
- `backend/app/core/security.py` — `require_permission()` dependency pattern
- `backend/app/core/base_service.py`, `backend/app/core/base_repository.py` — `BaseService`/`TenantScopedService`, `BaseRepository`/`TenantScopedRepository` conventions
- `backend/app/features/reports/service.py` — `ReportingService`, precedent for a plain aggregation class outside the CRUD `BaseService` hierarchy (source of Pattern 3 / `FinanceService` shape)
- `backend/app/features/users/models.py` — confirms no existing rate field on `User` (source of Pattern 2)
- `backend/app/features/companies/models.py` — company-level settings surface (no existing overhead/rate config)
- `backend/app/features/foreman/models.py`, `backend/app/features/checklists/models.py` — confirms no actual/spent-hours tracking exists anywhere in the project hierarchy today
- `backend/migrations/versions/` — latest migration `0029_contracts_and_license.py`, confirms next migration number `0030`
- `web/src/features/`, `web/src/app/(dashboard)/` — existing feature-module and route conventions for the web dashboard section
- `.planning/PROJECT.md` — v4.0 milestone scope, requirements, and constraints

---
*Architecture research for: financial-intelligence integration into existing FastAPI/Next.js/Flutter multi-trade construction platform*
*Researched: 2026-07-24*
