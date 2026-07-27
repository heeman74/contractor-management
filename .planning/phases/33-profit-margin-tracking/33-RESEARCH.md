# Phase 33: Profit Margin Tracking - Research

**Researched:** 2026-07-27
**Domain:** Margin computation (revenue − actual cost) over the existing FastAPI/SQLAlchemy finance stack + React/TanStack Query web + Flutter/Riverpod mobile
**Confidence:** HIGH (grounded in direct inspection of the shipped Phase 25/30/31/32 code this phase extends)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Revenue definition**
- **D-01:** **Invoices, else approved quote.** Revenue for a job/scope = sum of its invoice totals; if no invoice exists yet, fall back to the approved quote total. Once ANY invoice exists, invoices win outright (no mixing, no max()). Per research PITFALLS.md #3: quote line items NEVER count as cost, and invoice line items never feed the cost side.
- **D-02:** **All issued invoices count** — unpaid + partially_paid + paid (billed/accrual basis). Margin reflects job economics, not collections.
- **D-03:** **Approved quotes only** qualify for the fallback. Draft/sent/viewed are proposals; declined/expired are dead; revised quotes were superseded.
- **D-04:** **Quote-based margin is visibly labeled** with a caption to the effect of "Based on approved quote — not yet invoiced". Invoice-backed margin carries no label. Phase 36's AI must receive this estimated-vs-billed distinction with the margin data.

