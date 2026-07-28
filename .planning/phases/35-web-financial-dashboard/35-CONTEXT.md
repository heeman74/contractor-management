# Phase 35: Web Financial Dashboard - Context

**Gathered:** 2026-07-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Owner/PM can see financial health at a glance on web: a finance-gated
"Financials" area with a company-wide rollup (portfolio tiles, per-project
budget-vs-actual, attention list) and per-project drill-down (margin trend,
per-scope budget-vs-actual, category mix) — living alongside the existing v2.0
Reports dashboard with the same navigation and visual conventions. Users
without finance.* see no Financials nav item and cannot reach any financial
dashboard route. (MARG-04.)

All figures come from the shipped Phase 31–34 queries — this phase adds
time-bucketed aggregation, company-wide rollup endpoints, and the charts UI.

NOT in this phase: mobile dashboard, AI analysis (36), quote planning (37),
snapshot tables, composite risk scoring, any change to margin/budget math,
any change to the ungated Reports dashboard beyond adding the sibling nav item.

</domain>

<decisions>
## Implementation Decisions

### Margin trend
- **D-01:** **Reconstructed from dated records** — cumulative margin over time
  computed from records that already carry dates: cost `incurred_date`,
  time-entry work days (UTC convention from Phase 32), invoice dates, approved
  quote dates. No snapshot table; works retroactively from day one; stays
  consistent with computed-on-read. Incomplete-data status carries into the
  trend honestly.
- **D-02:** **Monthly buckets.** Cumulative revenue-to-date minus cost-to-date
  per month. (Exact bucket-edge and revenue-basis-over-time semantics: Claude's
  discretion, but deterministic and documented — e.g., quote-basis revenue
  appears in the bucket of quote approval, invoice revenue in the bucket of
  issuance, consistent with Phase 33 D-01 resolution at each point in time or
  a documented simplification.)

### Performance
- **D-03:** **Computed-on-read, settled by data.** No cache/denormalization.
  The phase MUST include a measured performance check (seeded multi-project
  company; company-rollup endpoint under a stated latency budget) so the
  Phase 33 D-11 deferral is closed with evidence, not assumption. If the test
  proves the budget is exceeded, caching becomes a follow-up decision — not
  silently added.

### Structure & navigation
- **D-04:** **Dedicated "Financials" nav item**, sibling to Reports in the
  sidebar, visible only with `finance.view`; the route guard blocks direct
  navigation without permission (redirect/404 — exact behavior consistent with
  existing permission-gated routes). The ungated Reports page is untouched
  except for the sibling nav entry (Phase 30 D-06 boundary).
- **D-05:** **Company overview + project drill-down:** `/financials` = company
  rollup + project list; `/financials/[projectId]` = that project's charts.
  Deep-linkable; same layout/visual conventions as Reports (chart-card,
  skeleton, Recharts 3.8).

### Chart content
- **D-06:** **Company overview ships:** portfolio margin summary tiles
  (revenue, cost, margin $ ·%), budget-vs-actual bars per project, and an
  attention list.
- **D-07:** **Project drill-down ships:** margin trend line (D-01/D-02),
  budget-vs-actual per trade scope, cost category mix (labor / materials /
  subcontractor / other — the Phase 32 breakdown).
- **D-08:** **Attention list ranking — ordered tiers, shipped signals only:**
  budget overruns first (worst % over at top), then 80%+ warnings, then
  incomplete-data projects. No composite scoring (that's Phase 36 AI
  territory). Show all qualifying projects.

