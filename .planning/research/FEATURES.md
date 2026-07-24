# Feature Research

**Domain:** Construction job costing, profit margin tracking, budgeting, and AI-assisted estimating (financial intelligence layer for an existing multi-trade construction management platform — v4.0 milestone)
**Researched:** 2026-07-24
**Confidence:** MEDIUM-HIGH (WebSearch-verified across multiple vendors: Buildertrend, Knowify, ServiceTitan, Jobber, CoConstruct, Procore; this is a domain/business-logic research question rather than a library API question, so no Context7 lookup applies)

## Scope Note

This research covers ONLY what's needed for the NEW v4.0 features: profit margin tracking, actual-cost capture, budgeting with overrun alerts, AI profitability analysis, AI-assisted quote building, and finance.* RBAC. It assumes the existing job/quote/invoice/time-tracking/trade-scope features described in PROJECT.md are already built and reusable as inputs (revenue side and labor-hours side are solved; this milestone adds the cost side, the budget side, and the AI-analysis side).

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist once a construction platform claims "job costing" or "profitability." Missing these makes the financial module feel like a toy.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Simple cost categories (labor / materials / subcontractor / other, per trade) | Every job-costing tool (Buildertrend, Knowify, ServiceTitan) organizes costs into buckets before anything else works. Small contractors specifically resist full CSI MasterFormat (50 divisions) — sources report 15-25 simple codes is the sweet spot for adoption. | LOW | Model as a small enum/lookup, not a configurable code hierarchy. Nest under existing Trade Scope so costs roll up per trade and per project. |
| Actual-cost capture (materials + subcontractor entries) | Buildertrend/Knowify both treat this as the foundational data-entry layer — without it there is nothing to compare budget against. | MEDIUM | New data layer: itemized cost entries (amount, category, trade scope, date, optional vendor/note, optional receipt photo). No inventory/stock tracking — just cost recording, consistent with existing "materials cost capture in scope, stock management out of scope" decision in PROJECT.md. |
| Labor cost derived from time tracking | ServiceTitan/Jobber both auto-roll clocked hours into job cost using an hourly rate. This project already has clock in/out per job — the gap is only "hourly rate × hours tracked." | LOW-MEDIUM | Requires adding an hourly cost rate per contractor (distinct from the labor line-item *price* on quotes, which is what the client is billed). Simple rate × hours is table stakes; true burden rate (below) is not. |
| Budget vs. actual view per project/trade | The single most consistently named feature across every vendor searched (Buildertrend "Job Costing & Budget Overview," Knowify, ServiceTitan job-costing flyout). Contractors expect to see "budgeted $X, spent $Y, remaining $Z" at both project and trade-scope level. | MEDIUM | Aggregates actual-cost entries + derived labor cost against a budget figure set per project (and ideally per trade scope, matching the existing Project → Trade Scope → Task hierarchy). |
| Profit margin per project/job | Jobber calculates this automatically and surfaces it on the job detail page and dashboard; it's the headline metric of "job costing" software everywhere. | MEDIUM | margin = revenue (from quote/invoice) − actual costs (materials + subcontractor + derived labor). Needs to work at both per-job (trade scope) and per-project (rollup) granularity to match the existing per-trade quoting/invoicing model. |
| Budget overrun alerts | Jobber flags any job that falls below a profit-margin threshold; ServiceTitan and PMIS-style tools use tiered thresholds (e.g., 50% early warning, 80-90% urgent). This is explicitly named in the milestone scope. | LOW-MEDIUM | Simple threshold-based rule (e.g., % of budget consumed, or margin % below target) is sufficient — not predictive/statistical forecasting. Reuse existing push-notification (FCM) infrastructure. |
| Financial data access control (finance.* RBAC) | Every mature platform in this space (ServiceTitan, Buildertrend, Procore) restricts cost/margin data to owners/admins/PMs — field crews and clients never see internal costs. This is explicitly required by the milestone. | LOW | Extends the existing role-based permission matrix, not a new permission system. Must be enforced backend-side (per CLAUDE.md security rules — every financial endpoint needs `Depends(get_current_user)` + a finance.* check), not just hidden in UI. |
| Change order / quote revision reflected in budget | CoConstruct: "Approved changes automatically update your budget." This project already has quote revisions — the new requirement is only that an approved revision propagates a budget delta. | MEDIUM | Depends on existing quote revision feature. No new change-order object needed if quote revisions already capture the delta; just wire the approved-revision event to adjust the project/trade budget. |
| Margin/profitability additions to the existing reporting dashboard | The project already has a reporting dashboard (revenue, utilization). Users will expect margin and budget-vs-actual to live there, not in a disconnected screen. | MEDIUM | Extend existing dashboard rather than build a parallel one — reuses existing charting/data-table patterns from v2.0. |

