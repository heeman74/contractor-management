# Phase 34: Budgeting and Overrun Alerts - Context

**Gathered:** 2026-07-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Owner/PM can set a budget per project and independently per trade scope, view
budgeted vs spent vs remaining at both levels, receive 80% warning and 100%
overrun alerts (dashboard + FCM push, finance-gated), and have approved quote
revisions automatically adjust the linked budget by the revision's delta.
(BUDG-01, BUDG-02, BUDG-03, BUDG-04.)

The `Budget`/`BudgetCategoryBreakdown` schema exists from Phase 30 (D-09).
"Spent" = the shipped Phase 31–33 cost definition: cost entries + derived labor
via the same traversal margins use.

NOT in this phase: velocity/trend-based overrun projection (deferred to
Phase 36 AI), per-category budget UI (schema stays dormant), dashboard charts
(35), any change to cost capture, labor derivation, or margin math.

</domain>

<decisions>
## Implementation Decisions

### Alert model (resolves the STATE.md open blocker)
- **D-01:** **Static 80%/100% thresholds with strict dedup.** Each budget fires
  exactly once per threshold crossing (80 warning, 100 overrun), tracked
  persistently so repeat evaluations never re-fire. No velocity/trend
  projection this phase — that judgment belongs to Phase 36's AI analysis.
  (Research Pitfall 6's noise problem is repeated alerts; dedup solves it.)
- **D-02:** **Evaluated on cost mutation + nightly sweep.** The affected
  budget(s) are checked synchronously when a cost entry is created/updated/
  deleted, AND a nightly cron sweep (Phase 26 APScheduler pattern) evaluates
  all budgets — required because derived labor grows on clock-outs with no
  cost-entry mutation to hook.
- **D-03:** **Thresholds re-arm on budget increase.** Raising a budget
  (manual edit or positive quote-revision delta) clears fired thresholds for
  that budget; crossing 80%/100% of the NEW total fires fresh alerts.
- **D-04:** **Independent per-budget alerting.** Project and scope budgets
  evaluate and alert independently against their own thresholds — a scope
  crossing never cascades a project-level notice. Alert content names the
  entity, threshold, spend, and budget figures.

### Alert delivery (from SC3 + Phase 30 D-11)
- **D-05:** Dashboard alerts use new financial `alert_type` values (requires a
  migration for the `dashboard_alerts_alert_type_check` constraint) and are
  registered in Phase 30's `FINANCIAL_ALERT_TYPES` so the shipped
  permission-aware filter hides them from non-finance roles. FCM push goes
  only to users holding `finance.view` in the company.

### Quote-revision → budget (BUDG-04)
- **D-06:** **Linkage mapping mirrors the cost/margin traversal:** a
  trade-scope-anchored quote adjusts that scope's budget; a job-anchored quote
  adjusts the project budget via `jobs.project_id` (a job with no project
  adjusts nothing); a project-level quote adjusts the project budget.
- **D-07:** **Delta is signed and pre-tax.** delta = new approved revision's
  pre-tax total − the previous approved quote's pre-tax total (Phase 33 D-13
  basis). Downward revisions lower the budget too — the budget tracks
  committed revenue in both directions; a resulting below-spend budget simply
  fires honest overrun alerts.
- **D-08:** **No-op when no budget exists.** Approval proceeds normally and no
  budget is auto-created; the delta applies only where a budget row exists.
- **D-09:** The trigger is approval of the NEW quote row created by
  `revise_quote` (old row status='revised', new row revision_number+1) — the
  first approval of a revision chain establishes the baseline; subsequent
  approved revisions apply deltas.

### Budget management
- **D-10:** **Full edit + soft-delete, no floor.** Budgets can be edited to any
  positive amount — including below current spend (next evaluation fires the
  crossed thresholds immediately, which is honest) — and soft-deleted like
  every other entity (deleted budgets stop evaluating). Gated `finance.manage`.
- **D-11:** **Total-only UI in v4.0.** The per-category breakdown rows (D-09
  Phase 30) stay dormant — no allocation editor, no category-level thresholds.

### UI surfaces
- **D-12:** **Extend the Costs sections** on project and trade-scope screens
  with budgeted vs spent vs remaining rows plus an inline "Set budget" action.
  No dedicated budgets screen. Established 31/32/33 pattern.
- **D-13:** **Web-edit + both-view.** Budget create/edit on web only (like
  rates, Phase 32 D-09 precedent), gated `finance.manage`; the
  budget-vs-actual view ships on both web and mobile, gated `finance.view`.
  Mobile fetches via API; no budget data persisted to Drift.

### Claude's Discretion
- Threshold-crossing state storage shape (fired-threshold columns on Budget vs
  a separate table), and how re-arm (D-03) resets it.
- Exact alert_type names, alert copy strings (a Phase 34 UI-SPEC pass locks
  UI strings), FCM payload shape, deep-link behavior.
- "Spent" computation reuse — how the budget evaluation calls into the shipped
  Phase 33 rollup/margin cost queries without duplicating traversal logic.