### Honest aggregates
- **D-09:** **Include + count badge.** Flagged (incomplete-data) projects'
  figures roll into portfolio totals, and summary tiles carry a badge like
  "3 projects with incomplete data" that ties to the attention list. Never
  exclude — an excluded project misstates the portfolio (Phase 33 honesty
  posture at aggregate level). Quote-basis (estimated) revenue in aggregates
  follows the same labeling spirit — surface the estimated share (exact
  presentation: Claude's discretion within UI-SPEC).

### Filtering
- **D-10:** **Trend window only.** The margin-trend chart gets a Reports-style
  range selector (e.g., 3m / 6m / 12m / all); portfolio totals and
  budget-vs-actual stay all-time — budgets and margins are lifetime-of-project
  numbers, and date-filtered budget-vs-actual would mislead.

### Post-research decisions (added 2026-07-28 after 35-RESEARCH.md open questions)
- **D-11:** **Attention tiers use LIVE threshold state** — recomputed from
  current spent/total via the shipped `budget_math.crossed_thresholds`, NOT the
  `warning_fired_at`/`overrun_fired_at` alert-claim timestamps (those null on
  re-arm and persist after spend drops; using them would let the list
  contradict the charts beside it). Refines D-08's "shipped signals" to mean
  shipped *functions*, not the alert-dedup columns.
- **D-12:** **All projects roll into portfolio totals regardless of status**
  (D-09 honesty posture); the response carries each project's status so the UI
  can group/de-emphasize drafts or completed projects visually.

### Claude's Discretion
- Trend bucket-edge semantics and how revenue basis resolves per bucket (D-02
  note); percent/rounding consistent with shipped conventions.
- Endpoint shapes (company rollup + project financials + trend — new gated
  endpoints under the finance feature; Decimal-as-string).
- Latency budget number for the D-03 performance test (state it in the plan).
- Chart composition details (Recharts config, colors per the dataviz/UI-SPEC
  pass, empty/loading/error states per Reports skeleton conventions).
- Attention-list row content; project-list columns on /financials.
- Route-guard implementation (layout-level check vs middleware) consistent
  with existing gated routes.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Financial foundation (all figures come from these)
- `.planning/phases/33-profit-margin-tracking/33-CONTEXT.md` — margin/revenue rules (D-01 invoices-else-quote, D-13 pre-tax, incomplete flags D-05..D-07)
- `.planning/phases/34-budgeting-and-overrun-alerts/34-CONTEXT.md` — budget-vs-actual, threshold state, alert types
- `backend/app/features/finance/` — `margin_math.py`, `budget_math.py`, repository traversal queries, breakdown/rollup/budget response blocks; the queries the new endpoints compose
- `.planning/phases/30-financial-schema-foundation-and-rbac-audit/30-CONTEXT.md` — D-06 gating boundary (Reports ungated, new financial surfaces gated)

### Reporting conventions being matched (SC2)
- `web/src/app/(dashboard)/reports/` — page structure, `_components/` (chart-card.tsx, revenue-chart.tsx, date-range-filter.tsx, reports-skeleton.tsx, reports-dashboard.tsx) — the visual/navigation conventions to mirror
- Recharts 3.8 (web/package.json) — the chart library; no new chart dependency
- Web sidebar/nav component + `usePermissions()` — where the gated Financials item lands

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — MARG-04
- `.planning/ROADMAP.md` — Phase 35 goal + 3 success criteria

### Research
- `.planning/research/PITFALLS.md` — #9 (aggregate honesty), performance notes (recompute-vs-cache table)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Reports dashboard components (chart-card, date-range-filter, skeletons) — the Financials pages compose these conventions with Recharts
- Phase 33/34 finance queries + response blocks — company rollup composes per-project calls into bounded batch queries (no N+1 across projects)
- `usePermissions()` + existing gated-route patterns — nav visibility + route guard
- `FinanceFlagChip` and honest-data vocabulary — the incomplete badge at aggregate level

### Established Patterns
- Money Decimal-as-string; computed-on-read; finance.view read gating; additive responses
- Playwright: login through UI + SPA-navigate (32-04 lesson) — route-guard tests must cover direct-URL access denial

### Integration Points
- Phase 36 (AI profitability) will consume the same company-rollup/trend data — shape endpoints so the AI reads pre-computed aggregates (research performance note: never feed the AI raw rows)
- Sidebar nav — one new gated entry; everything else untouched

</code_context>

<specifics>
## Specific Ideas

- SC3 keystone test: a non-finance user sees no Financials nav item AND direct navigation to /financials and /financials/[id] is blocked (both assertions, web e2e)
- Portfolio badge phrasing like "3 projects with incomplete data"
- Attention list tiers: overrun (worst % first) → warning → incomplete

</specifics>

<deferred>
## Deferred Ideas

- Margin snapshot table / cached aggregates — only if the D-03 performance test fails its budget
- Composite attention scoring — Phase 36 AI
- Mobile financial dashboard — not in v4.0 scope (web-only per MARG-04)
- Date-filtering portfolio totals/budget-vs-actual — rejected as misleading

</deferred>

---

*Phase: 35-web-financial-dashboard*
*Context gathered: 2026-07-28*