### Differentiators (Competitive Advantage)

Not required for a functioning financial module, but where this product can stand out — especially given the existing AI-native, multi-trade architecture.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| AI profitability analysis (margin erosion detection + corrective-action suggestions) | No mainstream small-contractor tool (Jobber, Buildertrend, Knowify) does proactive AI analysis of *why* margin is eroding and *what to do* — they only show dashboards and let the human interpret. This project already has Claude API integration with tool use (intake, interviews, checklists, schedule adaptation), so this extends a proven pattern instead of introducing a new capability class. | HIGH | Needs budget-vs-actual + margin data as clean structured input (depends on table-stakes items above). Should reuse the same alerting/notification rails as the existing "AI schedule adaptation... flag delays" feature for consistency. |
| AI quote building from company cost history (labor hours + material quantities/costs suggested) | AI estimating (Procore, Togal.AI, others) is trending in 2026 — 24% of construction firms already use AI for cost estimation, with reported 15-25% fewer change orders from more accurate initial pricing. Differentiator here is that it's *grounded in this company's own actual-cost history* (once actual-cost capture exists), not generic market pricing — directly leverages the new cost-capture data layer. | HIGH | Cold-start problem: needs a meaningful volume of historical actual-cost + quote data per company before suggestions are reliable. Early-stage companies (few completed jobs) will get thin/generic suggestions — worth flagging in UX (confidence indicator) rather than silently degrading quality. Must stay assistive (pre-fills line items for human review), never auto-send a quote — pricing errors have direct revenue impact. |
| Per-trade-scope budget granularity | Because this project already models Project → Trade Scope → Task (unlike most competitors, which are single-trade or flat-project), budgets and margins can be tracked per trade within a project, not just per whole project. This is a natural extension of an architecture competitors don't have. | MEDIUM | Directly reuses the existing trade-scope hierarchy — low marginal cost given the architecture already exists, but real differentiation vs. single-trade tools like Jobber/ServiceTitan. |
| AI-surfaced estimate-accuracy trend (quoted vs. actual variance over time, feeding back into AI quote suggestions) | Closes the loop: AI quoting gets smarter each project because actual-cost capture continuously corrects its assumptions. This compounding-accuracy loop is a genuine differentiator vs. static historical-pricing tools. | MEDIUM-HIGH | Not needed for v4.0 launch — depends on AI quote building + several completed projects worth of actual-cost data. Good candidate for a fast-follow milestone. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that look like "of course we need this" but would push this into enterprise-ERP territory that this small-to-mid contractor audience explicitly doesn't want (and can't afford in complexity or price, per the Procore complaints found in research: "wasn't designed for companies their size," setup complexity, cost-to-value mismatch).

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|------------------|-------------|
| Full CSI MasterFormat cost coding (50 divisions, deeply nested codes) | Feels "more professional," matches what large GC software (Procore) uses | Sources explicitly note small/mid contractors find it "cumbersome and clunky" and abandon detailed coding, leading to worse data than a simple system that's actually used | Simple flat categories (labor/materials/subcontractor/other) scoped to the existing trade-scope model — extendable later if a company genuinely outgrows it |
| Committed-cost tracking via formal purchase orders/subcontract agreements (vs. only actual costs) | Buildertrend/Knowify both distinguish "committed" (obligated but unpaid) from "actual" (paid) costs, and it's a legitimate accounting concept | Requires a new PO/subcontract-commitment object, approval workflow, and a second cost-tracking dimension — meaningfully larger scope than what the milestone asks for (actual costs only). Real risk of scope creep into procurement/ERP territory. | Ship actual-cost capture only for v4.0 (matches milestone scope exactly); revisit committed-cost tracking as a later milestone if users request it once actual-cost tracking is proven valuable |
| True labor burden rate (full overhead/benefits/workers-comp allocation per employee) | ServiceTitan and accounting best-practice both use burden rate = yearly overhead ÷ hours worked, which is more "accurate" than raw wage rate | Requires tracking company-wide overhead allocation, benefits data, and per-employee cost structures the project has no data model for today — a significant new data-collection burden on a small contractor who may not even track this internally | Simple hourly-rate × hours-tracked for v4.0 (already table stakes); flag as an approximation and let it be a differentiator to add later once/if companies want overhead-adjusted rates |
| Full WIP / percentage-of-completion revenue-recognition accounting (GAAP-level, over/under-billing schedules) | It's the term construction accountants use, and "WIP report" sounds like the obviously-correct feature for a construction financial module | This is formal accrual accounting used by mid-large GCs for bonding/lender reporting — sources note "many small business owners simply don't prepare WIP schedules" at all. It requires percentage-complete estimation methodology, contract-value tracking, and overbilling/underbilling calculations that belong in accounting software (QuickBooks/Xero), which this project has already deferred as a carried-over future integration | Simple budget-vs-actual + margin-by-project (table stakes above) covers the operational need; leave formal WIP/POC schedules to the eventual QuickBooks/Xero integration already listed in PROJECT.md's carried scope |
| Enterprise procurement workflows (RFIs, submittals, bid management, multi-level PO approval chains) | This is literally what Procore does, and "job costing" searches surface Procore prominently | Explicitly named in research as the reason small/mid contractors reject Procore — "residential contractors end up paying for features they never use," onboarding complexity, cost-to-value mismatch | Keep cost entry lightweight (a form, not a workflow engine); no approval chains for v4.0 |
| Autonomous AI quote sending (AI generates and sends a quote to the client with no human review) | Feels like the "AI-native" thing to do given the platform's existing autonomous AI checklist generation | Pricing mistakes directly cost the company money and damage client trust; unlike a checklist (low stakes if imperfect), a wrong quote line item is a real financial commitment | AI pre-fills quote line items (labor hours, material quantities/costs) for a human to review and approve before sending — assistive, not autonomous, consistent with how AI intake/interview already work as human-reviewed drafts |
| Multi-entity / multi-currency consolidated financial reporting | "Enterprise-grade" framing that sounds forward-thinking | No evidence this audience (small-to-mid, single-entity contractors) needs it; adds real complexity to every financial calculation for zero near-term value | Single-company, single-currency financial model, matching the existing multi-tenant-but-single-currency architecture |
| Full general-ledger / double-entry accounting inside the app | "Why not just do all the accounting here" | Duplicates what QuickBooks/Xero already do well and is a different product category entirely; this project already treats QuickBooks/Xero as a deferred integration, not a feature to rebuild | Keep this app as the operational job-costing layer (what was spent, on what, per job) and leave ledger-level accounting to the eventual accounting-software integration |

