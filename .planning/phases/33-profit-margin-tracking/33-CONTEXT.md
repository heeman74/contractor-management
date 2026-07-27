# Phase 33: Profit Margin Tracking - Context

**Gathered:** 2026-07-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Owner/PM can view a trustworthy profit margin (revenue minus actual cost) for
any job or trade scope, plus a project-level margin rollup aggregating across
trade scopes — with an explicit "incomplete data" flag wherever cost data is
missing, never a fabricated number. (MARG-01, MARG-02, MARG-03.)

Builds directly on the shipped cost side: Phase 31 cost entries + Phase 32
derived labor and category breakdowns. This phase adds the revenue side of the
equation and the margin math/display.

NOT in this phase: budgets/alerts (34), dashboard charts (35), AI profitability
analysis (36), caching/denormalization (revisit in 35 if needed), any change to
cost capture or labor derivation.

</domain>

<decisions>
## Implementation Decisions

### Revenue definition
- **D-01:** **Invoices, else approved quote.** Revenue for a job/scope = sum of
  its invoice totals; if no invoice exists yet, fall back to the approved quote
  total. Once ANY invoice exists, invoices win outright (no mixing, no max()).
  Per research PITFALLS.md #3: quote line items NEVER count as cost, and invoice
  line items never feed the cost side.
- **D-02:** **All issued invoices count** — unpaid + partially_paid + paid
  (billed/accrual basis). Margin reflects job economics, not collections.
- **D-03:** **Approved quotes only** qualify for the fallback. Draft/sent/viewed
  are proposals; declined/expired are dead; revised quotes were superseded.
- **D-04:** **Quote-based margin is visibly labeled** with a caption to the
  effect of "Based on approved quote — not yet invoiced". Invoice-backed margin
  carries no label. Phase 36's AI must receive this estimated-vs-billed
  distinction with the margin data.