**Incomplete-data flag (success criterion 3)**
- **D-05:** The flag triggers on exactly two conditions:
  1. **Unrated labor hours** — tracked time with no effective rate on the work day (reuse Phase 32's unrated-seconds signal from the breakdown API).
  2. **Zero cost entries + zero derived labor while revenue exists** — the research Pitfall 9 legacy case, which would otherwise fabricate a ~100% margin.
- **D-06:** **Partial number + flag.** When flagged, the margin computed from available data still displays, with the incomplete-data flag beside it — matching the Phase 32 pattern of rated-labor totals + "N hrs unrated" chip. Never suppress the number, never show an unflagged fabricated one.
- **D-07:** **No revenue source (no invoice AND no approved quote) is NOT an incomplete-data flag.** In that case the margin figure is simply absent — costs display as they already do, with a neutral "no revenue recorded"-style note instead of a margin (exact copy: Claude's discretion). The flag means "cost data quality problem", not "billing hasn't started".

**Presentation**
- **D-08:** **Margin extends the existing Costs sections** on job detail, trade-scope detail, and project screens — the same finance-gated surfaces Phases 31/32 built. No separate Margin card, no new nav. Both **web and mobile**, matching the established platform pattern.
- **D-09:** **Both $ and %** displayed together (e.g. "$4,200 · 21%"). Margin dollars = revenue − cost; percentage = margin / revenue.
- **D-10:** Margins are gated by `finance.view` (carried from Phase 30 D-06: finance.* gates margins; revenue surfaces themselves — quotes, invoices, reports — stay ungated as today). Mobile fetches margin via API like the Phase 32 breakdown; no rate or margin data persisted to Drift.

**Compute strategy**
- **D-11:** **Computed-on-read.** Margin derives at query time from the shipped breakdown/derivation queries plus bounded revenue queries — same posture as Phase 32 labor derivation. No denormalized margin table, no invalidation machinery. Revisit caching in Phase 35 if dashboard latency demands it (research suggests the threshold is hundreds of rows per project).

**Project rollup**
- **D-12:** Project margin rollup follows the Phase 30 D-05 traversal: revenue and cost from trade-scope-anchored records + records on jobs where `job.project_id` = project. Per research PITFALLS.md #1 mitigation, revenue and cost MUST resolve through the same traversal so mixed job/scope records net out correctly — one integration test must assert this explicitly. Project-level incomplete flag = any contributing job/scope is flagged.

### Claude's Discretion
- Exact API shape (extend the Phase 32 breakdown endpoints/response vs sibling margin endpoints); Decimal-as-string serialization per convention.
- Percentage precision/rounding and division-by-zero handling (zero revenue).
- Exact flag/label/no-revenue copy and visual treatment (follow the Phase 32 UI-SPEC conventions: chips/captions, no destructive red for informational flags) — a Phase 33 UI-SPEC pass will lock the strings.
- How the estimated-vs-billed revenue basis is represented in API responses (e.g. a `revenue_basis: invoiced | quoted` field) for UI labels and Phase 36.
- Bounded-query design for revenue aggregation (no N+1 per CLAUDE.md).

### Deferred Ideas (OUT OF SCOPE)
- Denormalized/cached margin summaries — revisit in Phase 35 if dashboard latency demands it (D-11)
- Cash-basis (paid-only) margin view — not selected; could be a future toggle if collections visibility is ever requested
- None other — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MARG-01 | Owner/PM can see profit margin (revenue − actual costs) per job/trade scope | Revenue aggregation design (Pattern 1), margin math (Pattern 3), additive `margin` block on the existing job/scope breakdown endpoints (Pattern 2), web+mobile margin row (Patterns 6/7) |
| MARG-02 | Owner/PM can see project-level margin rollup across trades | Same-traversal project revenue query mirroring `FinanceRepository.rollup_for_project` (Pattern 1b), additive `margin` on `ProjectCostRollupResponse` (Pattern 2), Pitfall-1 same-traversal integration test (Code Examples) |
| MARG-03 | Margin views flag incomplete cost data (legacy jobs, missing rates) instead of showing misleading numbers | D-05 flag derivation from `LaborCostSummary.unrated_seconds` + per-anchor zero-cost detection (Pattern 4), keystone legacy-job test (Code Examples), chip/caption UI per Phase 32 conventions |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **N+1 prevention:** never query in a loop; `selectinload`/`joinedload` for related data; models use `lazy="raise"` (Invoice/Quote relationships WILL raise on accidental lazy access — select columns or eager-load explicitly).
- **OOP architecture:** new logic goes in class methods on `FinanceService`/`FinanceRepository` (already inherit `TenantScopedService`/`TenantScopedRepository`); no standalone service functions. Pure math helpers module-level in `labor_derivation.py`-style DB-free modules is the established, accepted pattern (Phase 32 precedent).
- **No `db.commit()` in services** — `get_db` handles it. This phase is read-only anyway.
- **Routers thin, delegate to service; `require_permission("finance.view")` inline** (house style: `await require_permission("finance.view")(current_user, db)`).
- **Clean code:** intention-revealing names, ~20-line functions, no magic numbers (named constants like `CENTS`, `ZERO_MONEY` already exist — reuse), DRY (extract shared invoice/quote total math instead of a third copy), 0–2 function args preferred.
- **Mobile type safety:** no bare `as` casts; `is` checks + `FormatException`; `whereType<T>()` — the `tryFromJson` pattern in `cost_breakdown.dart` is the template.
- **Money discipline:** Decimal end-to-end backend; Decimal-as-string over the wire; mobile/web display strings verbatim, never re-sum with double (PITFALLS.md #10).
- **Testing:** every new service method/endpoint gets tests; phase E2E required — `backend/tests/test_phase_33_e2e.py`, `mobile/test/e2e/phase_33_*_e2e_test.dart`, web Playwright in `web/tests/`. Run `pytest`, `flutter test`, `npm run lint` + `npx tsc --noEmit`, `dart analyze`, `ruff check`/`ruff format` before committing.
- **Prefer editing existing files** — this phase is almost entirely additive edits to shipped finance files.

## Summary

Phase 33 adds the revenue side of the margin equation to a cost side that is already complete and battle-tested. Phase 32 shipped `CostBreakdownResponse` (category totals + derived labor + `unrated_seconds` + `grand_total`) for jobs, trade scopes, and projects, all `finance.view`-gated, all computed-on-read with bounded queries. This phase needs: (1) bounded revenue aggregation over `Invoice`/`Quote` per anchor and per project via the same D-12 traversal the cost side uses, (2) pure Decimal margin math with an incomplete-data flag derived from existing signals, (3) an additive `margin` block on the existing breakdown/rollup responses, and (4) a margin row extending `CostBreakdownSummary` on web and mobile.

The single most important discovery: **neither `Invoice` nor `Quote` stores a total.** Totals are computed at response time in `InvoiceResponse.from_orm_with_totals` / `QuoteResponse.from_orm_with_totals` (subtotal = Σ quantity × unit_price; discount percent/fixed applied to subtotal; tax on the discounted subtotal). Revenue aggregation must therefore either replicate this math in SQL or fetch per-invoice line-item subtotals plus invoice-level discount/tax fields and finish in Python with a shared pure helper — the recommended approach (Pattern 1). A second key discovery simplifies D-02: **invoices have no draft state** — the status check constraint is exactly `unpaid|partially_paid|paid` and `issued_at` is NOT NULL, so "all issued invoices" = all non-soft-deleted invoices; no status filter is needed on the revenue query.

A trap to avoid: the existing `InvoiceService.aggregate_by_project` looks like reusable revenue rollup but is **scope-anchored only** (misses job-anchored invoices) and **casts to `float`** — it violates both D-12 same-traversal and the Decimal policy. Build the margin revenue query fresh, mirroring `FinanceRepository.rollup_for_project`'s outerjoin traversal exactly.

**Primary recommendation:** Extend `CostBreakdownResponse` and `ProjectCostRollupResponse` additively with an optional `margin: MarginSummary | None` block (no new endpoints, no second network call, safe for mobile's strict-on-existing/tolerant-on-new parsing contract), computed in `FinanceService` from a new `RevenueRepository`-style set of bounded queries plus a DB-free `margin_math.py` module mirroring `labor_derivation.py`.

## Standard Stack

### Core (all existing — nothing new is installed this phase)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FastAPI + SQLAlchemy async | existing | breakdown endpoints extension | Phase 31/32 finance feature lives here |
| Python `decimal.Decimal` | stdlib | all margin math | `CENTS`, `ZERO_MONEY`, `ROUND_HALF_UP` already defined in `labor_derivation.py` — reuse, never redeclare |
| Pydantic v2 | existing | `MarginSummary` schema | `Decimal` fields auto-serialize as JSON strings (verified convention, `finance/schemas.py` docstring) |
| TanStack Query + existing finance hooks | existing | web data layer | breakdown hooks already keyed under `["cost-entries", ...]` prefix; margin rides the same responses, invalidation is free |
| Riverpod 3 providers (`jobCostBreakdownProvider` etc.) | existing | mobile data layer | margin arrives on the same fetches; zero new providers strictly required |
| Drift | existing | NOT used for margin | D-10: no margin/rate persistence to device |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| pytest (`asyncio_mode = "auto"`) | backend/.venv | phase E2E tests | `backend/tests/test_phase_33_e2e.py` |
| Playwright | ^1.58.2 | web E2E | `web/tests/phase-33-margin.spec.ts` |
| Jest + Testing Library | ^30 | web component tests | `web/src/features/finance/__tests__/` |
| flutter_test + mocktail | existing | mobile widget/E2E | `mobile/test/e2e/phase_33_margin_e2e_test.dart` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Extending breakdown responses additively | Sibling `/jobs/{id}/margin` endpoints | Sibling doubles network calls per surface, duplicates the cost queries the margin needs anyway, and gives Phase 34/35/36 two endpoints to consume instead of one. Rejected. |
| Python-side invoice total finishing (SQL subtotal GROUP BY + Python discount/tax) | Full SQL replication of discount/tax math | SQL CASE for percent/fixed discount duplicates `from_orm_with_totals` logic in a second language — a divergence risk. Python finishing keeps ONE home for document-total math. Recommended. |
| Fetching whole Invoice ORM rows with `selectinload(line_items)` | Column-only GROUP BY per invoice | ORM rows are fine at anchor level (few invoices) but the column-only aggregate is O(1) round trips at project level regardless of invoice count — matches `_costable_sessions_query` house style. Use column aggregates. |

**Installation:** none — no new packages on any platform.

## Architecture Patterns

### Recommended File Changes (no new modules except two)

```
backend/app/features/finance/
├── margin_math.py          # NEW — DB-free, mirrors labor_derivation.py: MarginSummary math,
│                           #   document_total(), incomplete-flag rules, revenue-basis resolution
├── repository.py           # + revenue query methods (invoice subtotals + quote subtotals per
│                           #   anchor and per project, D-12 traversal)
├── service.py              # + margin assembly in job/scope breakdown + project rollup paths
├── schemas.py              # + MarginSummary; CostBreakdownResponse.margin / ProjectCostRollupResponse.margin
└── router.py               # unchanged endpoints (same URLs, same finance.view gates)

web/src/features/finance/
├── types.ts                # + MarginSummary interface (strings for money, additive)
├── components/CostBreakdownSummary.tsx   # + margin row/block beneath Total (all 3 variants)
└── components/ProjectCostsCard.tsx       # margin flows through existing rollup hook

mobile/lib/features/finance/
├── data/cost_breakdown.dart              # + MarginSummary.tryFromJson (tolerant), CostBreakdown.margin
└── presentation/widgets/cost_breakdown_summary.dart  # + margin row/caption (or sibling margin widget)
```

### Pattern 1: Bounded revenue aggregation (the phase's core new backend logic)

**Anchor-level (job or trade scope).** Two round trips, columns only (never whole ORM rows — `lazy="raise"` on every Invoice/Quote relationship):

```python
# Source: mirrors invoices/service.py:530-565 subtotal subquery + finance/repository.py house style
# Round trip 1: per-invoice subtotal + invoice-level discount/tax fields for the anchor
select(
    Invoice.id,
    Invoice.discount_type,
    Invoice.discount_value,
    Invoice.tax_rate,
    func.coalesce(func.sum(InvoiceLineItem.quantity * InvoiceLineItem.unit_price), Decimal("0")),
).outerjoin(
    InvoiceLineItem,
    (InvoiceLineItem.invoice_id == Invoice.id) & InvoiceLineItem.deleted_at.is_(None),
).where(
    Invoice.job_id == job_id,          # or Invoice.trade_scope_id == trade_scope_id
    Invoice.deleted_at.is_(None),      # D-02: no status filter — every invoice is "issued"
).group_by(Invoice.id, Invoice.discount_type, Invoice.discount_value, Invoice.tax_rate)

# Round trip 2 (ONLY when round trip 1 returned zero rows — D-01 invoices win outright):
# latest approved quote for the anchor, same shape (per-quote subtotal + discount/tax),
# ordered Quote.created_at DESC, first row only — mirrors _latest_approved_quote_for_scope
# (invoices/service.py:145-164; status == "approved", deleted_at IS NULL)
```

Then finish each document in Python with a shared pure helper (extracted, not duplicated — see Don't Hand-Roll):

```python
# margin_math.py — single home for document-total math (third caller after invoice/quote schemas)
def document_total(subtotal, discount_type, discount_value, tax_rate) -> Decimal:
    # percent: subtotal * value/100 quantized to CENTS; fixed: min(value, subtotal)
    # tax on (subtotal - discount); total = taxable + tax  ← identical to from_orm_with_totals
```

**Project-level (D-12 same traversal).** ONE invoice query and ONE quote query, using the exact outerjoin shape of `FinanceRepository.rollup_for_project` (repository.py:128-147):

```python
.outerjoin(TradeScope, Invoice.trade_scope_id == TradeScope.id)
.outerjoin(Job, Invoice.job_id == Job.id)
.where(
    Invoice.deleted_at.is_(None),
    (TradeScope.project_id == project_id) | (Job.project_id == project_id),
)
# select the anchor columns too (Invoice.job_id, Invoice.trade_scope_id) — the per-anchor
# grouping is needed for D-01 fallback resolution and the D-12 per-anchor incomplete flag
```

**Per-anchor D-01 resolution at project level:** group revenue rows by `(job_id, trade_scope_id)` in Python. For each anchor: invoices exist → invoiced revenue; else latest approved quote for that anchor → quoted revenue; else no revenue. Project revenue = Σ per-anchor resolved revenue. Project `revenue_basis` = `invoiced` if every revenue-bearing anchor is invoiced, `quoted` if every one is quoted, `mixed` otherwise, `none` if no anchor has revenue. Quote rows for anchors that already have invoices are discarded (never mixed, never max()).

**Total round trips for a project margin:** existing rollup (entries + sessions + rates = 3) + invoices (1) + fallback quotes (1) = 5 bounded queries regardless of row counts. Well within D-11's computed-on-read posture.

### Pattern 2: API shape — additive `margin` block on existing responses (discretion, decided)

```python
# finance/schemas.py
class MarginSummary(BaseModel):
    """Margin block (MARG-01/02/03). None-able fields express honest absence, never 0."""
    revenue: Decimal | None          # None when revenue_basis == "none" (D-07)
    revenue_basis: str               # "invoiced" | "quoted" | "none"; project adds "mixed" (D-04/Phase 36)
    margin: Decimal | None           # revenue - cost; None when revenue is None
    margin_percent: Decimal | None   # margin/revenue*100; None when revenue None or zero
    incomplete: bool                 # D-05
    incomplete_reasons: list[str] = Field(default_factory=list)  # "unrated_labor" | "no_cost_data"

class CostBreakdownResponse(BaseModel):
    ...existing fields unchanged...
    margin: MarginSummary | None = None   # additive; None preserves old shape exactly

class ProjectCostRollupResponse(BaseModel):
    ...existing fields unchanged...
    margin: MarginSummary | None = None
```

**Why this is safe for mobile (verified):** `CostBreakdown.fromJson` (cost_breakdown.dart:87-111) reads only known keys and ignores extras; `ProjectCostRollupResponse` strictness covers `total`/`entries` only (finance_repository.dart:79-98). A new optional key breaks nothing. New mobile parsing uses the existing `tryFromJson` tolerant idiom (`LaborCostSummary.tryFromJson` is the template) — an old backend without `margin` yields `null`, and the UI simply shows no margin row.

**Why not sibling endpoints:** every surface already fetches the breakdown; margin needs the breakdown's `grand_total` and `unrated_seconds` anyway; one response keeps web invalidation free (`["cost-entries"]` prefix) and gives Phases 34/35/36 one shape to consume. Endpoints, URLs, and `finance.view` gates are unchanged — the RBAC audit surface does not grow.

**machine-readable `revenue_basis` string constants** live once in `margin_math.py` (e.g. `REVENUE_BASIS_INVOICED = "invoiced"`), mirroring `LABOR_CATEGORY_NAME` single-sourcing.

### Pattern 3: Margin math (discretion, decided)

```python
# margin_math.py — DB-free, unit-testable without fixtures (labor_derivation.py precedent)
PERCENT_PLACES = Decimal("0.1")   # one decimal place, ROUND_HALF_UP

margin = (revenue - cost).quantize(CENTS)                       # may be negative — display as-is
margin_percent = (margin / revenue * Decimal("100")).quantize(PERCENT_PLACES, ROUND_HALF_UP)
                 if revenue and revenue > 0 else None            # zero/absent revenue → None, never ∞/NaN
```

- **Precision:** dollars quantized to `CENTS`; percent to one decimal place (matches "21%"-style display; UI may drop a trailing `.0`).
- **Zero revenue with invoices present** (e.g. fully discounted invoice): `revenue = 0`, `margin = -cost`, `margin_percent = None` — number still shown per D-06, percent honestly absent.
- **Negative margins:** legitimate values; serialize normally (e.g. `"-350.00"`, `-8.3`). Visual treatment is a UI-SPEC decision (Phase 32 convention: informational flags never destructive red; a negative margin is a real figure, not a flag).
- **Cost input** = the breakdown's `grand_total` (labor-folded, already quantized) — never recomputed.

### Pattern 4: Incomplete-flag derivation (D-05, MARG-03)

Anchor level — both signals already exist in the breakdown assembly path:

| Reason | Trigger | Source |
|--------|---------|--------|
| `unrated_labor` | `labor.unrated_seconds > 0` | `LaborTotals` from `summarize_labor` (already computed) |
| `no_cost_data` | `grand_total == 0` AND resolved revenue > 0 | breakdown grand_total + Pattern 1 revenue |

- Trade scopes: `labor is None` (job-level tracking) → only `no_cost_data` can trigger there. This is correct per D-05 — a scope has no unrated signal to inspect, and `labor_tracked_at_job_level` already tells the UI why.
- D-07: no revenue → `incomplete = False`, `margin = None`, `revenue_basis = "none"` — neutral note, not a flag.
- **Project level (D-12: any contributing anchor flagged):** `unrated_labor` aggregates safely (project `unrated_seconds > 0` ⟺ some job has unrated time). `no_cost_data` does NOT aggregate safely (another anchor's costs mask a legacy job) — it must be evaluated **per anchor**: group cost entries by anchor (the rollup's fetched entries already carry `job_id`/`trade_scope_id` — group in Python, zero extra queries), group revenue by anchor (Pattern 1 already does), and derive per-job labor presence by adding `TimeEntry.job_id` to the columns of the project session query (one-line change to `completed_work_sessions_for_project`'s select; `WorkSession` gains a `job_id` field or a parallel per-job grouping — planner's choice, no schema change). An anchor with revenue > 0, zero cost entries, and zero rated labor seconds flags the project.

### Pattern 5: Web margin UI (extends `CostBreakdownSummary` + `ProjectCostsCard`)

- `types.ts`: additive `MarginSummary` interface — money as strings, `marginPercent` as number-or-null is acceptable for display but string keeps the Decimal-verbatim policy; recommend string.
- The margin block renders beneath the Total row inside `CostBreakdownSummary` (all three variants) or as a sibling `MarginSummary` component mounted directly under it — either satisfies D-08; a sibling component keeps `CostBreakdownSummary` single-responsibility (clean-code SRP) and is the recommended decomposition.
- Display shape: `"$4,200 · 21%"` (D-09). States needed for the UI-SPEC pass:
  1. invoiced margin — figure only, no caption
  2. quoted margin — figure + caption "Based on approved quote — not yet invoiced" (D-04)
  3. flagged margin — figure + incomplete chip (reuse the unrated-chip recipe: `bg-brand/15 text-amber-900`, rounded-full — NOT destructive red)
  4. no revenue — neutral `text-gray-500` note ("No revenue recorded" — exact copy locked in UI-SPEC)
  5. loading — `"—"` placeholders (existing convention); error — breakdown's existing inline error covers it
- Gating: nothing new — the mounts (`jobs/[id]/page.tsx`, `TradeScopeDetail.tsx`, `ProjectCostsCard.tsx`) are already inside `can("finance.view")`-gated cards; margin data rides the already-gated responses.
- Web money formatting via existing `formatCurrency`; percent formatted from the string without float re-math beyond display.

### Pattern 6: Mobile margin UI

- `cost_breakdown.dart`: `MarginSummary.tryFromJson` (tolerant — null on absence/malformed, per `LaborCostSummary` template; `is` checks, no bare casts) + optional `margin` field parsed in both `fromJson` and `tryFromJson` paths.
- Widget: margin row + caption beneath the Total row in `cost_breakdown_summary.dart` (or a sibling `margin_summary_row.dart`); same `bodyMedium`/`titleSmall` typography, chip recipe `Color(0x26F5A623)` / `Color(0xFF78350F)` from the unrated chip; captions are static `bodySmall` (mobile has no popover convention — Phase 32 precedent).
- Data flow: zero new network calls — `jobCostBreakdownProvider`, `tradeScopeCostBreakdownProvider`, and `_projectRollupFetchProvider` already deliver the extended responses. No Drift persistence (D-10); offline the breakdown already shows "Breakdown unavailable offline" — margin is inside it, nothing extra needed.

### Anti-Patterns to Avoid

- **Reusing `InvoiceService.aggregate_by_project` or `QuoteService`'s per-scope aggregate for margin revenue** — both traverse trade scopes ONLY (job-anchored invoices invisible → violates D-12) and cast to `float` (violates the Decimal policy). Reference their subtotal-subquery *shape*, not their traversal or types.
- **Using `Invoice.amount_paid` for revenue** — that is collections, not billing (D-02 is accrual basis).
- **Summing quote totals across multiple approved quotes per anchor** — use latest approved only (`created_at DESC`, `first()`), matching `_latest_approved_quote_for_scope`.
- **Accessing `invoice.line_items` / `quote.line_items` without eager loading** — `lazy="raise"` fails loudly; use column aggregates instead.
- **Computing margin client-side** — backend computes, clients display verbatim (PITFALLS.md #10; D-11).
- **Adding margin fields to invoice/quote/report endpoints** — those stay ungated (Phase 30 D-06 boundary); margin lives only on `finance.view`-gated breakdown/rollup responses.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Invoice/quote document total math | A third copy of subtotal/discount/tax logic | Extract ONE pure `document_total()` in `margin_math.py`; optionally have `from_orm_with_totals` (both files) delegate to it | The math already exists twice (invoices/schemas.py:160-194, quotes/schemas.py:173+); a third divergent copy is how invoice page total ≠ margin revenue happens |
| Money constants/quantization | New `Decimal("0.01")` literals | `CENTS`, `ZERO_MONEY`, `ROUND_HALF_UP` from `labor_derivation.py` | Single rounding policy (PITFALLS.md #10); CLAUDE.md no-magic-numbers |
| Cost side of the margin | Any new cost/labor query | `job_cost_breakdown`, `trade_scope_cost_breakdown`, `rollup_for_project` outputs | Phase 32 shipped it complete, bounded, and tested — margin consumes `grand_total` + `unrated_seconds` |
| Latest-approved-quote rule | New quote-selection logic | Mirror `_latest_approved_quote_for_scope` (status filter + `created_at DESC` + `first()`) | Established D-03-compatible precedent already in production for progress invoicing |
| Permission gating | Custom checks | `await require_permission("finance.view")(current_user, db)` | House style on every finance route |
| Web cache invalidation | New query keys/invalidation | Existing `["cost-entries", ...]` prefix + `invalidateAllCostEntries` | Margin rides breakdown responses; every cost write already refreshes them |
| Mobile JSON tolerance | Ad-hoc null checks | The `tryFromJson` static-method idiom from `cost_breakdown.dart` | Codified strict-on-existing/tolerant-on-new contract |

**Key insight:** this phase should add almost no *mechanism* — only revenue queries, pure math, one schema block, and one UI row per platform. Every supporting system (gating, invalidation, parsing, money policy, traversal) already exists and is the standard to copy.

## Common Pitfalls

### Pitfall 1: Revenue and cost traversing different paths at project level
**What goes wrong:** Project revenue query joins only through trade scopes (the existing `aggregate_by_project` shape) while cost traverses scopes + jobs — job-anchored invoices vanish, margins understate revenue.
**Why it happens:** The tempting-to-reuse invoice aggregate predates D-12.
**How to avoid:** Copy `rollup_for_project`'s dual-outerjoin `(TradeScope.project_id == p) | (Job.project_id == p)` shape verbatim for the revenue queries; the mandated integration test (below) asserts it.
**Warning signs:** A project margin that changes when an invoice is re-anchored from job to scope; project revenue < sum of visible anchor revenues.

### Pitfall 2: Double-counting quote fallback with invoices at project level
**What goes wrong:** Summing "all invoices + all approved quotes" for a project counts a scope's quote AND the invoices generated from it.
**Why it happens:** Aggregate-level thinking; D-01 is a per-anchor rule.
**How to avoid:** Resolve revenue per anchor first (invoices win outright at that anchor), then sum. Test: scope with approved quote + one invoice contributes only the invoice.
**Warning signs:** Project margin exceeds every anchor margin; margin % > quote markup (PITFALLS.md #3 impossibility).

### Pitfall 3: Tax/discount treatment drifting between the invoice leg and the quote leg
**What goes wrong:** Invoice revenue computed with tax, quote fallback without (or vice versa) — a job's margin jumps when its first invoice is issued for the identical amount.
**How to avoid:** One `document_total()` helper applied identically to both document types; one Open Question (below) decides the tax policy, then it applies to both.
**Warning signs:** Margin changes on quote→invoice conversion with unchanged line items.

### Pitfall 4: Breaking mobile's strict parser
**What goes wrong:** Renaming/reshaping existing breakdown/rollup fields throws `FormatException` on every device.
**How to avoid:** Additive-only: new optional `margin` key; never touch `total`, `entries`, `categories`, `grand_total`, `labor`, `labor_tracked_at_job_level`. Old clients ignore `margin`; new clients tolerate its absence via `tryFromJson`.
**Warning signs:** Any edit (not addition) to `CostBreakdownResponse`/`ProjectCostRollupResponse` field definitions.

### Pitfall 5: Legacy job fabricating an unflagged ~100% margin (PITFALLS.md #9 — the keystone)
**What goes wrong:** `SUM()` over zero cost rows → cost 0 → margin = revenue, 100%, no flag.
**How to avoid:** D-05 condition 2 is exactly this case; the keystone E2E (below) seeds a pre-v4.0-style job (invoice, no cost entries, no rated time) and asserts `incomplete == true` with `"no_cost_data"`.
**Warning signs:** Any margin response with revenue > 0, cost == 0, and `incomplete == false`.

### Pitfall 6: `lazy="raise"` trips on Invoice/Quote relationships
**What goes wrong:** Fetching Invoice ORM rows then touching `line_items` without `selectinload` raises at runtime.
**How to avoid:** Column-only aggregate queries (Pattern 1) never materialize relationships.

### Pitfall 7: Float leaking into the money path
**What goes wrong:** Copying `float(row.total_billed or 0)` from the existing aggregates.
**How to avoid:** `Decimal(str(row.value or 0))` / `func.coalesce(..., Decimal("0"))` only; grep new code for `float(` before commit (PITFALLS.md #10 warning sign).

### Pitfall 8: Project-level quotes invisible to the rollup
**What goes wrong:** Quotes created at project level (`job_id` and `trade_scope_id` both NULL, `project_id` set on approval — quotes/models.py:64-70) fall outside the D-12 traversal; a freshly-approved-but-not-yet-invoiced project shows no revenue.
**How to avoid:** See Open Question 2 — planner must decide explicitly; do not let it fall through silently.

## Code Examples

### Same-traversal integration test (D-12 mandate, Pitfall 1)

```python
# backend/tests/test_phase_33_e2e.py — the phase's mandated netting test
async def test_project_margin_same_traversal_mixed_anchors(async_client, tenant_a_client, seed_two_tenants):
    # Seed ONE project containing:
    #   - trade scope S (project_id = P) with: scope-anchored invoice ($1000 total),
    #     scope-anchored cost entry ($300)
    #   - job J (project_id = P) with: job-anchored invoice ($500 total),
    #     job-anchored cost entry ($100), rated time entry ($50 derived labor)
    # Assert GET /projects/{P}/cost-entries:
    #   margin.revenue == "1500.00"            (both anchors' invoices — same traversal)
    #   grand_total    == "450.00"             (both anchors' costs + labor — same traversal)
    #   margin.margin  == "1050.00", margin.margin_percent == "70.0"
    #   margin.revenue_basis == "invoiced", margin.incomplete is False
```

### Keystone honesty test (Pitfall 9 / D-05 / CONTEXT specifics, verbatim requirement)

```python
async def test_legacy_job_with_revenue_and_no_costs_is_flagged_never_100_percent(...):
    # job with a $2000 invoice, ZERO cost entries, ZERO time entries
    # GET /jobs/{id}/cost-breakdown →
    #   margin.margin == "2000.00" (partial number still shown, D-06)
    #   margin.incomplete is True, "no_cost_data" in margin.incomplete_reasons
```

### Per-anchor D-01 resolution (pure, unit-testable without DB)

```python
# margin_math.py — mirrors labor_derivation.py's DB-free posture
@dataclass(frozen=True)
class AnchorRevenue:
    anchor: tuple[uuid.UUID | None, uuid.UUID | None]  # (job_id, trade_scope_id)
    invoiced_total: Decimal | None   # None = no invoices at this anchor
    quoted_total: Decimal | None     # latest approved quote, None if absent

def resolve_revenue(anchor: AnchorRevenue) -> tuple[Decimal | None, str]:
    if anchor.invoiced_total is not None:
        return anchor.invoiced_total, REVENUE_BASIS_INVOICED   # invoices win outright (D-01)
    if anchor.quoted_total is not None:
        return anchor.quoted_total, REVENUE_BASIS_QUOTED
    return None, REVENUE_BASIS_NONE                            # D-07: absent, not flagged
```

### Web margin display state derivation (for the UI-SPEC pass)

```typescript
// Sibling component under CostBreakdownSummary; strings displayed verbatim
// state 1: basis "invoiced" → "$4,200 · 21%"
// state 2: basis "quoted"   → figure + caption "Based on approved quote — not yet invoiced"
// state 3: incomplete       → figure + chip (unrated-chip recipe, bg-brand/15 text-amber-900)
// state 4: basis "none"     → neutral gray note, no figure (exact copy: UI-SPEC)
```

## State of the Art

| Old Approach (pre-33) | Current Approach (33) | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Costs sections show spend only | Same sections show spend + margin block | this phase | No new surfaces/nav (D-08) |
| Revenue aggregates exist only in ungated per-scope billing summaries (float, scope-only) | Decimal, same-traversal, finance.view-gated revenue inside breakdown responses | this phase | Existing billing summaries untouched (Phase 30 D-06: revenue surfaces stay ungated) |
| Phase 36 AI has no billed-vs-estimated signal | `revenue_basis` field machine-readable in every margin block | this phase | Phase 36 reads, never recomputes |

**Deprecated/outdated:** nothing removed; `aggregate_by_project` remains for the billing UI it serves — it is simply not a margin input.

## Open Questions

1. **Does "invoice total" for margin revenue include tax?**
   - What we know: D-01 says "sum of its invoice totals". The response-layer `total` = subtotal − discount + tax. But every existing *aggregation* precedent is pre-tax: `aggregate_by_project.total_billed` sums raw line items; progress-invoice amounts derive from quote subtotal "before tax/discount".
   - What's unclear: whether the user meant the displayed invoice total (tax-inclusive) or the earned amount (tax is a pass-through; including it inflates margin on every taxed job).
   - Recommendation: use **subtotal − discount (pre-tax)** for both invoice and quote legs via the shared `document_total(..., include_tax=False)` — economically honest and consistent with existing aggregation precedent. Whichever is chosen, apply identically to both legs (Pitfall 3) and record the choice in the plan. LOW risk either way if consistent; flag for a one-line user confirmation if the planner prefers.

2. **Project-level quotes (job_id = trade_scope_id = NULL, project_id set) in the project rollup fallback**
   - What we know: the D-12 traversal (scope-anchored + jobs by project_id) excludes them by construction; approving one creates per-field jobs whose later invoices DO enter the traversal. Until first invoice, such a project shows no revenue.
   - What's unclear: whether D-12's locked traversal intentionally excludes them or simply didn't consider this quote shape.
   - Recommendation: include `Quote.project_id == project` approved quotes as a third revenue leg **only when the entire project has zero invoices** (the natural project-level extension of D-01; cannot double-count against cost — costs never anchor to projects). If the planner prefers strict D-12 literalism, exclude and document the gap for Phase 35. Needs an explicit plan decision either way (Pitfall 8).

3. **`margin_percent` serialization type**
   - What we know: money is Decimal-as-string by convention; a percent is not money.
   - Recommendation: serialize as string too (`"21.0"`, `"-8.3"`) — one policy, no float in transit; mobile/web format for display only. Trivial; planner may decide.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Python venv w/ pytest | backend tests | ✓ | `backend/.venv/bin/pytest` (venv Python ≥3.12 — PEP 695 syntax already in labor_derivation.py runs) | — |
| Node.js | web lint/tests | ✓ | v20.18.1 | — |
| Playwright | web E2E | ✓ | ^1.58.2 (`npm run test-e2e`) | — |
| Jest | web unit | ✓ | ^30 (`npm test`) | — |
| Flutter | mobile tests | ✓ | 3.41.4 stable | — |

**Missing dependencies with no fallback:** none.
**Note:** system `python3` is 3.9.6 — always run backend tests via `backend/.venv/bin/pytest`, never bare `python3 -m pytest`.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Backend | pytest (asyncio_mode=auto, testpaths=["tests"], config in `backend/pyproject.toml`) |
| Web unit | Jest 30 (`web/jest.config.ts`) |
| Web E2E | Playwright 1.58 (`web/playwright.config.ts`, specs in `web/tests/`) |
| Mobile | flutter_test + mocktail (`mobile/test/`, E2E in `mobile/test/e2e/`) |
| Quick run command | `cd backend && .venv/bin/pytest tests/test_phase_33_e2e.py -x -q` |
| Full suite command | `cd backend && .venv/bin/pytest` · `cd web && npm test && npm run test-e2e:chromium` · `cd mobile && flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MARG-01 | Job/scope margin: invoiced revenue, quote fallback + basis label, $·% math, finance.view 403 for admin/worker | integration | `.venv/bin/pytest tests/test_phase_33_e2e.py -k "anchor or basis or forbidden" -x` | ❌ Wave 0 |
| MARG-01 | Pure margin math (percent rounding, zero revenue, negative margin, document_total discount/tax) | unit | `.venv/bin/pytest tests/unit -k margin -x` | ❌ Wave 0 |
| MARG-02 | Project rollup: same-traversal netting (mixed job/scope anchors), per-anchor D-01 resolution, mixed basis | integration | `.venv/bin/pytest tests/test_phase_33_e2e.py -k traversal -x` | ❌ Wave 0 |
| MARG-03 | Incomplete flag: unrated-labor trigger, legacy zero-cost keystone, D-07 no-revenue not flagged, project any-anchor propagation | integration | `.venv/bin/pytest tests/test_phase_33_e2e.py -k "incomplete or legacy" -x` | ❌ Wave 0 |
| MARG-01/03 (web) | Margin row states (invoiced/quoted/flagged/no-revenue) in CostBreakdownSummary contexts | component | `cd web && npm test -- cost-breakdown` (extend existing `cost-breakdown-summary.test.tsx`) | ✅ extend |
| MARG-01/02 (web) | Margin visible on job/scope/project pages for owner, absent without finance.view | e2e | `cd web && npx playwright test tests/phase-33-margin.spec.ts --project=chromium` | ❌ Wave 0 |
| MARG-01/03 (mobile) | Tolerant `MarginSummary.tryFromJson` parse (present/absent/malformed) | unit | `cd mobile && flutter test test/features/finance/` | ❌ Wave 0 |
| MARG-01/02/03 (mobile) | Margin row + chip + captions render on job/scope/project screens; gated by financePermissionProvider | e2e widget | `cd mobile && flutter test test/e2e/phase_33_margin_e2e_test.dart` | ❌ Wave 0 |

Manual-only: none — all verification items automatable per CLAUDE.md UAT-automation rules (visual polish deferred to the UI-SPEC checker).

### Sampling Rate
- **Per task commit:** the task's own test file (`.venv/bin/pytest tests/test_phase_33_e2e.py -x -q` for backend tasks; `npm test -- <pattern>` / `flutter test <file>` for frontend tasks) + platform linters (`ruff check`, `npx tsc --noEmit`, `dart analyze`).
- **Per wave merge:** full backend `pytest` + `flutter test` + `npm test`.
- **Phase gate:** all three full suites + Playwright chromium green before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `backend/tests/test_phase_33_e2e.py` — covers MARG-01/02/03 (seed helpers for invoices/quotes exist in `test_phase_25_e2e.py` / `test_phase_32_e2e.py` fixtures — reuse `seed_two_tenants`, tenant clients)
- [ ] `backend/tests/unit/test_margin_math.py` — pure-math unit tests (DB-free, mirrors labor_derivation unit tests)
- [ ] `web/tests/phase-33-margin.spec.ts` — Playwright (login through UI then SPA-navigate — direct `page.goto` leaves permissions disabled, STATE.md Phase 32-04 lesson)
- [ ] `mobile/test/features/finance/margin_summary_parse_test.dart` — parser units
- [ ] `mobile/test/e2e/phase_33_margin_e2e_test.dart` — widget E2E (MockDio at Dio level, ProviderScope overrides; Riverpod 3 `Override` via `flutter_riverpod/misc.dart`, STATE.md 32-05 lesson)
- Framework installs: none needed.

## Sources

### Primary (HIGH confidence — direct code inspection, 2026-07-27)
- `backend/app/features/invoices/models.py` — Invoice status check (`unpaid|partially_paid|paid`, no draft), `issued_at` NOT NULL, job_id/trade_scope_id anchors, `amount_paid`, no stored total
- `backend/app/features/invoices/schemas.py:160-194` — `from_orm_with_totals` document-total math (subtotal → discount → tax)
- `backend/app/features/invoices/service.py:145-164, 457-470, 520-592` — latest-approved-quote precedent; pre-tax subtotal precedent; `aggregate_by_project` scope-only + float anti-pattern
- `backend/app/features/quotes/models.py` — status machine, project-level quote shape (`title`/`project_id`), QuoteLineItem `field`
- `backend/app/features/finance/{repository,service,schemas,router}.py` + `labor_derivation.py` — cost side, traversal shape, `CENTS`/`ZERO_MONEY`, breakdown assembly, unrated seconds, finance.view gating
- `web/src/features/finance/{types.ts,hooks.ts,components/*}` — string-money policy, query-key prefix invalidation, breakdown component states, ProjectCostsCard grand_total fallback
- `mobile/lib/features/finance/{data,presentation}/*` — strict/tolerant parsing contract, providers, no-Drift-persistence posture, gating via `financePermissionProvider`
- `.planning/research/PITFALLS.md` #1/#3/#9/#10; `.planning/phases/32-labor-rates-and-cost-rollup/32-UI-SPEC.md` (chip/caption/copy conventions); `32-RESEARCH.md` (breakdown architecture)
- `backend/pyproject.toml`, `web/package.json`, `backend/tests/`, `web/tests/`, `mobile/test/e2e/` — test infrastructure
- `~/.agents/skills/clean-code/SKILL.md` — naming/SRP/small-function rules applied to recommendations

### Secondary (MEDIUM confidence)
- STATE.md accumulated decisions (Phase 30–32 entries) — platform patterns cross-referenced against code

### Tertiary (LOW confidence)
- None — no external web research required; the domain is fully internal to this codebase.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; everything verified in-repo
- Revenue aggregation & traversal: HIGH — query shapes verified against shipped repository code
- Margin math / flag rules: HIGH for mechanics; MEDIUM on the tax-inclusion question (Open Question 1, needs a plan-level decision)
- Project-level quote handling: MEDIUM — genuine gap in the locked traversal (Open Question 2)
- UI composition: HIGH — extends components read in full, conventions locked by 32-UI-SPEC

**Research date:** 2026-07-27
**Valid until:** 2026-08-26 (internal-codebase research; invalidated only by changes to the finance feature files listed above)