## Feature Dependencies

```
finance.* RBAC permissions
    └──gates──> Actual-cost capture, Budgeting, Profit margin views, AI profitability analysis, AI quote building

Cost categories (labor/materials/sub/other)
    └──requires──> [none — new lightweight lookup]
    └──enables──> Actual-cost capture, Budgeting (budgets are set per category/trade)

Actual-cost capture (materials + subcontractor)
    └──requires──> Cost categories
    └──enables──> Budget vs. actual reporting, Profit margin tracking

Labor cost derivation
    └──requires──> Existing time tracking (clock in/out) + new hourly cost-rate field per contractor
    └──enables──> Profit margin tracking (labor is part of actual cost)

Budgeting (project/trade budgets)
    └──requires──> Cost categories, existing Project → Trade Scope hierarchy
    └──enables──> Budget vs. actual reporting, Budget overrun alerts

Budget vs. actual reporting
    └──requires──> Budgeting + Actual-cost capture + Labor cost derivation
    └──enables──> Margin dashboard, Budget overrun alerts

Profit margin tracking (per project/job)
    └──requires──> Actual-cost capture + Labor cost derivation + existing Revenue (quotes/invoices)
    └──enables──> Margin dashboard, AI profitability analysis

Change-order/quote-revision budget impact
    └──requires──> Existing quote revision feature + Budgeting

AI profitability analysis
    └──requires──> Profit margin tracking + Budget vs. actual reporting (needs clean structured data to reason over)
    └──enhances──> Margin dashboard (surfaces AI flags/suggestions inline)

AI quote building from history
    └──requires──> Actual-cost capture (historical data to learn from) + existing quote line-item structure
    └──weak-dependency──> sufficient historical project volume (cold-start: degrades gracefully with few prior jobs, does not block launch)

Committed-cost tracking (future) ──enhances──> Budget vs. actual reporting (would reduce false "budget available" reads)

Full WIP/POC accounting (future) ──conflicts──> project's stated preference for simple operational tooling over accountant-grade GAAP reporting; better delegated to QuickBooks/Xero integration
```

