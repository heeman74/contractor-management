# Phase 32: Labor Rates and Cost Rollup - Context

**Gathered:** 2026-07-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Owner/PM can set a worker's hourly cost rate with an effective date (history
preserved and visible), the system derives labor cost automatically from tracked
time × the rate effective on the day worked, and Owner/PM can view itemized
costs per job, per trade scope, and per project broken out by category
(labor / materials / subcontractor / other) with totals. (COST-04, COST-05, COST-06.)

The `LaborRate` schema (append-only, effective-dated) already exists from
Phase 30. Phase 31 already shipped cost-entry capture and Costs sections on
job / trade-scope / project screens (web + mobile). This phase builds: rate
management UI + endpoints, the labor-derivation logic, and the category
breakdown layered onto the existing Costs sections.

NOT in this phase: burden rates/multipliers (v4.0 ships unburdened wage-only
labor, explicitly flagged), trade-scope/task-level time tracking (deferred),
margins (33), budgets/alerts (34), dashboard charts (35), AI (36/37).

</domain>

<decisions>
## Implementation Decisions

### Labor cost derivation
- **D-01:** **Computed-on-read.** Labor cost is calculated at query time:
  `duration_seconds` × the rate whose `effective_from` covers the work day,
  looked up from the append-only `labor_rates` table. No materialized labor
  CostEntry rows, no snapshot columns, no recompute machinery. Time-entry
  adjustments and rate backdating are automatically reflected. This satisfies
  success criterion 2 (a later rate change never rewrites past labor cost)
  because rates are effective-dated and append-only — a new rate effective today
  cannot alter the rate that was effective on a past work day.
- **D-02:** **Backdated rates are allowed.** Owner/PM can enter a rate with a
  past `effective_from` (e.g., worker started May 1, rate entered May 10
  effective May 1) — labor cost for those days fills in retroactively. This is
  the sanctioned fix for unrated hours; it is deterministic under computed-on-read.
- **D-03:** **Completed sessions only.** Labor cost includes only clocked-out
  time entries with a final `duration_seconds` (session_status completed or
  adjusted). Active sessions never contribute to cost totals.
- **D-04:** The work day for rate lookup is derived from the time entry's
  clock-in date. (Exact timezone handling: Claude's discretion, but must be
  deterministic and documented.)

### Missing-rate handling
- **D-05:** **Explicit "unrated hours" flag — never silent $0.** When tracked
  time has no rate effective on the work day, labor totals show the computed
  amount for rated hours plus a visible indicator of unrated hours (e.g.,
  "12.5 hrs unrated"). Unrated hours are never valued at $0 silently and never
  hidden. This is the honest-data posture Phase 33's incomplete-data flag
  (MARG-03) builds on, and it nudges Owner/PM toward backdating a rate (D-02).
- **D-06:** **Unburdened labeling via info affordance.** Labor category rows and
  totals carry an info tooltip (web) / small caption (mobile) reading to the
  effect of "Wage cost only — excludes payroll tax, insurance, overhead."
  Carried from STATE.md blocker + research PITFALLS.md Pitfall 2: v4.0 labor is
  wage-only; the UI must say so where labor figures appear.

### Time-tracking scope
- **D-07:** **Labor stays job-only for v4.0.** Labor cost derives exclusively
  from existing job-anchored `TimeEntry` rows; projects get labor via the
  `jobs.project_id` link (migration 0030). No TimeEntry schema change, no new
  clock-in surfaces. Resolves the STATE.md open blocker.
- **D-08:** **Trade-scope itemized views show a labor row with a "tracked at
  job level" note** — not an omitted row, not $0. Materials/subcontractor/other
  totals show real numbers; the labor line is honest about why there's no
  scope-level number.

### Rate management UI
- **D-09:** **Web Team page only** (per Phase 30 D-07 — no new nav surface, and
  no mobile rates editor this phase). Rate field + full effective-dated history
  per member, visible/editable only with `finance.rates.manage` (Phase 30
  D-07/D-08: workers never see their own rate; admin excluded).

### Itemized breakdown presentation
- **D-10:** **Extend the existing Phase 31 Costs sections** on job detail,
  trade-scope detail, and project screens with a category-totals summary
  (labor / materials / subcontractor / other + total). No dedicated breakdown
  screen/tab — one cost surface per entity, reusing shipped components and
  permission gating.
- **D-11:** **Both web and mobile** get the category breakdown, matching
  Phase 31's platform pattern. Labor figures come from the backend API — mobile
  does not compute rates locally and labor_rates data never syncs to the device
  (rates are the most sensitive data in the system per Phase 30).

### Claude's Discretion
- Rate-editor UX details: validation, future-dated rates, duplicate
  effective_from handling, history display layout on the Team page.
- API shape: whether breakdown totals extend the existing rollup endpoint or
  add new endpoints; response serialization (mirror Decimal-as-string).
- Timezone convention for mapping `clocked_in_at` to a work date (D-04) —
  deterministic and consistent between derivation and display.
- Query/index design for the derivation join (effective-dated lookup per
  research ARCHITECTURE.md); whether to add a covering index.
- Mobile: how breakdown data is fetched/cached (Phase 31's
  FinanceRepository.fetchProjectRollup pattern) — noting labor requires the
  API, so breakdown is online-fetched like the Phase 31 project rollup.
