# Phase 32: Labor Rates and Cost Rollup - Research

**Researched:** 2026-07-26
**Domain:** Effective-dated rate lookup + derived labor cost + category cost breakdown (FastAPI/SQLAlchemy async + Next.js + Flutter)
**Confidence:** HIGH (grounded in direct codebase inspection; zero new external dependencies)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Labor cost derivation**
- **D-01:** **Computed-on-read.** Labor cost is calculated at query time: `duration_seconds` × the rate whose `effective_from` covers the work day, looked up from the append-only `labor_rates` table. No materialized labor CostEntry rows, no snapshot columns, no recompute machinery. Time-entry adjustments and rate backdating are automatically reflected. This satisfies success criterion 2 (a later rate change never rewrites past labor cost) because rates are effective-dated and append-only — a new rate effective today cannot alter the rate that was effective on a past work day.
- **D-02:** **Backdated rates are allowed.** Owner/PM can enter a rate with a past `effective_from` (e.g., worker started May 1, rate entered May 10 effective May 1) — labor cost for those days fills in retroactively. This is the sanctioned fix for unrated hours; it is deterministic under computed-on-read.
- **D-03:** **Completed sessions only.** Labor cost includes only clocked-out time entries with a final `duration_seconds` (session_status completed or adjusted). Active sessions never contribute to cost totals.
- **D-04:** The work day for rate lookup is derived from the time entry's clock-in date. (Exact timezone handling: Claude's discretion, but must be deterministic and documented.)

**Missing-rate handling**
- **D-05:** **Explicit "unrated hours" flag — never silent $0.** When tracked time has no rate effective on the work day, labor totals show the computed amount for rated hours plus a visible indicator of unrated hours (e.g., "12.5 hrs unrated"). Unrated hours are never valued at $0 silently and never hidden. This is the honest-data posture Phase 33's incomplete-data flag (MARG-03) builds on, and it nudges Owner/PM toward backdating a rate (D-02).
- **D-06:** **Unburdened labeling via info affordance.** Labor category rows and totals carry an info tooltip (web) / small caption (mobile) reading to the effect of "Wage cost only — excludes payroll tax, insurance, overhead." Carried from STATE.md blocker + research PITFALLS.md Pitfall 2: v4.0 labor is wage-only; the UI must say so where labor figures appear.

**Time-tracking scope**
- **D-07:** **Labor stays job-only for v4.0.** Labor cost derives exclusively from existing job-anchored `TimeEntry` rows; projects get labor via the `jobs.project_id` link (migration 0030). No TimeEntry schema change, no new clock-in surfaces. Resolves the STATE.md open blocker.
- **D-08:** **Trade-scope itemized views show a labor row with a "tracked at job level" note** — not an omitted row, not $0. Materials/subcontractor/other totals show real numbers; the labor line is honest about why there's no scope-level number.

**Rate management UI**
- **D-09:** **Web Team page only** (per Phase 30 D-07 — no new nav surface, and no mobile rates editor this phase). Rate field + full effective-dated history per member, visible/editable only with `finance.rates.manage` (Phase 30 D-07/D-08: workers never see their own rate; admin excluded).

**Itemized breakdown presentation**
- **D-10:** **Extend the existing Phase 31 Costs sections** on job detail, trade-scope detail, and project screens with a category-totals summary (labor / materials / subcontractor / other + total). No dedicated breakdown screen/tab — one cost surface per entity, reusing shipped components and permission gating.
- **D-11:** **Both web and mobile** get the category breakdown, matching Phase 31's platform pattern. Labor figures come from the backend API — mobile does not compute rates locally and labor_rates data never syncs to the device (rates are the most sensitive data in the system per Phase 30).