### Dependency Notes

- **finance.* RBAC must land first or in lockstep with everything else:** every other v4.0 feature exposes cost/margin data. Building actual-cost capture before the permission gate exists creates a window where sensitive data is visible to the wrong roles. Recommend treating RBAC as a cross-cutting concern implemented alongside the first cost-data feature, not a separate later phase.
- **Labor cost derivation is low complexity but easy to underestimate its data dependency:** it needs a new "hourly cost rate" field per contractor, which is conceptually simple but touches user/contractor profile data, not job data — worth sequencing early since profit margin tracking can't be accurate without it.
- **AI profitability analysis and AI quote building both depend on the "boring" data-capture features being solid first.** Sequencing AI features before actual-cost capture is stable would mean the AI is reasoning over incomplete/noisy data — high risk of low-trust AI output that damages user confidence in a feature they'll rely on for financial decisions.
- **AI quote building has a cold-start dependency that isn't a hard blocker but should shape UX:** new companies (or the initial rollout for existing companies with limited historical actual-cost data) will get weaker suggestions. This isn't a reason to delay the feature, but confidence/data-volume should be signaled in the UI rather than presenting thin suggestions as equally confident to well-grounded ones.
- **Change-order budget impact conflicts with nothing — it's a thin integration layer** on top of the existing quote-revision feature, not a new object. Treat as low-risk, high-value connective tissue rather than a standalone feature requiring its own data model.
- **Committed-cost tracking and full WIP/POC accounting are intentionally excluded from this milestone's dependency graph** — they're future-consideration items that would meaningfully expand scope (new PO/commitment objects, percentage-complete methodology) beyond what profit margin tracking, budgeting, and AI features require.

## MVP Definition

### Launch With (v4.0)

Minimum to deliver on the milestone goal: "give owners and PMs real profit visibility and AI-assisted financial management."

- [ ] finance.* RBAC permissions (owner + project_manager by default, adjustable via existing Roles & Permissions matrix) — gates everything else; must be backend-enforced
- [ ] Simple cost categories (labor / materials / subcontractor / other) scoped to existing Trade Scope hierarchy — the structural foundation everything else is built on
- [ ] Actual-cost capture for materials and subcontractor costs (itemized entries: amount, category, trade scope, date, optional note) — new data layer explicitly named in scope
- [ ] Labor cost derivation from existing time tracking × contractor hourly cost rate — reuses existing clock in/out data, adds one new rate field
- [ ] Budgeting: set budget per project and per trade scope — required before "budget vs actual" or "overrun alerts" can exist
- [ ] Budget vs. actual view (spend tracking against budget, per project and per trade) — core of the milestone's "budgeting" requirement
- [ ] Budget overrun-risk alerts (threshold-based, e.g., % of budget consumed) — explicitly named in scope, reuses existing FCM push infrastructure
- [ ] Profit margin tracking per project and per job/trade (revenue from quotes/invoices minus actual costs) — the milestone's headline feature
- [ ] Change-order/quote-revision impact flows into budget automatically — closes the loop between existing quote revisions and the new budget feature
- [ ] Margin/budget additions to the existing reporting dashboard — surfaces the above rather than building an isolated screen
- [ ] AI profitability analysis: flags margin erosion, suggests corrective actions — explicitly named in scope, extends existing Claude API integration pattern
- [ ] AI-assisted quote building: suggests labor hours + material quantities/costs priced from company history, human reviews/approves before sending — explicitly named in scope

### Add After Validation (v4.x)