### Incomplete-data flag (success criterion 3)
- **D-05:** The flag triggers on exactly two conditions:
  1. **Unrated labor hours** — tracked time with no effective rate on the work
     day (reuse Phase 32's unrated-seconds signal from the breakdown API).
  2. **Zero cost entries + zero derived labor while revenue exists** — the
     research Pitfall 9 legacy case, which would otherwise fabricate a ~100%
     margin.
- **D-06:** **Partial number + flag.** When flagged, the margin computed from
  available data still displays, with the incomplete-data flag beside it —
  matching the Phase 32 pattern of rated-labor totals + "N hrs unrated" chip.
  Never suppress the number, never show an unflagged fabricated one.
- **D-07:** **No revenue source (no invoice AND no approved quote) is NOT an
  incomplete-data flag.** In that case the margin figure is simply absent —
  costs display as they already do, with a neutral "no revenue recorded"-style
  note instead of a margin (exact copy: Claude's discretion). The flag means
  "cost data quality problem", not "billing hasn't started".

### Presentation
- **D-08:** **Margin extends the existing Costs sections** on job detail,
  trade-scope detail, and project screens — the same finance-gated surfaces
  Phases 31/32 built. No separate Margin card, no new nav. Both **web and
  mobile**, matching the established platform pattern.
- **D-09:** **Both $ and %** displayed together (e.g. "$4,200 · 21%"). Margin
  dollars = revenue − cost; percentage = margin / revenue.
- **D-10:** Margins are gated by `finance.view` (carried from Phase 30 D-06:
  finance.* gates margins; revenue surfaces themselves — quotes, invoices,
  reports — stay ungated as today). Mobile fetches margin via API like the
  Phase 32 breakdown; no rate or margin data persisted to Drift.

### Compute strategy
- **D-11:** **Computed-on-read.** Margin derives at query time from the shipped
  breakdown/derivation queries plus bounded revenue queries — same posture as
  Phase 32 labor derivation. No denormalized margin table, no invalidation
  machinery. Revisit caching in Phase 35 if dashboard latency demands it
  (research suggests the threshold is hundreds of rows per project).

### Project rollup
- **D-12:** Project margin rollup follows the Phase 30 D-05 traversal: revenue
  and cost from trade-scope-anchored records + records on jobs where
  `job.project_id` = project. Per research PITFALLS.md #1 mitigation, revenue
  and cost MUST resolve through the same traversal so mixed job/scope records
  net out correctly — one integration test must assert this explicitly.
  Project-level incomplete flag = any contributing job/scope is flagged.

### Post-research decisions (added 2026-07-27 after 33-RESEARCH.md open questions)
- **D-13:** **Pre-tax revenue.** Margin revenue = subtotal − discount, excluding
  tax — applied identically to the invoice and quote legs. Consistent with every
  existing revenue aggregation in the codebase (reports stay comparable).
- **D-14:** **Project-level quotes count as fallback only.** A project-anchored
  approved quote (job_id and trade_scope_id both NULL) contributes to project
  revenue only when the entire project has zero invoices — the D-01
  invoices-win-outright rule applied at project level.

### Claude's Discretion
- Exact API shape (extend the Phase 32 breakdown endpoints/response vs sibling
  margin endpoints); Decimal-as-string serialization per convention.
- Percentage precision/rounding and division-by-zero handling (zero revenue).
- Exact flag/label/no-revenue copy and visual treatment (follow the Phase 32
  UI-SPEC conventions: chips/captions, no destructive red for informational
  flags) — a Phase 33 UI-SPEC pass will lock the strings.
- How the estimated-vs-billed revenue basis is represented in API responses
  (e.g. a `revenue_basis: invoiced | quoted` field) for UI labels and Phase 36.
- Bounded-query design for revenue aggregation (no N+1 per CLAUDE.md).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 30/31/32 foundation (locked decisions this phase builds on)
- `.planning/phases/30-financial-schema-foundation-and-rbac-audit/30-CONTEXT.md` — D-05 rollup traversal, D-06 revenue-not-gated boundary, finance permission keys
- `.planning/phases/32-labor-rates-and-cost-rollup/32-CONTEXT.md` — computed-on-read posture, unrated-hours flag (this phase's incomplete signal), job-only labor, platform pattern
- `.planning/phases/32-labor-rates-and-cost-rollup/32-UI-SPEC.md` — copy/badge/caption conventions to extend (unrated chip, unburdened popover)
- `backend/app/features/finance/` — breakdown endpoints, `labor_derivation.py`, `CostBreakdownResponse` shapes with unrated seconds (32-02)
- `backend/app/features/finance/labor_derivation.py` — derivation helpers to reuse for margin cost side

### Revenue-side code that constrains this phase
- `backend/app/features/invoices/models.py` — Invoice (status: unpaid/partially_paid/paid, job_id XOR trade_scope_id), InvoiceLineItem
- `backend/app/features/quotes/models.py` — Quote (status machine: draft→sent→viewed→approved/declined/expired/revised), QuoteLineItem
- `.planning/phases/25-per-trade-billing/` — per-trade billing decisions (mark_invoiced atomicity, anchor patterns)

### Research (grounds the formula and pitfalls)
- `.planning/research/PITFALLS.md` — #1 (same-traversal revenue/cost test), #3 (revenue/cost side separation — the margin formula), #9 (legacy zero-cost fabricated margins)
- `.planning/research/ARCHITECTURE.md` — integration architecture

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — MARG-01, MARG-02, MARG-03
- `.planning/ROADMAP.md` — Phase 33 goal + 3 success criteria

### UI surfaces being extended
- Web: `web/src/features/finance/components/CostBreakdownSummary.tsx` + Costs sections on job/scope/project pages; `ProjectCostsCard`
- Mobile: `mobile/lib/features/finance/presentation/widgets/cost_breakdown_summary.dart` + mounts on job/scope/project screens; `financePermissionProvider`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 32 breakdown endpoints + `CostBreakdownResponse` (category totals, derived labor, unrated seconds, `labor_tracked_at_job_level`) — the complete cost side of the margin formula, already bounded-query
- Invoice/Quote models with job_id XOR trade_scope_id anchors (Phase 25) — the revenue side needs only aggregation queries
- `CostBreakdownSummary` components (web + mobile) — margin block mounts alongside/inside these
- `finance.view` gating plumbing on every surface involved

### Established Patterns
- Money = Decimal, string-serialized; computed-on-read derivation; additive-only response extension (mobile parsers are strict on existing fields, tolerant on new optional ones — extend, never reshape)
- Honest-data UI vocabulary already shipped: chips for data gaps, captions for caveats — the incomplete flag and estimated-revenue label follow it

### Integration Points
- Phase 34 budgets consume spend totals; Phase 35 dashboard charts these margins; Phase 36 AI consumes margin + revenue_basis + incomplete flags — shape responses so those phases read, not recompute
- Pitfall 1 integration test: one project with mixed job-anchored and scope-anchored quotes/invoices/costs must net out through the same traversal on both sides

</code_context>

<specifics>
## Specific Ideas

- Estimated-revenue caption wording to the effect of: "Based on approved quote — not yet invoiced"
- Margin display shape: "$4,200 · 21%"
- Keystone honesty test: a legacy job with revenue and zero cost data must show the incomplete flag, never an unflagged 100% margin (research Pitfall 9)

</specifics>

<deferred>
## Deferred Ideas

- Denormalized/cached margin summaries — revisit in Phase 35 if dashboard latency demands it (D-11)
- Cash-basis (paid-only) margin view — not selected; could be a future toggle if collections visibility is ever requested
- None other — discussion stayed within phase scope

</deferred>

---

*Phase: 33-profit-margin-tracking*
*Context gathered: 2026-07-27*