- Whether scope budgets use the scope's cost breakdown (scope-anchored costs
  only, labor "tracked at job level" exclusion noted honestly) — must be
  consistent with what the scope Costs section displays as spend.
- API shape (budget CRUD endpoints + budget-vs-actual in breakdown responses
  vs separate), additive-only extension of existing responses per the
  established mobile parsing contract.
- Migration numbering; nightly sweep scheduling details.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 30–33 foundation (locked decisions this phase builds on)
- `.planning/phases/30-financial-schema-foundation-and-rbac-audit/30-CONTEXT.md` — D-09 budget schema, D-11 alert-filter plumbing + FINANCIAL_ALERT_TYPES, finance keys
- `backend/app/features/finance/models.py` — `Budget`, `BudgetCategoryBreakdown` (shipped, dormant), CostEntry, LaborRate
- `.planning/phases/33-profit-margin-tracking/33-CONTEXT.md` — D-12 traversal, D-13 pre-tax basis, computed-on-read posture
- `backend/app/features/finance/repository.py` — `rollup_for_project`, `RevenueRepository` dual-outerjoin traversal; the spend queries to reuse
- `backend/app/features/finance/margin_math.py` — pre-tax document totals for the delta math

### Alert/notification plumbing
- `backend/app/features/dashboard/models.py` — `DashboardAlert` with `alert_type` CHECK constraint (migration needed for new types)
- Phase 30's permission-aware DashboardAlert filter + `FINANCIAL_ALERT_TYPES` (see 30-CONTEXT D-11; shipped in `backend/app/features/dashboard/`)
- `backend/app/features/notifications/` — FCM push service (Phase 24/26 async fire pattern: `asyncio.create_task`, never block the request)
- Phase 26 APScheduler cron pattern (`.planning/phases/26-ai-daily-checklists-and-monitoring-dashboard/` summaries; backend cron jobs feature)

### Quote revision machinery (BUDG-04)
- `backend/app/features/quotes/service.py` — `revise_quote` (old→'revised', new row revision_number+1), approval flow to hook
- `backend/app/features/quotes/models.py` — Quote status machine, revision_number, anchors

### Research
- `.planning/research/PITFALLS.md` — #6 (alert noise + permission leak), #4 (quote-revision budget sync), #1/#3 (traversal + revenue/cost separation)

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — BUDG-01..04
- `.planning/ROADMAP.md` — Phase 34 goal + 4 success criteria

### UI surfaces being extended
- Web: `web/src/features/finance/components/` (CostBreakdownSummary, MarginSummarySection, ProjectCostsCard) + project/scope pages
- Mobile: `mobile/lib/features/finance/presentation/widgets/` (cost_breakdown_summary.dart, margin_summary_section.dart, breakdown_row_widgets.dart shared primitives)
- Phase 32/33 UI-SPECs — chip/caption/copy conventions to extend

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Budget` schema shipped and dormant — this phase adds endpoints, evaluation, and UI only (no new budget tables; alert-state storage may need a migration alongside the alert_type constraint change)
- Phase 33's cost/revenue traversal queries — budget "spent" MUST reuse them (no third spend definition)
- Phase 30's permission-aware alert filter — register new types in FINANCIAL_ALERT_TYPES and the dashboard constraint; filtering comes free
- FCM notification service + async fire-and-forget pattern (Phase 24); APScheduler nightly cron (Phase 26)
- `FinanceFlagChip` / `BreakdownRow` shared primitives (web + mobile) for budget-vs-actual rows

### Established Patterns
- Money = Decimal, string-serialized; additive-only response extension (mobile strict/tolerant parsing contract)
- Soft-delete everywhere; `finance.manage` writes / `finance.view` reads; web-edit + both-view platform split
- Honest-data UI vocabulary (chips/captions) for over-budget states

### Integration Points
- Quote approval flow (`quotes/service.py`) → budget delta application (D-06..D-09)
- Cost entry create/update/delete (`finance/service.py`) → synchronous threshold evaluation (D-02)
- Nightly cron → full budget sweep (D-02); DashboardAlert + FCM (D-05)
- Phase 35 dashboard will chart budget-vs-actual; shape responses for reuse

</code_context>

<specifics>
## Specific Ideas

- Alert copy must name the entity, threshold, and figures — e.g. "Riverside Remodel — Plumbing scope has spent $8,200 of its $10,000 budget (82%)"
- Keystone tests: (1) threshold fires exactly once until re-armed by a budget increase; (2) a downward revision delta that puts the budget below spend fires the overrun alert on next evaluation; (3) non-finance roles see no budget alerts on the dashboard and receive no FCM push
</specifics>

<deferred>
## Deferred Ideas

- Velocity/trend-based overrun projection with front-loading heuristics — Phase 36 AI territory (research Pitfall 6 full recommendation)
- Per-category budget allocation UI + category-level thresholds — schema ready, revisit post-v4.0
- Mobile budget editing — web-only this milestone, consistent with rates
- Scope-crossing → project-level rollup notices — rejected as Pitfall 6 noise; revisit only if owners ask

</deferred>

---

*Phase: 34-budgeting-and-overrun-alerts*
*Context gathered: 2026-07-28*