- [ ] Committed-cost tracking (POs/subcontract commitments vs. actual, distinct from paid actual costs) — add once actual-cost tracking is proven adopted and users start asking "but what about costs I've agreed to but haven't paid yet"
- [ ] True labor burden rate (overhead/benefits allocation beyond raw wage) — add if companies request more accurate margin figures than wage-rate approximation provides
- [ ] Estimate-accuracy trend reporting (quoted vs. actual variance over time, feeding back into AI quote confidence) — add once enough completed projects exist post-launch to make trends meaningful
- [ ] More granular cost codes beyond the 4 basic categories — add only if a company outgrows the simple system (avoid pre-building this; simple systems that are used beat detailed ones that aren't, per research)

### Future Consideration (v5+)

- [ ] Formal WIP / percentage-of-completion accounting reports (over/underbilling schedules) — defer to the eventual QuickBooks/Xero integration; this is accountant-grade GAAP reporting, not operational job costing
- [ ] Enterprise procurement workflows (RFIs, submittals, PO approval chains) — explicitly an anti-feature for this audience; only reconsider if the customer base shifts toward larger GCs
- [ ] Multi-entity/multi-currency consolidated reporting — no evidence of demand from a small-to-mid single-entity contractor audience

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| finance.* RBAC permissions | HIGH | LOW | P1 |
| Cost categories (simple) | HIGH | LOW | P1 |
| Actual-cost capture (materials + sub) | HIGH | MEDIUM | P1 |
| Labor cost derivation from time tracking | HIGH | LOW-MEDIUM | P1 |
| Budgeting (project/trade) | HIGH | MEDIUM | P1 |
| Budget vs. actual reporting | HIGH | MEDIUM | P1 |
| Budget overrun alerts | HIGH | LOW-MEDIUM | P1 |
| Profit margin tracking | HIGH | MEDIUM | P1 |
| Change-order budget impact | MEDIUM | MEDIUM | P1 |
| Margin dashboard integration | HIGH | MEDIUM | P1 |
| AI profitability analysis | HIGH | HIGH | P1 |
| AI quote building from history | HIGH | HIGH | P1 |
| Committed-cost tracking | MEDIUM | MEDIUM-HIGH | P2 |
| True labor burden rate | MEDIUM | MEDIUM | P2 |
| Estimate-accuracy trend reporting | MEDIUM | MEDIUM | P2 |
| Granular/expanded cost codes | LOW | LOW-MEDIUM | P3 |
| Formal WIP/POC accounting | LOW (for this audience) | HIGH | P3 |
| Enterprise procurement workflows | LOW (for this audience) | HIGH | P3 (anti-feature; excluded) |

**Priority key:**
- P1: Must have for v4.0 launch (explicitly named in milestone scope or a hard dependency of something that is)
- P2: Should have, add once v4.0 is validated in production
- P3: Nice to have or explicitly deferred/excluded — future consideration only

## Competitor Feature Analysis

| Feature | Buildertrend | Knowify / ServiceTitan | Procore | Our Approach |
|---------|--------------|-------------------------|---------|--------------|
| Cost codes | Full cost-code system organized by category, required setup before using financial tools | Committed-vs-actual tracking, automatic budget-remaining calculation | CSI MasterFormat-based, deep hierarchy | Simple 4-category system (labor/materials/sub/other) scoped to existing trade scopes — deliberately lighter than all three |
| Budget vs. actual | Job Costing Budget by cost code, QuickBooks two-way sync | Committed costs auto-deducted from budget, actual vs. budgeted comparison | Full budget/commitment/change-order ledger | Budget vs. actual by project/trade, actual-cost only (no committed-cost layer) for v4.0 |
| Labor cost | Rolls into job costing via cost codes | ServiceTitan: explicit "technician burden rate" (yearly overhead ÷ hours) used in job costing flyout | Detailed labor cost tracking tied to timesheets | Simple rate × hours from existing time tracking; true burden rate deferred to v4.x |
| Profit margin dashboard | Part of job costing budget overview | Jobber: automatic per-job margin calc + threshold alerts on Insights dashboard | Full financial reporting suite | Extend existing reporting dashboard with per-project/per-trade margin; threshold alerts modeled closely on Jobber's approach |
| Change orders | Change orders sync to budget automatically | Change order fees flow into budget | Formal change-order/RFI workflow tied to contract value | Reuse existing quote-revision feature; approved revision pushes a budget delta — no new change-order object |
| AI estimating | Not a core differentiator historically | Not a focus | Data-driven estimating engine validating against historical cost data (enterprise-grade, AI floor-plan detection) | AI quote building grounded in this company's own actual-cost history, assistive (human-reviewed) not autonomous — closer in spirit to Procore's historical-validation approach but scoped for small-contractor simplicity, not floor-plan takeoff |
| AI profitability analysis | Not found in research (dashboards only, human-interpreted) | Not found in research (dashboards only, human-interpreted) | Not a named feature | Genuine differentiator: proactive margin-erosion flags + corrective-action suggestions via existing Claude API integration — no mainstream competitor in this tier does this |
| Target audience fit | Mid-market residential/light commercial | Trade contractors (Knowify) / home-service (ServiceTitan) | Large GCs, enterprise ($6K-28K+/yr even for small firms, explicit "not designed for companies their size" feedback) | Small-to-mid multi-trade GC audience — deliberately excludes Procore-tier procurement/submittal/RFI complexity |

## Sources

- [Job Costing & Budget Overview — Buildertrend](https://buildertrend.com/help-article/job-costing-budget-overview/)
- [What Are Construction Cost Codes? — Buildertrend](https://buildertrend.com/blog/guide-to-construction-cost-codes/)
- [Cost Codes Overview — Buildertrend](https://buildertrend.com/help-article/cost-codes-overview/)
- [Job costing software for trade contractors — Knowify](https://knowify.com/job-costing-software/)
- [Mastering construction job costing: A contractor's guide — Knowify](https://knowify.com/resources/construction-job-costing-contractors-guide/)
- [How to Track Committed Costs with Job Costing Software — Xpedeon](https://xpedeon.com/blog/how-to-track-committed-costs-with-job-costing-software/)
- [Case Study: Actual vs Committed Job Cost Reports — Onware](https://onware.com/case-studies/actual-vs-committed-job-cost-reporting/)
- [Job Costing Software — ServiceTitan](https://www.servicetitan.com/features/job-costing-software)
- [Calculate technician burden rates — ServiceTitan Help](https://help.servicetitan.com/docs/calculate-technician-burden-rates)
- [Labor Rate Calculator for Service Businesses — ServiceTitan](https://www.servicetitan.com/tools/labor-rate-calculator)
- [Work in Progress (WIP) Report in Construction — ProjectManager](https://www.projectmanager.com/blog/wip-report-construction)
- [WIP schedules: Blueprints for solid construction accounting — AICPA & CIMA](https://www.aicpa-cima.com/professional-insights/article/wip-schedules-blueprints-for-solid-construction-accounting)
- [Construction WIP Reports: Complete Guide — Foundation Software](https://www.foundationsoft.com/learn/wip-report-field-guide/)
- [How to Read Your Construction WIP Report — Jobpow](https://www.jobpow.com/blog/how-to-read-wip-report-construction/)
- [Construction change order software features — CoConstruct](https://www.coconstruct.com/features/change-order-software)
- [Turning estimates & job costing on or off for a project — CoConstruct](https://www.coconstruct.com/learn-construction-software/turning-estimates-job-costing-on-or-off-for-a-project)
- [12 Best AI Estimating Software for Construction in 2026 — ConstructionPlacements](https://www.constructionplacements.com/best-ai-estimating-software-construction/)
- [Construction Estimating Trends 2026: AI, Automation & Pricing — NEDES](https://nedesestimating.com/construction-estimating-companies-ai-automation-real-time-pricing/)
- [Construction Cost Codes: Setup Guide + Examples — Projul](https://projul.com/blog/construction-cost-codes-guide/)
- [Construction Cost Codes: The Complete Guide — Rhumbix](https://www.rhumbix.com/blog/construction-cost-codes-complete-guide)
- [Construction Cost Codes — Everything You Need to Know — CrewCost](https://crewcost.com/blog/everything-you-need-to-know-about-construction-cost-codes/)
- [Procore Software Review 2025: Pricing, Pros & Better Alternatives — ConstructionBase.ai](https://www.constructionbase.ai/blog/procore-features-pricing-and-limitations-explained)
- [Procore vs CoConstruct — Projul](https://projul.com/competitors/procore-vs-coconstruct/)
- [Insights Dashboard — Jobber Help Center](https://help.getjobber.com/hc/en-us/articles/30100867609367-Insights-Dashboard)
- [Job Costing — Jobber Help Center](https://help.getjobber.com/hc/en-us/articles/14343244961175-Job-Costing)
- [Job Costing Software for Field Service Businesses — Jobber](https://www.getjobber.com/features/job-costing-software/)
- [Construction Profit Margins: Calculate and Track — Jobber Academy](https://www.getjobber.com/academy/contracting/calculate-profit-margins-on-construction-jobs/)
- [Setting up alerts to avoid budget overruns — WorkflowMax](https://workflowmax.com/blog/setting-up-alerts-to-avoid-budget-overruns)
- [Budget Overrun Alerts by Cost Code — US Tech Automations](https://ustechautomations.com/resources/blog/automate-flag-budget-overruns-by-cost-code-2026)
- `.planning/PROJECT.md` — existing feature inventory, v4.0 milestone scope, and Out-of-Scope decisions (project internal)

---
*Feature research for: Construction financial intelligence (job costing, profit margin, budgeting, AI estimating) for a small-to-mid multi-trade contractor platform*
*Researched: 2026-07-24*