- Which permission gates the rates endpoints beyond `finance.rates.manage`
  reads/writes (e.g., whether rate history read requires the same key —
  default: yes, per Phase 30 D-08 zero-exception posture).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 30/31 foundation (locked decisions this phase builds on)
- `.planning/phases/30-financial-schema-foundation-and-rbac-audit/30-CONTEXT.md` — D-07/D-08 (labor rates on Team page, zero rate visibility exceptions), D-10 (`labor` reserved category), D-05 (rollup rule), finance permission keys
- `.planning/phases/31-actual-cost-capture/31-CONTEXT.md` — Costs-section placements (D-02/D-03), gating restatement, platform pattern
- `backend/app/features/finance/models.py` — `LaborRate` (user_id, hourly_cost, effective_from, ix_labor_rates_company_user_effective) already built; `CostEntry`, `CostCategory`
- `backend/app/features/finance/service.py` + `repository.py` + `router.py` — cost CRUD + `rollup_for_project` single-round-trip pattern to extend with category totals + labor

### Research (grounds the derivation decisions)
- `.planning/research/PITFALLS.md` — Pitfall 1 (TimeEntry has no trade-scope/project anchor — resolved by D-07 job-only), Pitfall 2 (unburdened labor labeling — D-06), Pitfall 7 (retroactive rate rewrites — addressed by append-only effective-dated lookup, D-01), Pitfall 9 (missing data ≠ $0 — D-05)
- `.planning/research/ARCHITECTURE.md` — effective-dated lookup and rollup integration architecture

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — COST-04, COST-05, COST-06
- `.planning/ROADMAP.md` — Phase 32 goal + 3 success criteria

### Code that constrains this phase
- `backend/app/features/jobs/models.py` (TimeEntry, line ~483) — job_id + contractor_id + duration_seconds + session_status; the derivation source. `adjustment_log` exists for admin edits.
- `backend/migrations/versions/0030_job_project_link.py` — jobs.project_id used for project-level labor rollup
- `backend/app/core/permissions.py` — `finance.view` / `finance.manage` / `finance.rates.manage`
- `web/src/app/(dashboard)/team/` — Team page where the rates UI attaches
- Web cost components from Phase 31 (`CostEntryList`, project/job/scope Costs sections under `web/src/app/(dashboard)/projects/`) — extended with category totals
- Mobile finance feature (`mobile/lib/features/finance/`) — `cost_providers.dart`, `cost_list_section.dart`, `finance_repository.dart` (fetchProjectRollup pattern), `financePermissionProvider` (31-05)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `LaborRate` model + composite index (company, user, effective_from) — schema is done; this phase adds endpoints + UI + derivation queries
- `rollup_for_project` (single DB round trip, entries + total) — the pattern to extend for category breakdowns
- Phase 31 Costs sections on all three entity screens (web + mobile) — the surfaces the breakdown lands on
- `financePermissionProvider` (mobile) + `usePermissions()` (web) — existing finance gating to reuse; rates UI needs `finance.rates.manage` specifically
- `require_permission()` dependency — gate rates endpoints with `finance.rates.manage`, breakdown reads with `finance.view`

### Established Patterns
- Money = Numeric/Decimal, string-serialized (quotes/invoices/cost entries) — labor amounts must match
- Effective-dated lookup has no query precedent yet — labor_rates is the first; the derivation query (rate effective on work day per time entry) is the phase's core new backend logic
- Mobile finance reads that need server computation go through FinanceRepository API fetch (31-05 rollup pattern), not local Drift computation

### Integration Points
- `TimeEntry` (jobs feature) × `LaborRate` (finance feature) — the derivation join crosses feature boundaries; keep it in the finance service layer
- `jobs.project_id` → project labor rollup; trade-scope views get no labor number (D-08 note)
- Phase 33 will consume the unrated-hours flag (D-05) as its incomplete-data signal — shape the API response so margins can reuse it
- Phase 37 (AI quote planning) depends on this phase's labor cost data being honest (unburdened-labeled, unrated-flagged)

</code_context>

<specifics>
## Specific Ideas

- Success criterion 2 verbatim: "a later rate change does not retroactively
  rewrite past labor cost" — the automated test should add a new rate effective
  today and assert a completed historical job's labor total is unchanged; and
  separately assert a *backdated* rate (D-02) DOES fill in previously unrated days.
- Unrated-hours indicator phrasing like "12.5 hrs unrated" — hours visible, not
  just a warning icon.
- Unburdened caption wording to the effect of: "Wage cost only — excludes
  payroll tax, insurance, overhead."

</specifics>

<deferred>
## Deferred Ideas

- **Trade-scope/task-level time tracking** (mobile clock-in against trade scopes
  or tasks, TimeEntry trade_scope anchor) — deliberately deferred out of v4.0;
  would unlock real trade-scope labor cost. Revisit as its own phase if
  scope-level labor becomes a priority.
- **Mobile rate management** (rates editor in mobile admin area) — deferred;
  rates stay a web Team page task this milestone.
- **Burden rates / burden multiplier** (per-company configurable) — explicitly
  out of v4.0 scope per STATE.md; PITFALLS.md Pitfall 2 documents the design
  when it lands. The D-06 unburdened labeling is the v4.0 mitigation.

</deferred>

---

*Phase: 32-labor-rates-and-cost-rollup*
*Context gathered: 2026-07-26*
