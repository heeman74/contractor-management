# Phase 35: Web Financial Dashboard - Research

**Researched:** 2026-07-28
**Domain:** Time-bucketed financial aggregation (FastAPI/SQLAlchemy async) + permission-gated charting UI (Next.js 16 / React 19 / Recharts 3.8)
**Confidence:** HIGH (codebase-grounded; every recommendation traces to shipped Phase 31–34 code or an existing Reports/Playwright convention)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Margin trend**
- **D-01:** **Reconstructed from dated records** — cumulative margin over time computed from records that already carry dates: cost `incurred_date`, time-entry work days (UTC convention from Phase 32), invoice dates, approved quote dates. No snapshot table; works retroactively from day one; stays consistent with computed-on-read. Incomplete-data status carries into the trend honestly.
- **D-02:** **Monthly buckets.** Cumulative revenue-to-date minus cost-to-date per month. (Exact bucket-edge and revenue-basis-over-time semantics: Claude's discretion, but deterministic and documented — e.g., quote-basis revenue appears in the bucket of quote approval, invoice revenue in the bucket of issuance, consistent with Phase 33 D-01 resolution at each point in time or a documented simplification.)

**Performance**
- **D-03:** **Computed-on-read, settled by data.** No cache/denormalization. The phase MUST include a measured performance check (seeded multi-project company; company-rollup endpoint under a stated latency budget) so the Phase 33 D-11 deferral is closed with evidence, not assumption. If the test proves the budget is exceeded, caching becomes a follow-up decision — not silently added.

**Structure & navigation**
- **D-04:** **Dedicated "Financials" nav item**, sibling to Reports in the sidebar, visible only with `finance.view`; the route guard blocks direct navigation without permission (redirect/404 — exact behavior consistent with existing permission-gated routes). The ungated Reports page is untouched except for the sibling nav entry (Phase 30 D-06 boundary).
- **D-05:** **Company overview + project drill-down:** `/financials` = company rollup + project list; `/financials/[projectId]` = that project's charts. Deep-linkable; same layout/visual conventions as Reports (chart-card, skeleton, Recharts 3.8).

**Chart content**
- **D-06:** **Company overview ships:** portfolio margin summary tiles (revenue, cost, margin $ ·%), budget-vs-actual bars per project, and an attention list.
- **D-07:** **Project drill-down ships:** margin trend line (D-01/D-02), budget-vs-actual per trade scope, cost category mix (labor / materials / subcontractor / other — the Phase 32 breakdown).
- **D-08:** **Attention list ranking — ordered tiers, shipped signals only:** budget overruns first (worst % over at top), then 80%+ warnings, then incomplete-data projects. No composite scoring (that's Phase 36 AI territory). Show all qualifying projects.

**Honest aggregates**
- **D-09:** **Include + count badge.** Flagged (incomplete-data) projects' figures roll into portfolio totals, and summary tiles carry a badge like "3 projects with incomplete data" that ties to the attention list. Never exclude — an excluded project misstates the portfolio (Phase 33 honesty posture at aggregate level). Quote-basis (estimated) revenue in aggregates follows the same labeling spirit — surface the estimated share (exact presentation: Claude's discretion within UI-SPEC).

**Filtering**
- **D-10:** **Trend window only.** The margin-trend chart gets a Reports-style range selector (e.g., 3m / 6m / 12m / all); portfolio totals and budget-vs-actual stay all-time — budgets and margins are lifetime-of-project numbers, and date-filtered budget-vs-actual would mislead.

### Claude's Discretion
- Trend bucket-edge semantics and how revenue basis resolves per bucket (D-02 note); percent/rounding consistent with shipped conventions.
- Endpoint shapes (company rollup + project financials + trend — new gated endpoints under the finance feature; Decimal-as-string).
- Latency budget number for the D-03 performance test (state it in the plan).
- Chart composition details (Recharts config, colors per the dataviz/UI-SPEC pass, empty/loading/error states per Reports skeleton conventions).
- Attention-list row content; project-list columns on /financials.
- Route-guard implementation (layout-level check vs middleware) consistent with existing gated routes.

### Deferred Ideas (OUT OF SCOPE)
- Margin snapshot table / cached aggregates — only if the D-03 performance test fails its budget
- Composite attention scoring — Phase 36 AI
- Mobile financial dashboard — not in v4.0 scope (web-only per MARG-04)
- Date-filtering portfolio totals/budget-vs-actual — rejected as misleading
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MARG-04 | Owner/PM can see margin + budget-vs-actual charts on the web financial dashboard | §Architecture Pattern 1 (batched company-rollup endpoint), Pattern 2 (monthly cumulative trend), Pattern 3 (per-scope budget-vs-actual without N+1), Pattern 5 (Recharts composition mirroring Reports), Pattern 6 (nav gating + route guard). Attention tiers derive from shipped `budget_math.crossed_thresholds` + `MarginSummary.incomplete` — no new scoring (§Pattern 4). |
</phase_requirements>

---

## Project Constraints (from CLAUDE.md)

These are directives, not suggestions. The planner must verify every task complies.

| Directive | Applies to this phase as |
|---|---|
| **NEVER query inside a loop**; eager-load with `selectinload`/`joinedload` | The company rollup MUST NOT call `rollup_for_project` per project (that would be 7 round trips × N projects). See Pattern 1. |
| All models `relationship(lazy="raise")` | `Invoice.line_items`, `Quote.line_items`, `CostEntry.category`, `TimeEntry.job` are all `lazy="raise"` — the new queries must select **columns only** or eager-load explicitly, exactly as `RevenueRepository` already does. |
| `AsyncSession` via `get_db`; **no `db.commit()` in services** | All three new endpoints are read-only; no commits at all. |
| New repositories inherit `TenantScopedRepository`; services inherit `TenantScopedService`; **standalone service functions are NOT allowed** | New batched query methods go on `FinanceRepository`/`RevenueRepository`/`BudgetRepository` (or a new `PortfolioRepository(TenantScopedRepository)`); orchestration on a service class. Pure math functions in a DB-free module are the established exception (`margin_math.py`, `budget_math.py`, `labor_derivation.py` are all module-level pure functions — follow that precedent, not "service functions"). |
| Response schemas inherit `BaseResponseSchema`… | …only for entity responses with id/timestamps. The shipped finance aggregate blocks (`MarginSummary`, `BudgetVsActual`, `CostBreakdownResponse`) are plain `BaseModel` — follow that. |
| Routers stay thin; gate **inline in the handler body** with `await require_permission("finance.view")(current_user, db)` | Plain `APIRouter`, never `CRUDRouter` (31-RESEARCH Pitfall 4). Mirror `finance/router.py` exactly. |
| Clean Code: ~20-line functions, one thing, no magic numbers, DRY, no dead code, minimal comments (WHY not WHAT) | Bucket-window constants, tier names, and chart colors must be named constants. The trend/portfolio math belongs in a pure module so functions stay tiny and testable. |
| `ruff check` + `ruff format` before commit (backend) | Note: ruff `UP047` enforces PEP 695 generics in this repo (`def f[RateT: EffectiveDatedRate]`); venv is Python 3.12.12. |
| `npm run lint` (`--max-warnings 0`) + `npx tsc --noEmit` before commit (web) | Two known traps: `react-hooks/set-state-in-effect` forbids reset-on-open `useEffect` (32-03/34-07 lesson — use `onOpenChange` wrappers); Recharts `Tooltip`/`Bar` handler params need the codebase's `// eslint-disable-next-line @typescript-eslint/no-explicit-any` convention. |
| **Every new feature ships E2E tests in the same change**; a feature is not done until they pass | Backend `tests/test_phase_35_e2e.py`; web `web/tests/phase-35-financials.spec.ts`. Non-negotiable. |
| Test edge cases: invalid input, missing auth, wrong token types, empty results, soft-deleted records | Soft-deleted cost entries / budgets / projects must be excluded; `BaseRepository.list_all()` does NOT filter `deleted_at` (Phase 31 pitfall) — every new query states it explicitly. |

**Project skill `.claude/skills/e2e-feature-tests` applies.** Backend: real `contractorhub_test` DB via `conftest.py` fixtures (`seed_two_tenants`, `tenant_a_client`, `tenant_b_client`), assert RLS isolation. Web: mock `/api/proxy` with `page.route`, mock `access_token` cookie, assert both captured request and resulting UI.

---

## Summary

Phase 35 adds **no new math and no new data**. Every figure it renders already exists as a tested pure function (`margin_math.py`, `budget_math.py`, `labor_derivation.py`) or a shipped query. What is genuinely new is (a) **batching** those queries across all of a company's projects in a constant number of round trips, (b) **replaying** the shipped Phase 33 D-01 revenue resolution at monthly cut-off dates to produce a cumulative trend, and (c) the **charts + gated navigation** on the web.

The single most important design constraint is the CLAUDE.md N+1 rule at company scale. `FinanceService.rollup_for_project` costs ~7 round trips per project; calling it in a loop over N projects is exactly the anti-pattern the codebase forbids and would guarantee failure of the D-03 latency budget. The recommended shape is a **parallel batched read path** (8 queries, constant in N) that never touches the shipped per-project path, pinned to it by a named equivalence test — the exact precedent set in Phase 34 (`test_sweep_scope_spends_equivalence_matches_trade_scope_spend`, called out in `budget_repository.scope_spends`'s docstring as a Pitfall-6 guard).

For the trend (D-02 discretion), the recommendation is **as-of resolution at each month-end**, not delta accumulation: for bucket edge `E`, filter every dated record to `date <= E` and run the *unmodified* shipped `_anchor_revenues` / `_combined_anchor_revenue` / `summarize_labor` / `summarize_margin` pipeline. This makes the final bucket bit-identical to `rollup_for_project`'s margin block — a self-verifying reconciliation the tests can assert — and it is literally the option D-02 names first ("consistent with Phase 33 D-01 resolution at each point in time"). Delta accumulation is rejected because a quote superseded by an invoice at the same anchor would double-count and the final bucket would not reconcile.

**Primary recommendation:** Ship three read-only `finance.view`-gated endpoints (`GET /financials/company`, `GET /projects/{id}/financials`, `GET /projects/{id}/financials/trend?window=`), all served by one new batched repository layer plus one new DB-free pure module (`portfolio_math.py` for tiers/totals, trend bucketing reusing existing math). Guard the web at a `financials/layout.tsx` `usePermissions()` gate that also short-circuits the queries (`enabled: can("finance.view")`), so an unauthorized cold load never even issues a financial request — the assertion that makes the SC3 keystone test meaningful.

---

## Standard Stack

**No new dependency is added by this phase.** Everything below is already installed and in production use in this repo.

### Core

| Library | Version (verified) | Purpose | Why Standard |
|---------|-----------|---------|--------------|
| recharts | 3.8.0 (`web/node_modules/recharts/package.json`) | All four new charts | Already the chart library for all 4 Reports charts; CONTEXT canonical ref says "no new chart dependency" |
| @tanstack/react-query | ^5.90.21 | Data fetching/caching for the 3 new endpoints | Every finance hook in `web/src/features/finance/hooks.ts` already uses it |
| next | 16.1.6 (App Router) | `financials/layout.tsx` route guard + `[projectId]` dynamic segment | Existing `(dashboard)` route group |
| react | 19.2.3 | — | — |
| lucide-react | ^0.577.0 | `Wallet` icon for the nav item | `BarChart3` is taken by Reports |
| SQLAlchemy async + FastAPI | as shipped | Batched aggregate queries | Existing finance feature |
| Python | 3.12.12 (`backend/.venv`) | PEP 695 generics required by ruff UP047 | Phase 32 precedent |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| date-fns | ^4.1.0 | Month labels / window boundaries client-side | Only for *display*; all bucket keys come from the server as `"YYYY-MM"` strings |
| @playwright/test | ^1.58.2 | Web E2E (`npm run test-e2e`) | SC3 keystone |
| jest + @testing-library/react | ^30.3.0 / ^16.3.2 | Component unit tests (`npm test`, matches `src/**/__tests__/**/*.test.tsx`) | Chart-adjacent pure logic + gate component |
| pytest + httpx AsyncClient | as shipped | Backend E2E + performance test | `tests/test_phase_35_e2e.py` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Recharts `LineChart` | `AreaChart` (as `revenue-chart.tsx` uses) | D-07 says "margin trend **line**" — use `LineChart`+`Line`. Area implies a filled magnitude, which reads wrong for a value that can go negative. |
| Server-ordered attention list | Client-side filter+sort of the projects array | Server-ordered wins: D-08's tier rule must not be re-implemented differently by Phase 36 AI or a future mobile surface. One implementation, in `portfolio_math.py`. |
| SQL `date_trunc`/`to_char` bucketing | Python-side bucketing of fetched rows | **Python wins here.** The effective-dated rate rule (`resolve_rate_row_for_work_date`) is deliberately DB-free and Phase 32 explicitly states it "lives in exactly one place, never duplicated in SQL" (`LaborRateService.list_current_rates` docstring). Labor cost cannot be bucketed in SQL without duplicating that rule. Bucketing everything in Python keeps one UTC convention and one code path. |
| New `/financials/*` endpoint tree | Extending `GET /projects/{id}/cost-entries` | The rollup returns `entries[]` (unbounded itemized rows) that a chart page must not download. Dedicated endpoints omit it. |

**Installation:** none.

---

## Architecture Patterns

### Recommended structure

```
backend/app/features/finance/
├── portfolio_math.py        # NEW — DB-free: portfolio totals, attention tiers/order
├── trend_math.py            # NEW — DB-free: month bucketing + as-of replay (reuses margin_math)
├── portfolio_repository.py  # NEW — batched, company-wide column-only aggregates
├── portfolio_service.py     # NEW — orchestrates the 3 endpoints (TenantScopedService)
├── schemas.py               # EXTEND — additive response models only
└── router.py                # EXTEND — 3 new finance.view-gated GET handlers

web/src/app/(dashboard)/financials/
├── layout.tsx                       # NEW — FinanceGate (usePermissions) wraps both routes
├── page.tsx                         # NEW — dynamic(ssr:false) + skeleton (mirrors reports/page.tsx)
├── _components/
│   ├── company-financials-dashboard.tsx
│   ├── portfolio-summary-tiles.tsx
│   ├── project-budget-bars.tsx
│   ├── attention-list.tsx
│   └── financials-skeleton.tsx
└── [projectId]/
    ├── page.tsx
    └── _components/
        ├── project-financials-dashboard.tsx
        ├── margin-trend-chart.tsx
        ├── scope-budget-bars.tsx
        ├── category-mix-chart.tsx
        └── trend-window-filter.tsx

web/src/features/finance/{types,api,hooks}.ts   # EXTEND — 3 new typed calls + hooks
web/src/components/layout/sidebar.tsx           # EXTEND — one nav item
```

---

### Pattern 1: Batched company rollup — 8 queries, constant in project count

**What:** Every per-project figure the overview needs, gathered by a fixed set of grouped column-only queries. Nothing per project.

**Why:** `FinanceService.rollup_for_project` is ~7 round trips (3 cost/labor + 2 revenue + up to 1 D-14 quote + 1 budget). At 25 projects a naive loop is 175 round trips. CLAUDE.md forbids querying inside a loop, and D-03's latency budget would not survive it.

**The 8 queries:**

| # | Query | Returns |
|---|---|---|
| 1 | Projects: `select(Project.id, Project.name, Project.status).where(Project.deleted_at.is_(None))` | project list (RLS-scoped) |
| 2 | Cost entries, grouped: dual-outerjoin, `COALESCE(TradeScope.project_id, Job.project_id)` as project key, `GROUP BY project_key, job_id, trade_scope_id, category_id, category_name` → `SUM(amount)` | per-project **anchor sums** (for the D-12 missing-cost flag) **and** category mix, in one pass |
| 3 | Costable sessions: `_costable_sessions_query().join(Job).where(Job.project_id.is_not(None))` + select `Job.project_id` | work sessions tagged with project |
| 4 | Labor rates: `LaborRateRepository.list_rates_for_users(sorted(contractor_ids))` | shared rate map (existing method, unchanged) |
| 5 | Invoice amounts by anchor **and project**: `_invoice_amounts_query()` + dual outerjoin + coalesced project key | revenue leg A |
| 6 | Approved-quote amounts by anchor **and project**: `_approved_quote_amounts_query()` + same traversal, newest-first | revenue leg B |
| 7 | Project-level approved quotes (D-14 fallback): `_approved_quote_amounts_query().where(Quote.project_id.is_not(None), Quote.job_id.is_(None), Quote.trade_scope_id.is_(None))` | fallback candidates, newest per project |
| 8 | Active budgets: `BudgetRepository.list_active()` (already exists — returns project **and** scope budgets with `warning_fired_at`/`overrun_fired_at`) | budget totals |

Scope spends for scope budgets come from the already-batched, already-equivalence-tested `BudgetRepository.scope_spends([ids])` — reuse it, do not write a second SUM (that is exactly the Pitfall 6 the shipped docstring warns about). That is a 9th query only when scope budgets exist.

**Critical SQL detail:** the coalesced project key must be added to `GROUP BY` explicitly. PostgreSQL's functional-dependency shortcut only applies to columns of a table whose primary key is grouped; `trade_scopes.project_id` / `jobs.project_id` do not belong to `invoices`/`quotes`/`cost_entries`, so grouping by `Invoice.id` alone will **not** license selecting the coalesced key.

**Why `COALESCE` is exact here:** `CostEntry`, `Invoice` and `Quote` all anchor job XOR trade_scope, so at most one of the two outer joins produces a project id. Rows where both are NULL (an invoice with no job and no scope) coalesce to NULL and drop out — which is precisely what the shipped `(TradeScope.project_id == pid) | (Job.project_id == pid)` filter already does.

**Indexes already present (no migration needed):** `ix_cost_entries_job_id`, `ix_cost_entries_trade_scope_id`, `ix_cost_entries_company_id` (0032); `idx_trade_scopes_project_id` (0015); `ix_jobs_project_id` (0030); `idx_time_entries_job_id` (0009); `ix_quotes_job_id`, `ix_invoices_job_id`, `ix_quotes_trade_scope_id`, `ix_invoices_trade_scope_id` (0021/0023); `ix_labor_rates_company_user_effective` (0032); `ix_budgets_project_id` (0032). There is **no** index on `cost_entries.incurred_date` — this is fine because the trend never filters by date in SQL (all bucketing is Python-side, see Pattern 2). Do not add an index speculatively; let the D-03 measurement decide.

**Reuse, do not refactor:** leave `rollup_for_project`, `job_cost_breakdown`, `trade_scope_cost_breakdown` untouched (mobile parses them strictly). Add the batched path alongside, and pin them together (see §Common Pitfalls, Pitfall 1).

---

### Pattern 2: Monthly cumulative trend — as-of replay at month-end edges

**What:** For each month bucket, recompute the *entire* Phase 33 margin block using only records dated on or before that month's last day.

**Deterministic semantics (the D-02 answer, to be documented in the module docstring):**

| Rule | Value |
|---|---|
| Bucket key | `"YYYY-MM"` (UTC) |
| Bucket edge | last calendar day of that month, **inclusive** |
| Cost entry lands in | every bucket whose edge ≥ `incurred_date` (cumulative) |
| Labor session lands in | every bucket whose edge ≥ `work_date_for(clocked_in_at)` — the shipped UTC work-day convention |
| Invoice revenue lands in | every bucket whose edge ≥ UTC date of `issued_at` |
| Approved-quote revenue lands in | every bucket whose edge ≥ UTC date of `approved_at` (fallback `created_at`, see Pitfall 4) |
| Revenue basis per bucket | run the **unmodified** `_anchor_revenues(invoices ≤ E, quotes ≤ E)` → `_combined_anchor_revenue`; D-14 project-level quote applies only when no anchor resolved |
| Bucket range | dense (no gaps) from the earliest dated record's month through the current UTC month |
| Window (D-10) | filters which buckets are **returned**, never which records are **included** |

**Algorithm (pure, DB-free, in `trend_math.py`):**

```
cost side  — O(C + S + B): compute each cost entry's month key and each session's
             (month key, session_labor_cost) ONCE, prefix-sum by month.
             Quantizing a sum of already-cent-quantized values is a no-op, so this is
             bit-identical to calling summarize_labor per bucket. unrated_seconds
             prefix-sums the same way.
revenue side — O(B x (I + Q)): NOT prefix-summable. D-01 says invoices supersede
             quotes at an anchor, so revenue is a resolution, not a sum. Re-resolve
             per bucket over the (small) document set.
per bucket  — summarize_margin(MarginInputs(revenue=..., cost=..., unrated_seconds=...,
             has_missing_cost_data=...)) -> the exact shipped MarginFigures block,
             including `incomplete` and `incomplete_reasons` (D-01: "incomplete-data
             status carries into the trend honestly").
```

**The reconciliation guarantee:** with `E = today`, this pipeline produces the identical `MarginSummary` that `rollup_for_project` returns. Assert it. That test is worth more than any amount of hand-verification of bucket arithmetic.

**Why not delta accumulation:** contributing each document to its own bucket and cumsumming double-counts an anchor that was quoted and later invoiced (Phase 33 Pitfall 2: "never summed, never max()ed"), and the last bucket would not equal the shipped rollup. Rejected.

**Known, accepted artifact:** an anchor quoted at \$10k and later part-invoiced at \$3k shows revenue *dropping* at the invoice month. That is honest — it is what the rollup would have said at each point in time — and the per-bucket `revenue_basis` field lets the UI annotate the basis change. Do not smooth it.

**Round-trip cost of the trend endpoint:** 6 bounded queries (costs, sessions, rates, invoices, quotes, project-level quote) — the same profile as the shipped rollup. Adding `Invoice.issued_at` / `Quote.approved_at` to the existing aggregate selects is safe: `Invoice.id`/`Quote.id` are already in `GROUP BY`, so those same-table columns are functionally dependent; add them to `GROUP BY` anyway for clarity.

---

### Pattern 3: Per-scope budget-vs-actual without an N+1 on the client

**What:** `GET /projects/{id}/financials` returns a `scopes[]` array with each scope's budget block already computed.

**Why:** the naive web implementation loops `useTradeScopeCostBreakdown(scopeId)` over the project's scopes — an N+1 across HTTP. Three server queries replace it: scopes (`id`, `trade_name`, ordered by `sort_order`), active scope budgets, and `BudgetRepository.scope_spends([ids])` (one grouped SUM, already equivalence-pinned to `trade_scope_spend`).

`BudgetVsActual` is assembled by the shipped `_to_budget_vs_actual(budget, spent)` — `percent_used` comes from `budget_math.percent_used`, never re-derived client-side (the shipped schema docstring is explicit about this).

Note the D-08 asymmetry the planner must keep straight: **CostEntry anchors job XOR trade_scope; Budget anchors project XOR trade_scope.** Labor is job-anchored, so a scope's `spent` legitimately excludes labor (`labor_tracked_at_job_level: true`) — the drill-down must carry that same honest note, not silently show a lower bar.

---

### Pattern 4: Attention tiers from shipped signals

**What:** `portfolio_math.py` classifies each project into `overrun` > `warning` > `incomplete` > (none) and orders the list.

```
tier(project):
  worst = max over the project's budgets (project budget + its scope budgets) of
          budget_math.crossed_thresholds(spent, total)      # shipped, tested rule
  if overrun in worst  -> ("overrun", percent_used)   # sort DESC by percent_used
  elif warning in worst-> ("warning", percent_used)   # sort DESC by percent_used
  elif margin.incomplete -> ("incomplete", None)      # sort by project name
  else -> not listed
```

**Recommendation — use LIVE threshold state, not `warning_fired_at`/`overrun_fired_at`.** Those columns are the *exactly-once alert claim*, not a live condition: `BudgetRepository.set_total` **nulls both on a raise** (D-03 re-arm), so a budget that is still 130% over can carry `overrun_fired_at IS NULL` right after an edit; conversely a fired claim persists after spend drops (a cost entry is soft-deleted). Deriving tiers from `crossed_thresholds(spent, total)` — the same function the alert engine uses — guarantees the attention list agrees with the budget bars rendered two inches above it on the same page. A tile saying 112% while the attention list omits the project is a visible, trust-destroying bug.

The fired timestamps remain useful as *metadata* (e.g. an "alerted" marker or `alerted_at` field), and the planner may include them, but they must not drive the tier. **This slightly reinterprets the phase brief's wording and is flagged in §Open Questions.**

D-08 says "show all qualifying projects" — no cap, no pagination. A project qualifies at its worst tier; the row should name the offending anchor (`"Plumbing scope"` vs the project itself) using the same vocabulary `budget_repository.alert_context` already produces for alert copy.

D-09's badge count = the number of projects whose `margin.incomplete` is true — the same set that forms the `incomplete` tier, so the badge and the list can never disagree.

---

### Pattern 5: Web composition — mirror Reports exactly

**Page shell** (copy `reports/page.tsx` verbatim in shape):

```tsx
const CompanyFinancialsDashboard = dynamic(
  () => import("./_components/company-financials-dashboard"),
  { ssr: false, loading: () => <FinancialsSkeleton /> }
);
```
`ssr: false` matters: Recharts' `ResponsiveContainer` measures the DOM and hydrates badly under SSR. Every Reports chart is behind this pattern.

**Conventions to mirror, with their exact shipped APIs:**

| Component | API | Notes |
|---|---|---|
| `ChartCard` | `{ title, kpiValue: string, icon: LucideIcon, csvFilename, csvRows: string[][], ariaLabel, children }` | Includes a built-in Export-CSV button — every new chart gets a `csvRows` builder, same as `reports-dashboard.tsx`. `aria-label` is how Playwright finds cards. |
| `EmptyState` | local function in `reports-dashboard.tsx`, `role="status"` | Not exported. Either lift it to a shared component or re-create it identically; **prefer lifting** (DRY, CLAUDE.md). |
| `ReportsSkeleton` | 4 × `Card` + `Skeleton` grid | Make a `FinancialsSkeleton` in the same shape; do not import the Reports one (different card count/layout). |
| Grid | `grid grid-cols-1 md:grid-cols-2 gap-8`; page wrapper `space-y-6`; heading `text-xl font-normal text-gray-900` + `text-sm text-muted-foreground` subtitle | |
| Error handling | `useEffect(() => { if (isError) toast.error("…", { duration: Infinity }) }, [isError])` (sonner) | |
| Chart height | `<ResponsiveContainer width="100%" height={280}>` | |
| Tooltip style | `{ backgroundColor: "white", border: "1px solid var(--border)", borderRadius: "6px", boxShadow: "0 1px 2px rgba(0,0,0,0.05)", padding: "8px" }` | Repeated verbatim in all 3 shipped cartesian charts — extract a shared constant rather than a 4th copy. |
| Colors | literal hexes (`#4f46e5` indigo, `#f59e0b` amber, `#22c55e` green, `#ef4444` red, `#6b7280` gray) | Follow it; no token system exists. Negative margin → `#ef4444`; over-budget bar → `#ef4444`; warning band → `#f59e0b`. |
| Formatters | `formatCurrency`, `formatSignedCurrency`, `formatDate` from `@/lib/format`; `formatMarginPercent`, `formatMarginDollars` from `features/finance/components/MarginSummarySection` | `formatCurrency` does **not** add thousands separators (34-04 lesson: asserting comma-formatted output breaks shipped tests). |
| Honesty chip | `<FinanceFlagChip testId="…">` (amber, informational) | Reuse for the D-09 portfolio badge. |

**Chart selection:**

| Chart | Recharts composition |
|---|---|
| Margin trend (D-07) | `LineChart` + `Line type="monotone"` for `margin`, optionally `revenue`/`cost` companions; `XAxis dataKey="month"`; `YAxis tickFormatter={(v) => \`$${(v/1000).toFixed(0)}k\`}` (revenue-chart precedent) |
| Budget vs actual per project (D-06) | `BarChart layout="vertical"`, `YAxis type="category" dataKey="projectName"`, two `Bar`s (budget, spent) or one `Bar` + `ReferenceLine` at 100% — horizontal reads far better for many project labels |
| Budget vs actual per scope (D-07) | Same, keyed by `tradeName` |
| Category mix (D-07) | `PieChart`+`Pie`+`Cell`+`Legend` — copy `quote-conversion-chart.tsx`, including its `label` and `formatter` shapes |

**Decimal-as-string boundary (critical, and easy to get wrong):** the API returns money as strings. `parseFloat` is permitted **only** to build the numeric array Recharts needs for geometry (`revenue-chart.tsx` sets the precedent: `paid: parseFloat(d.paid)`). Every *rendered* figure — tiles, tooltips, axis labels, CSV rows, attention rows — must format from the original string via `formatCurrency`/`formatSignedCurrency`/`formatMarginPercent`. Never re-sum money client-side; the portfolio totals come from the server.

**Null must stay null in the trend series.** `MarginSummary.revenue`/`margin` are `null` when no invoice or approved quote exists yet (Phase 33 D-07: "None expresses honest absence, never zero"). Map `null → null` in the chart datum, **not** `null → 0`. Recharts `Line` defaults to `connectNulls={false}`, which renders the gap correctly. Coercing to 0 fabricates a \$0 margin — the exact Pitfall 9 failure this whole milestone is built to avoid.

**Query keys:** put the new queries under the existing `["cost-entries", …]` prefix (e.g. `["cost-entries", "financials", "company"]`). `hooks.ts` documents this explicitly — `invalidateAllCostEntries` then refreshes the dashboard after any cost/budget/rate write, for free. The trend key includes the window: `["cost-entries", "financials", "trend", projectId, window]` so switching 3m→12m refetches only the trend (D-10), not the whole page.

---

### Pattern 6: Nav gating + route guard

**Nav item** — append to `navItems` in `web/src/components/layout/sidebar.tsx`, immediately after Reports:

```tsx
{ label: "Financials", href: "/financials", icon: Wallet, permission: "finance.view" },
```
The filter already handles it: `if (item.permission) return can(item.permission)`. `usePermissions().can()` returns **false while loading**, so the item never flashes. `isActive` uses `pathname.startsWith(href)` — `/financials` collides with nothing.

**Route guard** — the established pattern in this codebase is **not** a redirect or a 404. `contracts/page.tsx` and `settings/roles/page.tsx` both do: `usePermissions()` → pulsing skeleton while `isLoading` → an amber "You do not have permission to…" panel otherwise. D-04 says "consistent with existing permission-gated routes", so **match that, do not introduce middleware or `notFound()`**.

Because the pattern now appears in three-plus places, extract it once (CLAUDE.md DRY) and mount it at **`app/(dashboard)/financials/layout.tsx`** so a single component guards `/financials` *and* `/financials/[projectId]`:

```tsx
export default function FinancialsLayout({ children }: { children: React.ReactNode }) {
  return <FinanceGate>{children}</FinanceGate>;
}
```

**And gate the fetches, not just the render:** every new hook takes `enabled: can("finance.view")`. This is what makes the SC3 test assert something real — an unauthorized visit issues **zero** requests to `/api/v1/financials/*`, which Playwright can count. Render-only gating would still fire the request (and get a correct 403 — the backend is the real guard — but the assertion would be weaker).

**Defense in depth is already there:** `require_permission("finance.view")` returns `403 {"detail": "Missing permission: finance.view"}`. Per `app/core/permissions.py`, `finance.*` is granted to `owner`/`project_manager` and **deliberately excluded from `admin`** (`_FINANCE_ONLY_KEYS` subtraction, Phase 30) — so an admin token is the correct negative fixture (`_admin_headers` in `test_phase_34_e2e.py`).

---

### Anti-patterns to avoid

- **Calling `rollup_for_project` (or `trade_scope_cost_breakdown`) in a loop.** The whole phase fails here. It is a CLAUDE.md violation and the D-03 test exists to catch it.
- **Client-side fan-out.** `projects.map(p => useProjectCostRollup(p.id))` is the same N+1 moved across the wire.
- **Re-implementing threshold or margin math.** `crossed_thresholds`, `percent_used`, `summarize_margin`, `margin_percent_for`, `combine_revenue_bases`, `missing_cost_data` all exist and are tested. Import them.
- **Duplicating the effective-dated rate rule in SQL.** Phase 32 states the rule lives in exactly one place.
- **Excluding incomplete-data projects from portfolio totals.** D-09 forbids it; PITFALLS #9 explains why.
- **Modifying the Reports page.** Phase 30 D-06 boundary — the only permitted change is the sibling nav entry.
- **Adding a snapshot/cache table.** Explicitly deferred; only reopens if the D-03 test fails.
- **Filtering records by the trend window.** The window filters returned buckets only.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Per-anchor revenue resolution (invoices supersede quotes) | A new "revenue at date" resolver | `_anchor_revenues` + `_combined_anchor_revenue` (`finance/service.py`) with a date-filtered input list | D-01/Pitfall-2 semantics (never summed, never max()ed) are already encoded and tested |
| Labor cost from tracked time | Rate lookup in SQL or a second resolver | `summarize_labor` / `resolve_rate_row_for_work_date` / `session_labor_cost` (`labor_derivation.py`) | Effective-dated bisect + per-session cent quantization + unrated-seconds accounting; single source of the rule |
| Work-day derivation | `clocked_in_at.date()` | `work_date_for(clocked_in_at)` | Raises on naive datetimes; enforces the UTC convention |
| Margin %, incomplete flags, basis strings | Client-side `margin/revenue*100` | `summarize_margin`, `margin_percent_for`, `combine_revenue_bases` | ROUND_HALF_UP at one decimal; `mixed`/`none` basis rules |
| Budget threshold classification | `if percent >= 80` | `budget_math.crossed_thresholds(spent, total)` + `percent_used` | Ratio constants live in one place; 34-04/34-05 shipped a subtle `remaining > 0` nuance already |
| Scope spend for many scopes | A loop of `trade_scope_spend` | `BudgetRepository.scope_spends([ids])` | One grouped query, already pinned to `trade_scope_spend` by a named equivalence test |
| Money display | `toFixed`/`toLocaleString` inline | `formatCurrency`, `formatSignedCurrency`, `formatMarginDollars`, `formatMarginPercent` | Negative money renders sign-before-symbol (33-04); no thousands separators (34-04) |
| Honesty chip | A new amber span | `FinanceFlagChip` | 33-04 exists so the chip recipe cannot drift |
| Permission gate + deny panel | A new inline check per page | One extracted `FinanceGate` in `financials/layout.tsx` | Third occurrence of the pattern; DRY |
| CSV export from a chart card | A bespoke download handler | `ChartCard`'s built-in `csvRows`/`csvFilename` | Already implemented and accessible-labelled |
| Charting | Any new chart library | Recharts 3.8 | Installed, used by all 4 Reports charts |

**Key insight:** this phase's correctness comes almost entirely from *not writing math*. The only genuinely new logic is (a) which records fall in which bucket and (b) how tiers are ordered. Everything else is composition.

---

## Common Pitfalls

### Pitfall 1: The batched path silently drifts from the shipped per-project path
**What goes wrong:** the company overview says project X has \$40,120 cost; opening the drill-down (or the mobile rollup) says \$40,080. Both look plausible; nobody notices for weeks.
**Why:** two independent traversals of the same dual-outerjoin/labor-folding logic — legacy `labor`-category folding (`_build_breakdown`), soft-delete predicates, per-session vs per-total quantization, the D-14 fallback rule. Any one of them is easy to reproduce *almost* correctly.
**How to avoid:** the Phase 34 precedent, verbatim — write a named equivalence test asserting the batched company rollup's per-project figures are **exactly equal** to `FinanceService.rollup_for_project`'s for the same seeded project (including a soft-deleted cost entry, a legacy `labor`-category entry, an unrated session, and a scope with a quote but no invoice). Reference the test by name in the batched method's docstring, exactly as `scope_spends` does.
**Warning signs:** a figure differing by cents (quantization drift) or by exactly one entry's amount (soft-delete predicate missing).

### Pitfall 2: The trend window filters records instead of buckets
**What goes wrong:** the 3m view shows a cumulative margin of \$4k while the 12m view shows \$61k for the same month. Both cannot be right; the chart is meaningless.
**Why:** `WHERE incurred_date >= window_start` reads like the obvious optimization.
**How to avoid:** state it in the docstring and enforce it with a test: **for any month present in two different windows, the bucket values must be identical.** The window slices the output array, nothing else. Cumulative always runs from project inception.
**Warning signs:** the first bucket of a narrow window starts near zero.

### Pitfall 3: Coercing `null` revenue/margin to `0` in the chart
**What goes wrong:** early project months plot a flat \$0 margin line, which reads as "we broke even" instead of "no revenue recorded yet" — precisely PITFALLS #9's fabricated-figure failure at chart scale.
**Why:** `parseFloat(null)` → `NaN`, and the reflexive fix is `?? 0`.
**How to avoid:** map `string | null → number | null`; leave Recharts' `connectNulls` at its `false` default. Assert a test datum with `revenue: null` renders no point.
**Warning signs:** a trend line that begins at exactly \$0.00 for a project whose first invoice is months in.

### Pitfall 4: Approved quotes with `approved_at IS NULL`
**What goes wrong:** an approved quote contributes to the all-time rollup revenue but has no date, so it never enters any bucket — the final trend bucket disagrees with the tiles on the same page.
**Why:** `Quote.approved_at` is nullable. `QuoteService` sets it on the approve path and Phase 33's raw-SQL fixture sets it, but nothing in the schema *requires* status `approved` ⇒ `approved_at` non-null, and legacy/imported rows may violate it.
**How to avoid:** use `COALESCE(approved_at, created_at)` for bucketing, document the fallback in the module docstring, and seed a test quote with `status='approved', approved_at=NULL` asserting the final bucket still reconciles with `rollup_for_project`. (Do **not** exclude such quotes — that breaks reconciliation, which is the trend's only self-check.)
**Warning signs:** last bucket revenue < rollup revenue by exactly one quote's amount.

### Pitfall 5: `warning_fired_at`/`overrun_fired_at` used as live state
**What goes wrong:** a project shows a 130%-over bar in the chart but is absent from the attention list (or vice versa).
**Why:** those columns are the exactly-once alert claim. `set_total` nulls both on a raise (D-03 re-arm); a claim persists after spend drops via soft-delete.
**How to avoid:** derive tiers from `crossed_thresholds(spent, total)` on the same `spent` the bars render. Test: raise a budget above an overrun spend and assert the project still appears in the overrun tier despite `overrun_fired_at IS NULL`.
**Warning signs:** attention list and budget bars disagree on any project.

### Pitfall 6: Playwright direct-URL denial is a false green
**What goes wrong:** `page.goto("/financials")` shows the deny panel for a *permitted* user too, because a hard navigation resets Redux — `isAuthenticated` is set only by the login page (32-04 lesson), so `usePermissions`'s query is `enabled: false`, `can()` is false, and the gate denies. The test passes for the wrong reason and would keep passing even if the gate were deleted.
**Why:** auth state lives in Redux, hydrated only by the login flow.
**How to avoid:** split the assertion.
  - **Backend pytest is the real guard test:** all three endpoints return 403 `"Missing permission: finance.view"` for an `admin` token, plus RLS isolation (tenant B gets 404/empty for tenant A's project).
  - **Playwright asserts what only the browser can:** (a) with a finance permission set, log in through the UI and **SPA-navigate via the sidebar link** — dashboard renders; (b) with a non-finance permission set, log in through the UI and assert the Financials link is **absent**; (c) on a cold `page.goto("/financials")`, assert the deny panel renders **and zero `/api/proxy?path=/api/v1/financials/*` requests were captured** — proving no financial data is ever fetched or painted before permissions are known.
Add a code comment stating why (c) is phrased that way, so a future reader does not "fix" it into a false green.
**Warning signs:** a route-guard test that passes when the guard component is commented out.

### Pitfall 7: `GROUP BY` omission on the coalesced project key
**What goes wrong:** `column "trade_scopes.project_id" must appear in the GROUP BY clause` — or worse, on a variant that PostgreSQL accepts, silently wrong grouping.
**Why:** functional dependency on a grouped PK only covers columns of *that* table.
**How to avoid:** add `COALESCE(TradeScope.project_id, Job.project_id)` to both `select()` and `group_by()`.

### Pitfall 8: `BaseRepository.list_all()` does not filter `deleted_at`
**What goes wrong:** soft-deleted projects, cost entries or budgets appear in portfolio totals.
**Why:** documented Phase 31 pitfall; the base class genuinely does not filter.
**How to avoid:** every new query states `.where(X.deleted_at.is_(None))` explicitly. Test with a soft-deleted project and a soft-deleted cost entry.

### Pitfall 9: Wall-clock assertions that flake or that have no teeth
**What goes wrong:** either CI goes red on unrelated load, or the budget is so generous that a reintroduced N+1 still passes.
**How to avoid:** two assertions (see §Validation Architecture) — a deterministic **query-count invariant** as the primary regression guard, and a generous **wall-clock ceiling** as the D-03 evidence. Discard a warm-up request before timing; use the median of ≥5 runs, never a single sample.

### Pitfall 10: Sending `entries[]` to a chart page
**What goes wrong:** the drill-down downloads every itemized cost entry (unbounded) to draw a pie chart.
**Why:** reusing `GET /projects/{id}/cost-entries` looks like free reuse.
**How to avoid:** the new `/projects/{id}/financials` response carries aggregates only — categories, labor, margin, project budget, `scopes[]`. No `entries`.

---

## Code Examples

### Batched project-keyed cost aggregate (Pattern 1, query #2)

```python
# Source: composed from backend/app/features/finance/repository.py
#   rollup_for_project (dual-outerjoin traversal) + _category_totals_where (GROUP BY shape)
_PROJECT_KEY = func.coalesce(TradeScope.project_id, Job.project_id).label("project_id")

async def category_totals_by_project(self) -> list[Row]:
    """Per-(project, anchor, category) cost sums for the whole tenant, in ONE round trip.

    Same D-12 traversal as rollup_for_project so mixed job/scope records net out with
    the revenue side. Pinned to rollup_for_project by
    test_company_rollup_matches_rollup_for_project (Pitfall 1).
    """
    result = await self.db.execute(
        select(
            _PROJECT_KEY,
            CostEntry.job_id,
            CostEntry.trade_scope_id,
            CostCategory.id,
            CostCategory.name,
            func.sum(CostEntry.amount),
        )
        .select_from(CostEntry)
        .join(CostCategory, CostEntry.category_id == CostCategory.id)
        .outerjoin(TradeScope, CostEntry.trade_scope_id == TradeScope.id)
        .outerjoin(Job, CostEntry.job_id == Job.id)
        .where(CostEntry.deleted_at.is_(None), _PROJECT_KEY.is_not(None))
        .group_by(
            _PROJECT_KEY,
            CostEntry.job_id,
            CostEntry.trade_scope_id,
            CostCategory.id,
            CostCategory.name,
        )
    )
    return list(result.all())
```

### As-of revenue replay at a bucket edge (Pattern 2)

```python
# Source: reuses backend/app/features/finance/service.py::_anchor_revenues /
#   _combined_anchor_revenue unchanged — only the input lists are date-filtered.
def revenue_at(edge: date, documents: DatedDocuments) -> ResolvedRevenue | None:
    """Project revenue as Phase 33 D-01 would have resolved it on `edge`."""
    invoices = [(a, d) for a, d, issued in documents.invoices if issued <= edge]
    quotes = [(a, d) for a, d, approved in documents.quotes if approved <= edge]
    return _combined_anchor_revenue(_anchor_revenues(invoices, quotes))
```

### Existing permission-gate pattern to extract (Pattern 6)

```tsx
// Source: web/src/app/(dashboard)/settings/roles/page.tsx (identical shape in contracts/page.tsx)
const { can, isLoading } = usePermissions();
if (isLoading) return <div className="h-64 animate-pulse rounded-lg bg-muted" />;
if (!can("roles.permissions.manage")) {
  return (
    <div className="rounded-xl border border-yellow-200 bg-yellow-50 px-6 py-12 text-center">
      <p className="text-sm font-medium text-yellow-700">
        You do not have permission to edit role permissions.
      </p>
    </div>
  );
}
```

### Playwright recipe (Pitfall 6)

```ts
// Source: web/tests/phase-34-budgets.spec.ts — the shipped recipe
async function seedAuth(page: Page) {
  await page.context().addCookies([
    { name: "access_token", value: "mock-token", domain: "localhost", path: "/" },
  ]);
  await page.route("**/api/auth/login", (route) => route.fulfill({ json: { /* user */ } }));
}
// Route matching: most-specific-first; `path` comes from the proxy query param
const path = new URL(route.request().url()).searchParams.get("path") ?? "";
// Always log in through the UI, then SPA-navigate by clicking the sidebar link
async function loginThroughUi(page: Page) {
  await page.goto("/login");
  await page.getByLabel(/email/i).fill("sarah@ace.com");
  await page.locator("#password").fill("password123");
  await page.getByRole("button", { name: /sign in|log in/i }).click();
  await page.waitForURL("http://localhost:3000/");
}
```

### Backend E2E fixtures (from `test_phase_34_e2e.py`)

```python
_pm_headers(company_id)     # project_manager -> HAS finance.view + finance.manage
_admin_headers(company_id)  # admin -> deliberately EXCLUDED from finance.* (Phase 30)
# Approving a quote in fixtures uses raw SQL, never POST /quotes/{id}/approve
# (the endpoint demands sent/viewed transitions and creates jobs) — 33-02 lesson:
"UPDATE quotes SET status = 'approved', approved_at = now() WHERE id = CAST(:quote_id AS uuid)"
```

---

## State of the Art

| Old approach | Current approach | When changed | Impact |
|---|---|---|---|
| Recharts 2.x `Customized` for custom elements; `recharts-scale`/`react-smooth` deps | Recharts 3.x renders arbitrary elements anywhere; scale/animation vendored in; `Tooltip` gains a `portal` prop | 3.0 (repo is on 3.8.0) | No migration work — all 4 shipped charts already run on 3.8. `LineChart` is the same cartesian family as the working `AreaChart`/`BarChart`. |
| Mutable hourly rate column | Effective-dated `labor_rates` table | Phase 32 | Historical margins are reproducible; the trend can honestly cost a session at the rate in force on its work day |
| Ad-hoc margin math in endpoints | DB-free `margin_math` / `budget_math` / `labor_derivation` modules | Phases 32–34 | Phase 35's new pure modules follow this exact layout |
| Per-budget SUM in the nightly sweep | `BudgetRepository.scope_spends([ids])`, one grouped query | Phase 34 | The batching template — and the equivalence-test precedent |

**Deprecated/outdated:** nothing in this phase's dependency surface.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|---|---|---|---|---|
| Node.js | Next.js dev server, jest, Playwright | ✓ | v20.18.1 | — |
| npm | web tooling | ✓ | 10.8.2 | — |
| Python venv (backend) | pytest, FastAPI, PEP 695 generics | ✓ | 3.12.12 (`backend/.venv`) | — |
| PostgreSQL | `contractorhub_test` (conftest force-selects + migrates) | ✓ | accepting connections on :5432 | — |
| Docker | `docker compose up migrate` for the local dev DB | ✓ | running | — |
| Recharts 3.8.0 | all four charts | ✓ | 3.8.0 in `web/node_modules` | — |
| `web/node_modules` | jest/Playwright/tsc | ✓ | present | — |
| Playwright browsers | `npm run test-e2e` | ⚠ not verified | — | `npx playwright install chromium` if the first run fails |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** Playwright browser binaries — install on demand.

> Note: system `python3` is 3.9.6, which cannot parse this repo's PEP 695 syntax. All backend commands must use `backend/.venv` (`cd backend && source .venv/bin/activate`), as the e2e-feature-tests skill already documents.

---

## Validation Architecture

### Test Framework

| Property | Value |
|---|---|
| Backend framework | pytest + pytest-asyncio + httpx `AsyncClient` (real `contractorhub_test` DB) |
| Backend config | `backend/tests/conftest.py` (forces `DATABASE_URL`, runs `alembic upgrade head`, `clean_tables` autouse) |
| Backend quick run | `cd backend && source .venv/bin/activate && python -m pytest tests/test_phase_35_e2e.py -q` |
| Backend full suite | `cd backend && source .venv/bin/activate && python -m pytest -q` (slow, ~25 min) |
| Web unit framework | jest 30 + ts-jest + jsdom + @testing-library/react; `jest.config.ts`; matches `src/**/__tests__/**/*.test.tsx` |
| Web unit quick run | `cd web && npx jest src/features/finance` |
| Web unit full | `cd web && npm test` |
| Web E2E framework | Playwright 1.58 (`playwright.config.ts`, chromium project, `webServer: npm run dev`) |
| Web E2E quick run | `cd web && npx playwright test tests/phase-35-financials.spec.ts` |
| Web E2E full | `cd web && npm run test-e2e` |
| Static gates | `cd web && npm run lint && npx tsc --noEmit`; `cd backend && ruff check . && ruff format --check .` |

### Phase Requirements → Test Map

| Req | Behavior | Type | Automated command | File exists? |
|---|---|---|---|---|
| MARG-04 / SC1 | Trend endpoint returns dense monthly buckets; final bucket **equals** `rollup_for_project`'s margin block | integration | `pytest tests/test_phase_35_e2e.py::test_trend_final_bucket_reconciles_with_project_rollup -x` | ❌ Wave 0 |
| MARG-04 / SC1 | Same month has identical values across 3m / 12m / all windows (Pitfall 2) | integration | `pytest tests/test_phase_35_e2e.py::test_trend_window_slices_buckets_not_records -x` | ❌ Wave 0 |
| MARG-04 / SC1 | Approved quote with `approved_at IS NULL` still reconciles (Pitfall 4) | integration | `pytest tests/test_phase_35_e2e.py::test_trend_quote_without_approved_at_uses_created_at -x` | ❌ Wave 0 |
| MARG-04 / SC1 | Months with no activity carry forward cumulative values (dense buckets) | integration | `pytest tests/test_phase_35_e2e.py::test_trend_buckets_are_dense -x` | ❌ Wave 0 |
| MARG-04 / SC1 | Pre-revenue buckets return `revenue=null`, `margin=null`, `basis="none"` | integration | `pytest tests/test_phase_35_e2e.py::test_trend_absent_revenue_is_null_not_zero -x` | ❌ Wave 0 |
| MARG-04 / SC1 | Drill-down returns per-scope budget-vs-actual with `spent` matching `trade_scope_spend` | integration | `pytest tests/test_phase_35_e2e.py::test_project_financials_scope_budgets_match_scope_spend -x` | ❌ Wave 0 |
| MARG-04 / SC1 | Trend line renders gaps for null margin; no `$0` point | unit (jest) | `npx jest src/app/\(dashboard\)/financials` | ❌ Wave 0 |
| MARG-04 / SC2 | Company rollup per-project figures **equal** `rollup_for_project` (Pitfall 1) | integration | `pytest tests/test_phase_35_e2e.py::test_company_rollup_matches_rollup_for_project -x` | ❌ Wave 0 |
| MARG-04 / SC2 | Portfolio totals include incomplete-data projects; badge count == incomplete tier size (D-09) | integration | `pytest tests/test_phase_35_e2e.py::test_portfolio_totals_include_flagged_projects_with_count -x` | ❌ Wave 0 |
| MARG-04 / SC2 | Estimated (quote-basis) revenue share is surfaced; basis is `mixed` when both legs present | integration | `pytest tests/test_phase_35_e2e.py::test_portfolio_surfaces_quoted_revenue_share -x` | ❌ Wave 0 |
| MARG-04 / SC2 | Attention tiers ordered overrun(worst % first) → warning → incomplete (D-08) | integration | `pytest tests/test_phase_35_e2e.py::test_attention_list_tier_ordering -x` | ❌ Wave 0 |
| MARG-04 / SC2 | Overrun tier survives a budget raise that nulled `overrun_fired_at` (Pitfall 5) | integration | `pytest tests/test_phase_35_e2e.py::test_attention_tiers_use_live_threshold_state -x` | ❌ Wave 0 |
| MARG-04 / SC2 | Soft-deleted project / cost entry / budget excluded (Pitfall 8) | integration | `pytest tests/test_phase_35_e2e.py::test_company_rollup_excludes_soft_deleted -x` | ❌ Wave 0 |
| MARG-04 / SC2 | Company overview + drill-down render with Reports conventions (ChartCard aria-labels, skeleton, empty state) | e2e | `npx playwright test tests/phase-35-financials.spec.ts -g "renders"` | ❌ Wave 0 |
| **D-03** | **Query count is identical for a 5-project and a 25-project company** (primary N+1 guard) | integration | `pytest tests/test_phase_35_e2e.py::test_company_rollup_query_count_is_constant_in_project_count -x` | ❌ Wave 0 |
| **D-03** | **Company rollup median latency under budget at 25 projects / ~5,000 financial records** | integration | `pytest tests/test_phase_35_e2e.py::test_company_rollup_latency_budget -x` | ❌ Wave 0 |
| MARG-04 / SC3 | All three endpoints 403 for an `admin` token (no `finance.view`) | integration | `pytest tests/test_phase_35_e2e.py::test_financial_endpoints_forbidden_without_finance_view -x` | ❌ Wave 0 |
| MARG-04 / SC3 | Tenant B cannot read tenant A's project financials (RLS) | integration | `pytest tests/test_phase_35_e2e.py::test_project_financials_rls_isolation -x` | ❌ Wave 0 |
| MARG-04 / SC3 | Non-finance user sees **no** Financials nav item | e2e | `npx playwright test tests/phase-35-financials.spec.ts -g "nav item"` | ❌ Wave 0 |
| MARG-04 / SC3 | Direct `/financials` and `/financials/[id]` load → deny panel **and zero** `/api/v1/financials/*` proxy requests (Pitfall 6) | e2e | `npx playwright test tests/phase-35-financials.spec.ts -g "direct navigation"` | ❌ Wave 0 |
| MARG-04 / SC3 | Finance user sees the nav item and reaches both routes by SPA navigation | e2e | `npx playwright test tests/phase-35-financials.spec.ts -g "finance user"` | ❌ Wave 0 |
| Regression | Reports page untouched (Phase 30 D-06) | e2e | `npx playwright test tests/phase-18-reports.spec.ts` | ✅ exists |
| Regression | Phase 33/34 finance surfaces unchanged | integration + e2e | `pytest tests/test_phase_33_e2e.py tests/test_phase_34_e2e.py -q`; `npx playwright test tests/phase-33-margin.spec.ts tests/phase-34-budgets.spec.ts` | ✅ exists |

### Recommended latency budget (D-03 — state this number in the plan)

**Seed:** one company with **25 projects**, each with 4 trade scopes, 2 jobs, 20 cost entries, 50 completed time entries, 2 invoices and 2 approved quotes, plus 25 project budgets and 100 scope budgets ≈ **5,000 financial records**.

**Two assertions, both required:**

1. **Query-count invariant (primary, deterministic, never flakes).** Count SQL statements with a SQLAlchemy `before_cursor_execute` event listener around one `GET /financials/company` call. Assert the count for a 25-project company **equals** the count for a 5-project company (expected ~8–9). This is the actual N+1 guarantee; a wall-clock number alone cannot enforce it.
2. **Wall-clock ceiling (the D-03 evidence).** Discard one warm-up request, then time 5 requests and assert the **median < 1500 ms**. Rationale: the endpoint is a constant ~8 queries whose cost is dominated by Python `Decimal` aggregation over ~5,000 rows; local measurements should land well under this, while a reintroduced per-project loop (25 × 7 = 175 round trips) blows straight through it. 1500 ms is deliberately generous so shared CI hardware does not produce red builds on unrelated load.

**Follow-up rule to state in the plan:** if the first measured median is ≪ 1500 ms (e.g. under 300 ms), tighten the committed ceiling to ~2× the measured median so the test retains teeth. If the median exceeds 1500 ms, D-03 says the cache/snapshot decision **reopens as a follow-up** — it is not silently added in this phase.

**Honest caveat to record with the result:** an in-process ASGI + local-Postgres measurement is evidence that computed-on-read does not blow up at this data scale; it is not a production SLO.

### Sampling rate

- **Per task commit:** `cd backend && source .venv/bin/activate && python -m pytest tests/test_phase_35_e2e.py -q` and/or `cd web && npx jest src/features/finance src/app/\(dashboard\)/financials`
- **Per wave merge:** `pytest tests/test_phase_3{3,4,5}_e2e.py -q` + `npm test` + `npm run lint && npx tsc --noEmit`
- **Phase gate:** full backend suite green, `npm test` green, `npm run test-e2e` green, ruff clean — before `/gsd:verify-work`

### Wave 0 gaps

- [ ] `backend/tests/test_phase_35_e2e.py` — covers MARG-04 (all backend rows above). Reuse the `test_phase_34_e2e.py` helper set (`_seed_cost_categories`, `_create_project`, `_create_trade_scope`, `_create_job`, `_create_budget`, `_add_cost_entry`, `_post_rate`, `_seed_time_entry`, `_pm_headers`, `_admin_headers`) — they drive real endpoints, not raw SQL, and are explicitly written to be reused by later phases.
- [ ] A multi-project seeding helper (`_seed_company_portfolio(project_count, …)`) for the two D-03 tests — new; the largest single piece of test scaffolding in the phase.
- [ ] A query-counting context manager (`_count_sql_statements()`) using `sqlalchemy.event.listen(engine.sync_engine, "before_cursor_execute", …)` — **no precedent exists in this repo**; write it in Wave 0.
- [ ] `web/tests/phase-35-financials.spec.ts` — SC3 keystone + render specs. Template: `web/tests/phase-34-budgets.spec.ts`.
- [ ] `web/src/features/finance/__tests__/financials-*.test.tsx` — pure-mapping and null-handling unit tests (existing `__tests__` dir, jest already configured).
- [ ] Backend pure-math unit tests for `trend_math.py` / `portfolio_math.py` — no DB, F.I.R.S.T., mirroring how `margin_math`/`budget_math` are tested.
- [ ] No framework installation needed.

---

## Open Questions

1. **Attention tiers: live threshold state vs. `warning_fired_at`/`overrun_fired_at`.**
   - What we know: the phase brief names the fired-timestamp columns as the tier source; D-08 requires ranking overruns by "worst % over", which needs live `percent_used`.
   - What's unclear: whether the user intends the attention list to mean "budgets currently over" or "budgets that have alerted".
   - Recommendation: **live state** via `crossed_thresholds(spent, total)`, so the list can never contradict the budget bars on the same screen (the fired columns are re-armed to NULL on a budget raise and persist after a spend drop). Optionally surface `alerted_at` as row metadata. Flag this in the plan as a deliberate, documented reading of D-08 — it is a 2-line change if the user prefers otherwise.

2. **Do draft / archived projects appear in the portfolio?**
   - What we know: `projects.status ∈ draft|planning|active|on_hold|complete|archived`. D-09's honesty posture says never exclude; but an archived project's costs arguably do not belong in "current portfolio health".
   - Recommendation: include **all** non-soft-deleted projects (D-09 literal reading), return `status` per project row so the UI can group or de-emphasize, and defer any filtering to a UI-SPEC decision. Do not filter server-side without an explicit decision.

3. **Endpoint path shape.** `/api/v1/financials/company` vs `/api/v1/company/financials` vs `/api/v1/financials/`. No convention forces one. Recommendation: `GET /financials/company`, `GET /projects/{id}/financials`, `GET /projects/{id}/financials/trend` — reads well, keeps the project-scoped pair under the existing `/projects/{id}/…` family that `finance/router.py` already uses.

4. **Does the trend endpoint also serve the drill-down's revenue/cost tiles?** The final trend bucket equals the rollup by construction, so the drill-down *could* read tiles from the last bucket. Recommendation: **don't** — keep the window-independent figures on `/projects/{id}/financials` (D-10 says only the trend is windowed) so a window change never restates the headline numbers. Two endpoints, two query keys.

5. **Recharts vertical `BarChart` label truncation with 25 project names.** Not investigated in depth. Likely needs `YAxis width={…}` plus a truncating `tickFormatter`, or a scrollable container. Low risk, resolve during the UI-SPEC pass.

---

## Sources

### Primary (HIGH confidence — read directly this session)
- `backend/app/features/finance/{repository,service,router,schemas,models,margin_math,budget_math,budget_service,budget_repository,labor_derivation}.py` — full read; the traversal, math, gating and round-trip budgets quoted above come from these files
- `backend/app/features/reports/service.py` — existing monthly bucketing precedent (`func.to_char(Invoice.issued_at, 'YYYY-MM')`)
- `backend/app/core/permissions.py` — `finance.*` role grants; admin exclusion via `_FINANCE_ONLY_KEYS`
- `backend/app/core/security.py::require_permission` — 403 shape
- `backend/app/features/{invoices,quotes,projects}/models.py` — `Invoice.issued_at` (NOT NULL), `Quote.approved_at` (nullable), project status CHECK
- `backend/migrations/versions/{0009,0015,0021,0023,0030,0032,0035}_*.py` — the exact index inventory
- `backend/tests/{conftest.py,test_phase_33_e2e.py,test_phase_34_e2e.py}` — fixtures, quote-approval SQL, helper set
- `web/src/app/(dashboard)/reports/**` — ChartCard/RevenueChart/JobsByStatusChart/QuoteConversionChart/DateRangeFilter/ReportsSkeleton/ReportsDashboard APIs and conventions
- `web/src/components/layout/sidebar.tsx`, `web/src/lib/hooks/usePermissions.ts` — nav gating mechanism
- `web/src/app/(dashboard)/{contracts,settings/roles}/page.tsx` — the shipped route-guard pattern
- `web/src/features/finance/{types,api,hooks}.ts` + `components/{MarginSummarySection,FinanceFlagChip}.tsx` — extension points and formatters
- `web/src/lib/{format.ts,api-client.ts}`, `web/package.json`, `web/node_modules/recharts/package.json` (3.8.0), `jest.config.ts`, `playwright.config.ts`
- `web/tests/phase-34-budgets.spec.ts` — the Playwright recipe including the 32-04 login-through-UI lesson
- `.planning/phases/35-web-financial-dashboard/{35-CONTEXT.md,35-DISCUSSION-LOG.md}`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`, `.planning/research/PITFALLS.md`, `.planning/config.json`
- `CLAUDE.md`, `~/.agents/skills/clean-code/SKILL.md`, `.claude/skills/e2e-feature-tests/SKILL.md`

### Secondary (MEDIUM confidence)
- [Recharts 3.0 migration guide](https://github.com/recharts/recharts/wiki/3.0-migration-guide) — state-management rewrite, `Customized` no longer needed, `recharts-scale`/`react-smooth` vendored, `Tooltip` `portal` prop. Cross-checked against the repo's four working 3.8 charts.

### Tertiary (LOW confidence — flagged for validation)
- The **1500 ms** median latency ceiling is an engineering judgement, not a measurement. It is deliberately generous. The plan must record the first measured median and tighten accordingly (§Validation Architecture).
- Vertical-`BarChart` label handling at 25 rows (Open Question 5) is untested.

---

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** — zero new dependencies; every version read from `package.json`/`node_modules`/the venv
- Architecture (batching, trend semantics, endpoint shapes): **HIGH** — derived from directly-read shipped code, with the Phase 34 equivalence-test precedent as the drift guard
- Web composition & conventions: **HIGH** — every API quoted from the actual component source
- Pitfalls: **HIGH** for 1–8 and 10 (each traces to a documented Phase 31–34 lesson or a read code path); **MEDIUM** for 9 (latency-test flakiness is judgement)
- Latency budget number: **LOW→MEDIUM** — reasoned, not measured; explicitly designed to be tightened after the first run
- Attention-tier source (Pitfall 5 / Open Question 1): **HIGH** on the mechanism, **MEDIUM** on intent — flagged for the planner

**Research date:** 2026-07-28
**Valid until:** 2026-08-27 (30 days — internal codebase, stable dependencies; re-verify only if Recharts or Next.js is upgraded)