### Claude's Discretion
- Rate-editor UX details: validation, future-dated rates, duplicate effective_from handling, history display layout on the Team page.
- API shape: whether breakdown totals extend the existing rollup endpoint or add new endpoints; response serialization (mirror Decimal-as-string).
- Timezone convention for mapping `clocked_in_at` to a work date (D-04) — deterministic and consistent between derivation and display.
- Query/index design for the derivation join (effective-dated lookup per research ARCHITECTURE.md); whether to add a covering index.
- Mobile: how breakdown data is fetched/cached (Phase 31's FinanceRepository.fetchProjectRollup pattern) — noting labor requires the API, so breakdown is online-fetched like the Phase 31 project rollup.
- Which permission gates the rates endpoints beyond `finance.rates.manage` reads/writes (e.g., whether rate history read requires the same key — default: yes, per Phase 30 D-08 zero-exception posture).

### Deferred Ideas (OUT OF SCOPE)
- **Trade-scope/task-level time tracking** (mobile clock-in against trade scopes or tasks, TimeEntry trade_scope anchor) — deliberately deferred out of v4.0; would unlock real trade-scope labor cost. Revisit as its own phase if scope-level labor becomes a priority.
- **Mobile rate management** (rates editor in mobile admin area) — deferred; rates stay a web Team page task this milestone.
- **Burden rates / burden multiplier** (per-company configurable) — explicitly out of v4.0 scope per STATE.md; PITFALLS.md Pitfall 2 documents the design when it lands. The D-06 unburdened labeling is the v4.0 mitigation.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| COST-04 | Owner/PM can set a worker's hourly cost rate with an effective date; historical rates are preserved | `LaborRate` model + `ix_labor_rates_company_user_effective` already exist (migration 0032) — this phase adds append-only POST/GET endpoints gated `finance.rates.manage` (Pattern 3), Team page rate column + history dialog (Pattern 5). Duplicate-`effective_from` tie-break: latest `created_at` wins (Pattern 2). |
| COST-05 | System derives labor cost automatically from tracked time × the rate effective on the day worked | Two-query bounded derivation in the finance service (Pattern 1): completed `TimeEntry` rows (job or via `jobs.project_id`) + all `LaborRate` rows for involved contractors, matched by a pure Python helper with UTC-date work-day convention (Pattern 2). No N+1; Decimal-only math; unrated seconds surfaced explicitly (D-05). |
| COST-06 | Owner/PM can view itemized costs per job/trade scope/project with category totals (labor/materials/subcontractor/other) | New `GET /jobs/{id}/cost-breakdown` and `GET /trade-scopes/{id}/cost-breakdown` endpoints + extended `ProjectCostRollupResponse` (Pattern 4); shared `CostBreakdownSummary` UI component on web (Pattern 6) and mobile widget (Pattern 7), layered onto Phase 31 Costs sections. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

Directives that directly bind this phase's plans:

- **N+1 prevention:** never query inside a loop; `lazy="raise"` on relationships; eager-load in queries. The derivation MUST be bounded round trips (the 2-query design below), never a per-time-entry rate lookup.
- **OOP architecture:** new models inherit `TenantScopedModel`; services inherit `TenantScopedService`; repositories inherit `TenantScopedRepository`; standalone service functions are NOT allowed. LaborRate/derivation logic extends the existing `FinanceService`/`FinanceRepository` classes (or a sibling class in the same module).
- **No `db.commit()` in services** — `get_db` handles it; `db.flush()` for generated IDs.
- **Clean code:** intention-revealing names (`resolve_rate_for_work_date`, not `get_rate`), functions ~20 lines, no magic numbers (`SECONDS_PER_HOUR = 3600` or `Decimal("3600")` as named constant), DRY (one shared category-totals query helper for job/scope).
- **Testing:** every new service function/endpoint gets tests before merging; backend integration tests via ASGI client with existing conftest fixtures; phase E2E in `backend/tests/test_phase_32_e2e.py`, mobile in `mobile/test/e2e/phase_32_*.dart`; E2E ships in the same change as the feature.
- **Flutter:** no bare `as` casts on API responses — `is` checks + `FormatException` (the existing `FinanceRepository` pattern); `whereType<T>()`; never swallow exceptions silently; `AsyncNotifier`/documented GetIt-in-Riverpod tradeoff.
- **Money:** amounts stay Decimal (backend) / string (web, mobile) end-to-end — mobile displays backend-computed strings, never re-derives totals with `double`.
- **Pre-commit:** `ruff check`/`ruff format` (backend), `dart analyze` (mobile), `npm run lint` + `npx tsc --noEmit` (web) must pass.
- **Migrations:** run `docker compose up migrate` after adding Alembic migrations — **note: this phase needs NO new migration** (labor_rates table + index exist from 0032; jobs.project_id from 0030).

## Summary

Everything this phase needs already exists at the schema and infrastructure level: `LaborRate` (with composite index `ix_labor_rates_company_user_effective`), `CostEntry`/`CostCategory` with the seeded `labor` system category, `jobs.project_id`, the three `finance.*` permission keys (with admin exclusion already tested in Phase 30), the Phase 31 Costs sections on all three entity screens (web + mobile), and the web Team page with `usePermissions()` gating. **This phase is pure application code: no migration, no new library, no new permission key.**

The core new backend logic is the codebase's first effective-dated lookup. The recommended design is a **two-query bounded derivation** computed in Python with Decimal (matching the existing `rollup_for_project` precedent of "fetch itemized in one round trip, aggregate in Python"): query 1 fetches completed time entries for the anchor (job directly, or project via the `jobs.project_id` join), query 2 fetches all labor rates for the distinct contractor IDs involved, and a pure, unit-testable helper resolves each entry's rate as "latest `effective_from` ≤ work day, ties broken by latest `created_at`". Work day = UTC date of `clocked_in_at` (there is no company timezone field anywhere in the schema, so UTC is the only deterministic convention available without new schema). A SQL LATERAL join alternative exists but is worse here: harder to unit-test the rate-resolution rule, harder to produce the unrated-hours flag, and unnecessary at SMB scale.

The API shape: two new read endpoints (`/jobs/{id}/cost-breakdown`, `/trade-scopes/{id}/cost-breakdown`) plus additive extension of the existing project rollup response (keep the existing `total` field's meaning unchanged — mobile's `fetchProjectRollup` parses it strictly and throws `FormatException` on shape changes). Labor rates get append-only POST + history GET, both gated `finance.rates.manage`. One genuine gap discovered: **nothing currently prevents a manual CostEntry from using the reserved `labor` category** (Phase 30 D-10 reserves it for derived labor) — this phase must add that service-layer guard or the breakdown's labor row can double-count.

**Primary recommendation:** Ship as 4 plan-sized slices: (1) backend labor-rates endpoints + derivation service + breakdown endpoints with full pytest coverage including the success-criterion-2 rate-change test; (2) web Team page rates UI; (3) web breakdown UI on the three Costs surfaces; (4) mobile breakdown UI + phase E2E. No migration anywhere.

## Standard Stack

### Core (all existing — verify nothing new is installed)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SQLAlchemy async + asyncpg | existing | Derivation queries, GROUP BY category totals | Existing backend ORM; `TenantScopedRepository` pattern |
| FastAPI + Pydantic v2 | existing | Rates CRUD + breakdown endpoints; `Decimal` auto-serializes to JSON string (verified in `CostEntryResponse`) | Existing pattern; no custom serializer needed |
| TanStack Query (web) | existing | `useLaborRates`, `useJobCostBreakdown` hooks | Matches `web/src/features/finance/hooks.ts` |
| base-ui Popover (`@base-ui/react/popover`) | existing | D-06 info affordance on web labor rows | **No `tooltip.tsx` exists in `web/src/components/ui/`** — use the existing `popover.tsx` with an Info icon trigger (STATE.md precedent: base-ui PopoverTrigger has no asChild) |
| Riverpod 3 + Dio (mobile) | existing | Breakdown fetch providers | Matches `cost_providers.dart` / `FinanceRepository` |
| Python `decimal.Decimal` | stdlib | All labor math (`ROUND_HALF_UP`) | PITFALLS.md Pitfall 10; existing `Decimal(str(...))` convention |

**Installation:** none. This phase adds zero dependencies on any platform.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Two-query Python derivation | SQL `LEFT JOIN LATERAL` (rate subquery per entry) | Single round trip, but: rate-resolution rule lives in SQL (untestable as a pure unit), unrated-hours accounting needs NULL-handling branches in SQL, and interval→hours×rate math invites rounding-policy drift. Only revisit if a company accumulates thousands of time entries per project (Performance Traps, ARCHITECTURE.md). |
| Latest-`created_at` tie-break for duplicate `effective_from` | 409 Conflict + unique index on (company_id, user_id, effective_from) | The 409 approach requires a new migration AND leaves no correction path for a same-day typo without violating append-only. Tie-break keeps append-only intact: re-enter the same date with the right amount, newest row wins, history shows both. |
| New `/cost-breakdown` endpoints for job/scope | Wrapping the existing `GET /cost-entries/?job_id=` list in an envelope | The list endpoint returns a bare JSON array consumed by web hooks and mobile `_upsertCostEntries` — wrapping it is a breaking change to two clients for no benefit. |

## Architecture Patterns

### Recommended File Changes (no new modules)

```
backend/app/features/finance/
├── models.py        # UNCHANGED (LaborRate exists)
├── schemas.py       # + LaborRateCreate/Response, CostBreakdownResponse, CategoryTotal,
│                    #   LaborCostSummary; extend ProjectCostRollupResponse (additive)
├── repository.py    # + list_rates_for_user, list_rates_for_users, category_totals_for_job,
│                    #   category_totals_for_trade_scope, completed_time_entries_for_job,
│                    #   completed_time_entries_for_project
├── service.py       # + create_labor_rate, list_rate_history, job_cost_breakdown,
│                    #   trade_scope_cost_breakdown, extended rollup_for_project;
│                    #   labor derivation helpers (pure functions or staticmethods)
└── router.py        # + POST/GET /labor-rates/, GET /jobs/{id}/cost-breakdown,
                     #   GET /trade-scopes/{id}/cost-breakdown; rollup handler extended

web/src/features/finance/
├── types.ts         # + LaborRate, CategoryTotal, LaborCostSummary, CostBreakdown
├── api.ts           # + fetchLaborRates, createLaborRate, fetchJobCostBreakdown, fetchTradeScopeCostBreakdown
├── hooks.ts         # + useLaborRates, useAddLaborRate, useJobCostBreakdown, useTradeScopeCostBreakdown
└── components/
    ├── CostBreakdownSummary.tsx   # shared category-totals block (labor/materials/sub/other + total)
    └── RateHistoryDialog.tsx      # or under team/_components/ — rate form + history table

web/src/app/(dashboard)/team/page.tsx          # + Cost Rate column (finance.rates.manage-gated)
web/src/app/(dashboard)/jobs/[id]/page.tsx     # + CostBreakdownSummary in existing Costs card
web/src/app/(dashboard)/projects/components/TradeScopeDetail.tsx  # + summary w/ job-level labor note
web/src/features/finance/components/ProjectCostsCard.tsx          # + summary from extended rollup

mobile/lib/features/finance/
├── data/finance_repository.dart   # + fetchJobCostBreakdown, fetchTradeScopeCostBreakdown;
│                                  #   fetchProjectRollup parses new optional breakdown fields
├── presentation/providers/cost_providers.dart  # + breakdown FutureProvider.family per anchor
└── presentation/widgets/cost_breakdown_summary.dart  # new widget above CostListSection
```

### Pattern 1: Two-query bounded labor derivation (the phase's core backend logic)

**What:** For an anchor (job or project), fetch (a) completed time entries and (b) all rates for the involved contractors, then match in Python. Exactly 2 round trips regardless of entry count — satisfies the CLAUDE.md N+1 rule.

**Query (a) — job anchor:**
```python
# Source: mirrors JobRepository.list_time_entries filters + D-03
_COMPLETED_STATUSES = ("completed", "adjusted")

select(TimeEntry).where(
    TimeEntry.job_id == job_id,
    TimeEntry.session_status.in_(_COMPLETED_STATUSES),
    TimeEntry.duration_seconds.is_not(None),
    TimeEntry.deleted_at.is_(None),
)
```

**Query (a) — project anchor (via migration 0030 link):**
```python
select(TimeEntry).join(Job, TimeEntry.job_id == Job.id).where(
    Job.project_id == project_id,
    TimeEntry.session_status.in_(_COMPLETED_STATUSES),
    TimeEntry.duration_seconds.is_not(None),
    TimeEntry.deleted_at.is_(None),
)
```
Select only the columns needed (`contractor_id`, `clocked_in_at`, `duration_seconds`) — no relationships touched, so `lazy="raise"` never trips.

**Query (b) — rates for the contractors seen in (a):**
```python
select(LaborRate).where(
    LaborRate.user_id.in_(contractor_ids),
    LaborRate.deleted_at.is_(None),
).order_by(LaborRate.user_id, LaborRate.effective_from, LaborRate.created_at)
```
Index usage: RLS injects the `company_id` filter, so `ix_labor_rates_company_user_effective (company_id, user_id, effective_from)` serves this query directly — the leading column matches the RLS predicate, `user_id` matches the IN, and `effective_from` matches the ORDER BY. **No new index needed** (rate tables are tiny: workers × a few changes/year). Confidence: HIGH.

**Cross-feature boundary:** the derivation imports `TimeEntry`/`Job` from `app.features.jobs.models` into the finance repository — sanctioned by CONTEXT ("keep it in the finance service layer"); precedent: `finance/repository.py` already imports `Job` and `TradeScope`.

### Pattern 2: Rate resolution rule (pure, unit-testable helper)

**The rule, stated once and reused everywhere:**
> The rate for a time entry is the `labor_rates` row for that worker with the greatest `effective_from` ≤ the entry's work day; among rows sharing that `effective_from`, the one with the latest `created_at` wins. If no row qualifies, the entry's seconds are **unrated**.

**Work-day convention (D-04 discretion, decided):** `work_date = clocked_in_at.astimezone(UTC).date()`. Rationale: `clocked_in_at` is `DateTime(timezone=True)` (asyncpg returns tz-aware UTC); no `Company`/`Job` timezone field exists anywhere in the schema (verified by grep), so UTC is the only deterministic choice without schema change. Document the convention in the helper docstring and use the same UTC date anywhere the work day is displayed. Known, acceptable edge: a late-evening US clock-in maps to the next UTC day — deterministic, and rates rarely change on adjacent days.

**Duplicate `effective_from` (discretion, decided):** allowed; latest `created_at` wins. This is the append-only-preserving correction path for a same-day typo (re-enter the correct amount, same date). History display shows all rows, so the superseded entry stays visible (success criterion 1). No unique constraint, no migration.

**Future-dated rates (discretion, decided):** allowed (a scheduled raise). The `effective_from <= work_date` predicate naturally ignores it until the date arrives. The Team page should label a future-dated row (e.g., "starts Aug 1").

**Money math policy (Pitfall 10):**
```python
SECONDS_PER_HOUR = Decimal("3600")
CENTS = Decimal("0.01")

def entry_labor_cost(duration_seconds: int, hourly_cost: Decimal) -> Decimal:
    hours = Decimal(duration_seconds) / SECONDS_PER_HOUR
    return (hours * hourly_cost).quantize(CENTS, rounding=ROUND_HALF_UP)
```
Quantize **per entry**, then sum quantized values — any future itemized labor view will sum to the same total. Never `float` anywhere on this path.

**Lookup implementation:** build `dict[user_id, list[(effective_from, created_at, hourly_cost)]]` sorted ascending; resolve with `bisect` on `effective_from` (list is already tie-broken by sort order — take the last qualifying element). Extract as a module-level pure function or `@staticmethod` so it unit-tests without a DB.

### Pattern 3: Labor-rates endpoints (append-only, single permission)

```
POST /labor-rates/            body: {user_id, hourly_cost, effective_from}   → 201  [finance.rates.manage]
GET  /labor-rates/?user_id=X  → full history, effective_from DESC, created_at DESC  [finance.rates.manage]
```
- **Both read and write gated `finance.rates.manage`** (CONTEXT default: zero-exception posture; workers/admin get 403 on their own rate too). Use the inline-gate style from `finance/router.py`: `await require_permission("finance.rates.manage")(current_user, db)`.
- **No PATCH, no DELETE** — append-only (D-01/D-02); corrections via backdating or same-day re-entry.
- Validation: `hourly_cost: Decimal = Field(..., gt=0, decimal_places=2, lt=Decimal("100000"))` (column is `Numeric(10,2)`); `effective_from: date` — past, today, and future all allowed.
- `user_id` is a **soft FK** (no DB constraint) — the service must verify the user exists in the company (one query against `users`, RLS-scoped) and 404 otherwise, or typo'd UUIDs create orphan rates that silently never match any time entry.
- `labor_rates` data must never appear in the mobile `/sync` delta or any non-rates endpoint (D-11). Nothing to remove — just don't add it.

### Pattern 4: Breakdown API shape (discretion, decided: new endpoints + additive rollup extension)

**Shared response schema:**
```python
class CategoryTotal(BaseModel):
    category_id: uuid.UUID
    category_name: str
    total: Decimal                      # Decimal-as-string on the wire

class LaborCostSummary(BaseModel):
    total: Decimal                      # rated labor cost, wage-only
    rated_seconds: int
    unrated_seconds: int                # D-05: never silently $0 — UI renders "X hrs unrated"
    basis: str = "unburdened"           # D-06 machine-readable marker for Phase 33/37

class CostBreakdownResponse(BaseModel):
    categories: list[CategoryTotal]     # from cost entries (materials/subcontractor/other/custom)
    labor: LaborCostSummary | None      # None on trade scopes
    labor_tracked_at_job_level: bool    # True only on trade-scope responses (D-08)
    grand_total: Decimal                # categories total + labor.total (rated only)
```
- `GET /jobs/{job_id}/cost-breakdown` — [finance.view]; 1 GROUP BY query (category totals) + 2 derivation queries = 3 round trips.
- `GET /trade-scopes/{trade_scope_id}/cost-breakdown` — [finance.view]; 1 GROUP BY query; `labor=None`, `labor_tracked_at_job_level=True`.
- `GET /projects/{project_id}/cost-entries` (existing) — extend `ProjectCostRollupResponse` **additively**: keep `total` (cost-entry sum) and `entries` exactly as-is, add `categories` (computed in Python from the already-fetched entries — zero extra queries), `labor`, `grand_total`. **Do not change `total`'s meaning** — mobile's `fetchProjectRollup` throws `FormatException` if `total`/`entries` shape changes, and un-updated clients must keep working.
- Category totals GROUP BY (one query, DRY helper shared by job/scope):
```python
select(CostCategory.id, CostCategory.name, func.sum(CostEntry.amount))
    .join(CostCategory, CostEntry.category_id == CostCategory.id)
    .where(CostEntry.job_id == job_id, CostEntry.deleted_at.is_(None))
    .group_by(CostCategory.id, CostCategory.name)
```
- Expose seconds as ints (exact) and let each UI format hours ("12.5 hrs unrated" = one-decimal division by 3600 for display only). Phase 33 consumes `unrated_seconds` as its incomplete-data signal — keep it machine-readable.

### Pattern 5: Web Team page rates UI

`team/page.tsx` already gates on `usePermissions()` (`users.view`, `users.create`). Add:
- `const canManageRates = can("finance.rates.manage")` — render a "Cost Rate" table column and per-row "Manage rate" action **only** when true (workers/admin never see the column; the API 403s regardless).
- `RateHistoryDialog` (mirrors `CreateUserDialog` conventions: dialog component under `team/_components/` or the finance feature): current rate headline, add-rate form (amount + effective date, defaulting to today), history table (effective_from DESC) with future-dated rows labeled.
- Hooks: `useLaborRates(userId)` keyed `["labor-rates", userId]`; `useAddLaborRate` invalidates `["labor-rates", userId]` **and** `["cost-entries"]` (rate changes move derived labor in every breakdown — the existing broad `invalidateAllCostEntries` prefix covers breakdown queries if they are keyed under `["cost-entries", "breakdown", ...]` — do that).

### Pattern 6: Web breakdown UI

- One shared `CostBreakdownSummary` component rendering category rows + labor row + total; props: `breakdown`, `variant: "job" | "trade-scope" | "project"`.
- Labor row: amount + `{unrated}` badge when `unrated_seconds > 0` ("12.5 hrs unrated" — hours visible per CONTEXT specifics, not just an icon) + Info icon opening the existing base-ui `Popover` with the unburdened text ("Wage cost only — excludes payroll tax, insurance, overhead."). **There is no `tooltip.tsx` component — do not invent one; reuse `popover.tsx`.**
- Trade-scope variant: labor row shows "Tracked at job level" note instead of a number (D-08).
- Mount points: inside the existing Costs `Card` on `jobs/[id]/page.tsx` (above `CostEntryList`), in `TradeScopeDetail.tsx`'s Costs section, and in `ProjectCostsCard` (which now reads `categories`/`labor`/`grand_total` from the extended rollup). All three surfaces are already gated `can("finance.view")` — no new gating needed for breakdown display.

### Pattern 7: Mobile breakdown (online-fetch via API, like the Phase 31 rollup total)

- `FinanceRepository` gains `fetchJobCostBreakdown(jobId)` / `fetchTradeScopeCostBreakdown(tradeScopeId)` returning a typed `CostBreakdown` Dart class parsed with `is` checks + `FormatException` (existing house style). **No Drift persistence for breakdown/labor data** — labor requires the API (D-11) and rates never touch the device; this matches `costRollupTotalProvider`'s online-fetch precedent. Amounts stay `String`s end-to-end (Pitfall 10).
- `fetchProjectRollup` parses the new optional fields **tolerantly** (absent → null breakdown) so the app doesn't hard-crash against an older backend; `total`/`entries` parsing stays strict as-is.
- Providers: `FutureProvider.autoDispose.family<CostBreakdown?, String>` per anchor; UI shows the cached list immediately and the breakdown when the fetch lands (offline → breakdown section shows a quiet "unavailable offline" state, never $0).
- Widget: `CostBreakdownSummary` above `CostListSection` in `job_detail_screen.dart` and `trade_scope_detail_screen.dart` (both already gate the section on `financePermissionProvider.canView`), and in `project_detail_screen.dart`'s rollup section. Labor caption (D-06): small `bodySmall` text under the labor row.

### Anti-Patterns to Avoid

- **Per-entry rate query in a loop** — instant CLAUDE.md violation; the 2-query design exists precisely to avoid this.
- **Materializing labor cost rows or snapshot columns** — contradicts locked D-01.
- **Changing `ProjectCostRollupResponse.total` semantics** — breaks mobile's strict parser and the "Total Spent" display on un-updated clients.
- **Computing labor on mobile from synced data** — rates must never reach the device (D-11).
- **Gating rate history reads with a weaker key than writes** — CONTEXT default is `finance.rates.manage` for both.
- **Building the derivation on `Job.trade_scope` traversal or booking joins** — labor is job-only; projects only via `jobs.project_id` (D-07).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Decimal JSON serialization | Custom field serializer | Pydantic v2 `Decimal` fields | Verified: `CostEntryResponse.amount` auto-serializes as string |
| Permission checks | Role-name checks (`require_admin`) | `require_permission("finance.*")` inline-gate style from `finance/router.py` | PITFALLS.md Pitfall 4; admin is excluded from finance.* by derivation |
| Query invalidation on web | Bespoke per-query invalidation | Existing `invalidateAllCostEntries` prefix (`["cost-entries"]`) + keyed breakdown queries under that prefix | Already handles "one write touches many aggregates" |
| Mobile API-shape validation | Bare `as` casts | Existing `is` + `FormatException` idiom in `finance_repository.dart` | CLAUDE.md type-safety rule; pattern already established |
| Tenant isolation for labor_rates | Manual company_id filters | RLS via `TenantScopedRepository` (`SET LOCAL app.current_company_id`) | Table already has FORCE RLS from migration 0032 |
| Currency display (web) | New formatter | `formatCurrency` in `web/src/lib/format.ts` | Exists; takes Decimal-as-string |

**Key insight:** the phase's only genuinely new algorithm is ~30 lines (rate resolution + per-entry cost). Everything else is composition of shipped patterns — plans should read as "extend X following Y's shape", not greenfield design.

## Common Pitfalls

### Pitfall 1: Reserved `labor` category double-count
**What goes wrong:** Phase 30 D-10 reserves the `labor` system category as "the target of derived labor cost", but **no guard exists today** — `create_cost_entry` accepts any `category_id`, and both AddCost UIs list all categories. A manual "labor" cost entry would appear in the category GROUP BY *and* labor is derived separately → the breakdown double-displays labor.
**How to avoid:** (a) service-layer guard in `create_cost_entry`/`update_cost_entry`: reject the `labor` system category with 422 ("Labor cost is derived from tracked time"); (b) filter `labor` out of the category pickers in `AddCostDialog` (web) and `add_cost_sheet.dart` (mobile); (c) in the breakdown, if legacy labor-categorized entries exist, sum them into the labor row (not a second labor line) so nothing hides.
**Warning signs:** two labor lines in a breakdown; grand_total ≠ categories + derived labor.

### Pitfall 2: Breaking mobile's strict rollup parser
**What goes wrong:** `fetchProjectRollup` throws `FormatException` unless `total` is a `String` and `entries` a `List`. Renaming/nesting these fields (e.g., wrapping in a `breakdown` envelope) crashes the shipped mobile Costs tab.
**How to avoid:** extend the response additively only; new fields optional in the mobile parser.

### Pitfall 3: Active/soft-deleted sessions leaking into labor
**What goes wrong:** summing `duration_seconds` without `session_status IN ('completed','adjusted')`, `duration_seconds IS NOT NULL`, and `deleted_at IS NULL` counts active or deleted sessions (D-03 violation; also `NULL` seconds poisons sums).
**How to avoid:** the three predicates live in one shared repository method used by both job and project derivation; a test clocks in without clocking out and asserts zero labor contribution.

### Pitfall 4: Timezone drift between derivation and display
**What goes wrong:** derivation uses UTC date but a UI shows the local-date of `clocked_in_at` next to a rate boundary — user sees "worked May 1" costed at the April 30 rate.
**How to avoid:** one documented convention (UTC date), used by derivation and any surface that explains a labor figure. State it in the helper docstring and the RESEARCH-referenced plan.

### Pitfall 5: `lazy="raise"` trip on TimeEntry relationships
**What goes wrong:** selecting full `TimeEntry` ORM rows and later touching `entry.job` or `entry.contractor` raises at runtime (both are `lazy="raise"`).
**How to avoid:** select only the needed columns (`contractor_id`, `clocked_in_at`, `duration_seconds`) as tuples — the derivation needs no relationships.

### Pitfall 6: Unrated hours silently valued at $0 (D-05 / PITFALLS.md Pitfall 9)
**What goes wrong:** `SUM()` naturally treats missing rates as 0; totals look complete when they aren't.
**How to avoid:** the derivation returns `unrated_seconds` explicitly; every UI renders "X hrs unrated" whenever it's > 0; tests assert the flag appears and that backdating a rate (D-02) converts unrated → rated.

### Pitfall 7: Rates data leaking beyond `finance.rates.manage`
**What goes wrong:** convenience additions (e.g., current rate on `UserResponse`, rates in `/sync`) leak the most sensitive data in the system to workers/admin.
**How to avoid:** rates are only ever readable via `GET /labor-rates/` gated `finance.rates.manage`; the breakdown responses expose derived **cost totals** (finance.view) but never a rate or a per-worker figure. E2E asserts 403 for admin/worker/contractor on both rates endpoints.

## Code Examples

### Success criterion 2 test shape (CONTEXT specifics, verbatim requirement)
```python
# backend/tests/test_phase_32_e2e.py — the phase's keystone test
async def test_later_rate_change_does_not_rewrite_history(...):
    # rate A ($30) effective June 1; completed 8h time entry on June 10
    # breakdown → labor.total == "240.00"
    # POST rate B ($40) effective today (July)
    # breakdown again → labor.total STILL "240.00"

async def test_backdated_rate_fills_unrated_days(...):
    # completed 4h entry on May 5, no rate → unrated_seconds == 14400, labor.total == "0.00"
    # POST rate $25 effective May 1 (backdated, D-02)
    # breakdown → unrated_seconds == 0, labor.total == "100.00"
```

### Rate resolution helper (pure function, unit-tested without DB)
```python
# app/features/finance/service.py (or a labor_derivation module in the same package)
def resolve_rate_for_work_date(
    sorted_rates: list[RateRow],  # ascending (effective_from, created_at)
    work_date: date,
) -> Decimal | None:
    """Latest effective_from <= work_date wins; created_at breaks same-day ties.

    Work date convention: UTC date of clocked_in_at (documented, deterministic).
    Returns None when no rate covers the work date (caller counts unrated seconds).
    """
    index = bisect_right(sorted_rates, work_date, key=lambda r: r.effective_from)
    return sorted_rates[index - 1].hourly_cost if index else None
```

### Inline permission gate (existing house style — copy exactly)
```python
# Source: backend/app/features/finance/router.py (Phase 31 pattern)
@router.post("/labor-rates/", response_model=LaborRateResponse, status_code=status.HTTP_201_CREATED)
async def create_labor_rate(
    data: LaborRateCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> LaborRateResponse:
    await require_permission("finance.rates.manage")(current_user, db)
    ...
```

### Web hook keying so rate writes refresh breakdowns
```typescript
// Source: web/src/features/finance/hooks.ts conventions
export function useJobCostBreakdown(jobId: string) {
  return useQuery({
    queryKey: ["cost-entries", "breakdown", "job", jobId],  // under the invalidation prefix
    queryFn: () => fetchJobCostBreakdown(jobId),
    enabled: !!jobId,
  });
}
```

## State of the Art

| Old Approach (rejected here) | Current Approach (this phase) | Why |
|------------------------------|-------------------------------|-----|
| Mutable `User.hourly_rate` live join | Append-only effective-dated `labor_rates` lookup | Locked at roadmap stage; PITFALLS.md Pitfall 7 |
| Snapshotting rate onto cost rows | Computed-on-read (D-01) | Effective-dated append-only table makes snapshots redundant — an equally deterministic, simpler design |
| `SUM()` treating missing data as $0 | Explicit `unrated_seconds` (D-05) | PITFALLS.md Pitfall 9; Phase 33's MARG-03 builds on it |

## Open Questions

1. **Should the Team page show the current rate inline in the table for all rows, or only inside the dialog?**
   - What we know: D-09 requires "rate field + full history per member" gated by the permission; the users list endpoint doesn't return rates.
   - What's unclear: inline display needs either N per-row queries (bad) or a batch `GET /labor-rates/` returning current rates for all users (one query, gated).
   - Recommendation: add an optional no-`user_id` mode to `GET /labor-rates/` returning each user's current effective rate in one query (uses the same index), so the column renders without N+1. Planner may instead keep rates dialog-only for a smaller slice — both satisfy D-09.
2. **Legacy manual `labor`-category cost entries.**
   - What we know: nothing blocks them today; real deployments may have zero (feature is days old).
   - Recommendation: guard going forward (Pitfall 1) and fold any existing ones into the labor row; no data migration.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Backend venv Python | pytest, ruff | ✓ | 3.12.12 (`backend/.venv/bin/python`) | — |
| Node.js | web build/lint/jest/playwright | ✓ | v20.18.1 | — |
| Flutter | mobile tests/analyze | ✓ | 3.41.4 stable | — |
| Docker (postgres for tests) | backend pytest (`contractorhub_test` DB) | CLI present; **no containers observed running** | — | `docker compose up -d` before running backend tests |
| New packages/services | — | n/a | — | none needed — phase adds zero dependencies |

**Missing dependencies with no fallback:** none.
**Note for executor:** start the Docker Postgres before backend test runs; no `docker compose up migrate` needed (no new migration).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Backend | pytest + pytest-asyncio + httpx ASGI client (config in `backend/pyproject.toml`, fixtures in `backend/tests/conftest.py` — `seed_two_tenants`, `clean_tables`, JWT via `create_access_token`) |
| Web unit | Jest (`web/jest.config.ts`), tests in `__tests__/` dirs |
| Web E2E | Playwright (`web/playwright.config.ts`), specs in `web/tests/*.spec.ts` |
| Mobile | flutter_test + mocktail + Drift in-memory; E2E in `mobile/test/e2e/` |
| Quick run | `cd backend && .venv/bin/python -m pytest tests/test_phase_32_e2e.py -x -q` |
| Full suites | `cd backend && .venv/bin/python -m pytest` · `cd web && npm test && npx playwright test` · `cd mobile && flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| COST-04 | POST rate + effective date; history preserved & ordered; 403 for admin/worker; duplicate-day tie-break; future-dated allowed | integration | `pytest tests/test_phase_32_e2e.py -k rate -x` | ❌ Wave 0 |
| COST-04 | Team page rate column/dialog gated `finance.rates.manage`; history renders | unit (Jest) + E2E (Playwright) | `npm test -- rate-history` · `npx playwright test tests/phase-32-labor-rates.spec.ts` | ❌ Wave 0 |
| COST-05 | Rate resolution rule (boundary dates, ties, unrated, UTC work-day) | unit (pure fn) | `pytest tests/unit/test_labor_derivation.py -x` | ❌ Wave 0 |
| COST-05 | Success criterion 2: later rate change leaves history unchanged; backdated rate fills unrated; active sessions excluded | integration | `pytest tests/test_phase_32_e2e.py -k derivation -x` | ❌ Wave 0 |
| COST-06 | Job/scope/project breakdowns: category totals, labor row, `labor_tracked_at_job_level` on scopes, grand_total, `total` backward-compat, 403 matrix, RLS isolation | integration | `pytest tests/test_phase_32_e2e.py -k breakdown -x` | ❌ Wave 0 |
| COST-06 | Web breakdown rendering incl. "X hrs unrated" badge + unburdened popover + scope note | unit (Jest) + E2E (Playwright) | `npm test -- cost-breakdown` · Playwright spec above | ❌ Wave 0 |
| COST-06 | Mobile breakdown fetch/parse (tolerant optional fields) + widget render + offline state | unit + widget + E2E | `flutter test test/e2e/phase_32_labor_cost_e2e_test.dart` | ❌ Wave 0 |

Manual-only residue: visual polish of popover/caption placement (UAT `automated: false`); everything else automatable per CLAUDE.md UAT rules (mock Dio at `MockDioClient.instance`, seed Drift, assert rendering).

### Sampling Rate
- **Per task commit:** the task's own test file (`pytest tests/test_phase_32_e2e.py -x -q` / `npm test -- <pattern>` / `flutter test <file>`) + platform linters (ruff / eslint+tsc / dart analyze).
- **Per wave merge:** full platform suite for the touched platform(s).
- **Phase gate:** all three full suites green + Playwright phase spec before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `backend/tests/test_phase_32_e2e.py` — COST-04/05/06 integration (naming convention: `test_phase_{N}_e2e.py`; copy `_seed_cost_categories`/`_token` helpers from `test_phase_31_e2e.py`)
- [ ] `backend/tests/unit/test_labor_derivation.py` — pure rate-resolution unit tests (a `tests/unit/` dir exists)
- [ ] `web/src/features/finance/__tests__/` additions + `web/tests/phase-32-labor-rates.spec.ts` (Playwright; mirror `cost-capture.spec.ts` auth/nav approach)
- [ ] `mobile/test/e2e/phase_32_labor_cost_e2e_test.dart` (naming: `phase_{N}_{feature}_e2e_test.dart`)
- Framework install: none — all four harnesses already configured and in use.

## Sources

### Primary (HIGH confidence — direct codebase inspection, 2026-07-26)
- `backend/app/features/finance/{models,repository,service,router,schemas}.py` — LaborRate schema + index, rollup pattern, inline permission gates, Decimal serialization
- `backend/app/features/jobs/models.py` (TimeEntry L483) — columns, session_status check constraint, `lazy="raise"` relationships
- `backend/migrations/versions/0030_job_project_link.py`, `0032_financial_schema_and_rbac.py` — jobs.project_id, labor_rates DDL + FORCE RLS
- `backend/app/core/permissions.py` — `_FINANCE_ONLY_KEYS` incl. `finance.rates.manage`; PM defaults
- `backend/app/core/security.py` L229 — `require_permission` shape
- `web/src/app/(dashboard)/team/page.tsx`, `web/src/features/finance/{hooks,types,api}.ts`, `components/ProjectCostsCard.tsx`, `jobs/[id]/page.tsx` — mount points, gating, query keys, Decimal-as-string types
- `web/src/components/ui/` — confirms Popover exists (base-ui), **no Tooltip component**
- `mobile/lib/features/finance/**` — FinanceRepository strict parsing, cost_providers, CostListSection, financePermissionProvider
- `backend/tests/test_phase_31_e2e.py` + `backend/tests/` listing — fixture/naming conventions
- `.planning/phases/30-.../30-CONTEXT.md` D-10 — `labor` reserved category
- `.planning/research/PITFALLS.md` (Pitfalls 1, 2, 7, 9, 10), `.planning/research/ARCHITECTURE.md` (Patterns 2/3)

### Secondary (MEDIUM)
- PostgreSQL composite-index/RLS predicate interaction and `bisect`-based effective-dated lookup — standard, verified against the actual index definition; no external fetch needed.

### Tertiary (LOW)
- None — no claims rest on unverified web sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; every building block verified in-repo
- Architecture (derivation/API shape): HIGH — grounded in shipped rollup/permission/parsing patterns; the two discretionary decisions (UTC work day, created_at tie-break) are reasoned and reversible
- Pitfalls: HIGH — Pitfall 1 (labor category guard gap) verified by grep; parser strictness verified by reading `finance_repository.dart`

**Research date:** 2026-07-26
**Valid until:** 2026-08-26 (internal-codebase research; invalidated only by changes to the finance feature or Costs UIs)
