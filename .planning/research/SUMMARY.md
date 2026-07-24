# Project Research Summary

**Project:** ContractorHub v4.0 — Financial Intelligence
**Domain:** Construction job costing, profit margin tracking, budgeting, and AI-assisted estimating layered onto an existing multi-trade construction management SaaS platform
**Researched:** 2026-07-24
**Confidence:** HIGH

## Executive Summary

ContractorHub v4.0 adds a financial intelligence layer — actual-cost capture, profit margin tracking, budgeting with overrun alerts, AI profitability analysis, and AI-assisted quote building — on top of an already-shipped multi-trade platform (jobs, per-trade quotes/invoices, time tracking, AI chat/checklists, RBAC). This is not a rewrite and requires **zero new runtime dependencies**: `Decimal`/`Numeric`, PostgreSQL aggregate SQL (`FILTER`, `GROUPING SETS`, window functions), Recharts, APScheduler, and the existing Claude tool-use integration cover every capability needed. The only stack action is confirming the `anthropic` SDK is pinned >=0.77.0 to use GA Structured Outputs for grounded, schema-guaranteed AI financial output. Architecturally, the work is a new `finance/` backend module (`CostEntry`, `LaborRate`, `Budget`) that follows the same polymorphic job-vs-trade-scope XOR pattern already established by `Quote`/`Invoice`, plus an extension of the existing `TimeEntry` and `DashboardAlert` models rather than new parallel tables.

The recommended feature scope is deliberately narrower than enterprise construction ERP (Procore-tier): simple 4-category costs (labor/materials/subcontractor/other), actual-cost-only tracking (no committed-cost/PO layer), wage-rate-based labor cost (not full burden-rate accounting), and assistive (never autonomous) AI quote generation — this matches how Buildertrend, Knowify, ServiceTitan, and Jobber serve the small-to-mid contractor audience, while the two AI features (proactive margin-erosion flagging and AI-grounded quote building from company history) are genuine differentiators no mainstream competitor in this tier offers.

The primary risks are not technical novelty but **discipline gaps that are easy to miss because they interact with code that already exists**: (1) a "Job vs. Project/TradeScope split-brain" where cost and revenue records can anchor to different hierarchies and silently under- or double-count in margin rollups; (2) the existing `require_admin`/role-based `reports/dashboard` endpoint and the wildcard-minus-exclusion admin permission derivation (`_ADMIN_KEYS = PERMISSION_KEYS - _OWNER_ONLY_KEYS`) will **silently leak financial data to the admin role** unless `finance.*` keys are explicitly added to a new exclusion set in the same commit; (3) existing AI surfaces (chat, checklists, schedule alerts) will start returning cost/margin fields to non-finance roles once those columns exist on `Project`/`TradeScope`, unless tool-result construction is retrofitted as its own authorization boundary; (4) naive live-rate joins for labor cost will retroactively rewrite historical margin figures when a contractor's pay rate changes; and (5) legacy pre-v4.0 jobs with no cost data must show "no data" rather than a fabricated 100% margin, or AI quote planning will anchor its pricing on a phantom baseline. Every one of these is avoidable with explicit schema/permission decisions made in the first phase, not retrofitted later.

## Key Findings

### Recommended Stack

No new packages for backend, web, or mobile. The stack additions are usage-pattern upgrades on existing dependencies: verify the `anthropic` Python SDK is >=0.77.0 for GA **Structured Outputs**/`strict: true` tool schemas (removes JSON-parse-retry logic for money fields), and extend the existing Recharts/APScheduler/RBAC infrastructure with new call sites rather than new libraries.

**Core technologies:**
- `Decimal` (stdlib) + SQLAlchemy `Numeric` — exact money math for costs, revenue, margins, budgets; already the project's convention for quotes/invoices, must be extended end-to-end (never `float`, never `numpy`/`pandas`)
- PostgreSQL 13 aggregate SQL (`FILTER`, `GROUPING SETS`/`ROLLUP`, window functions) via SQLAlchemy 2.0 `func.sum().filter()`/`.over()` — per-project/per-trade/per-category cost rollups and margin trend queries computed in the DB, not re-summed in Python
- Recharts (existing) — margin trend lines, budget-vs-actual bars, cost-breakdown charts via `ComposedChart`/stacked `BarChart`/`ReferenceLine`; no new charting library needed
- `anthropic` SDK >=0.77.0 (GA Structured Outputs) — AI profitability analysis and AI quote building reuse the existing Claude tool-use plumbing (`AIService`), now with grammar-constrained schema guarantees for money fields
- APScheduler (existing) — new nightly job for budget-overrun/margin-erosion scanning, alongside existing AI checklist/alert jobs; no second task queue
- `require_permission()` RBAC (existing) — new `finance.*` permission keys added to the per-company editable matrix, defaulting to owner + project_manager

**Explicitly avoid:** `python-money`/`py-moneyed` (no multi-currency need today), `numpy-financial` (no IRR/NPV/amortization scope), a second task queue, `instructor`/`outlines`/`guidance` (Anthropic's native Structured Outputs replaces these), pgvector/embeddings for quote-pricing lookup (structured SQL filtering beats semantic search for categorical trade/task data), and any embedded BI/dashboard-builder product (Metabase/Superset).

### Expected Features

Scope research (WebSearch-verified against Buildertrend, Knowify, ServiceTitan, Jobber, CoConstruct, Procore) confirms this milestone should ship a lean, small-contractor-appropriate financial layer, not enterprise job-costing.

**Must have (table stakes for v4.0):**
- `finance.*` RBAC permissions (owner + project_manager default, backend-enforced) — gates everything else
- Simple cost categories (labor/materials/subcontractor/other) scoped to the existing Trade Scope hierarchy — not full CSI MasterFormat
- Actual-cost capture (materials + subcontractor itemized entries)
- Labor cost derived from existing time tracking x contractor hourly rate
- Budgeting per project and per trade scope, with budget-vs-actual view
- Budget overrun-risk alerts (threshold-based, reusing existing FCM infrastructure)
- Profit margin tracking per project and per job/trade (revenue minus actual cost)
- Change-order/quote-revision impact flowing automatically into budget
- Margin/budget additions to the existing reporting dashboard (not a disconnected screen)
- AI profitability analysis (margin-erosion flags + corrective-action suggestions)
- AI-assisted quote building (labor hours + material costs priced from company history, human-reviewed before sending)

**Should have (differentiators):**
- Per-trade-scope budget granularity — no mainstream single-trade competitor (Jobber, ServiceTitan) offers this; leverages the platform's unique Project→TradeScope→Task hierarchy
- Proactive AI margin-erosion detection with suggested corrective actions — competitors only show dashboards for humans to interpret
- AI quote building grounded in the company's own historical actual-cost data (not generic market pricing)

**Defer (v4.x / v5+):**
- Committed-cost tracking (POs/subcontract commitments distinct from paid actual costs)
- True labor burden rate (overhead/benefits allocation beyond wage rate)
- Estimate-accuracy trend reporting (quoted vs. actual variance feeding back into AI confidence)
- Formal WIP/percentage-of-completion GAAP accounting — delegate to the eventual QuickBooks/Xero integration
- Enterprise procurement workflows (RFIs, submittals, PO approval chains) — explicit anti-feature for this audience
- Multi-entity/multi-currency consolidated reporting

### Architecture Approach

A new `backend/app/features/finance/` module (mirroring the existing `billing_milestones/` shape) owns three new models — `CostEntry`, `LaborRate`, `Budget` — plus a non-CRUD `FinanceService` aggregation class (same pattern as `ReportingService`) that computes margin/budget-vs-actual live, on every request, with no materialized snapshot table until scale demands it. `TimeEntry` is extended in place (nullable `trade_scope_id`/`task_id`, relaxed nullable `job_id`) rather than forked into a parallel table, and `DashboardAlert` is reused (new `alert_type` values) rather than duplicated for financial alerts. Both new AI features reuse the existing `AIService` Claude tool-use plumbing at two different call shapes: the profitability analyzer is a scheduled nightly batch job (mirrors `run_alert_detection`), and the quote estimator is a synchronous, single-shot structured-generation endpoint (mirrors checklist generation, not the multi-turn intake conversation).

**Major components (new):**
1. `CostEntry` — actual-cost transaction (material/subcontractor) attached to a job or trade scope via the same nullable-pair XOR pattern as `Quote`/`Invoice`
2. `LaborRate` — effective-dated hourly cost rate per user (not a mutable single column), so historical margins stay reproducible after rate changes
3. `Budget` — target spend ceiling per project or trade scope
4. `FinanceService` — read-only aggregation: revenue (Quote/Invoice) minus cost (CostEntry + TimeEntry x LaborRate) = margin, compared against Budget for overrun risk
5. Financial analysis cron job — nightly per-company scan via APScheduler → Claude tool-use call → persisted `DashboardAlert` rows (new `alert_type`s)
6. `QuoteEstimatorService` — on-demand Claude tool-use call pricing new quote line items from historical `QuoteLineItem`/`LaborRate` data
7. `finance.*` permission catalog entries — explicitly excluded from admin's auto-derived wildcard set, explicitly granted to project_manager

Suggested backend build order (dependency-constrained): (1) schema + RBAC foundation → (2) actual-cost capture → (3) labor rate management → (4) TimeEntry extension for trade-scope/task time tracking → (5) margin computation (`FinanceService`) → (6) budgeting + overrun-risk → (7) web financial dashboard → (8) AI profitability analyzer → (9) AI quote planning (can parallelize with 6-8 once labor rates exist).

### Critical Pitfalls

1. **Job↔Project split-brain for cost attachment** — `Job` (v1.0) and `Project→TradeScope→Task` (v3.0) are parallel, non-overlapping hierarchies; cost entries and revenue must resolve through the same anchor-entity traversal or margin queries will silently miss or double-count costs. Define one canonical resolution path in schema design, before any margin query is written.
2. **Admin silently inherits `finance.*` via wildcard-derived permission set** — `_ADMIN_KEYS = PERMISSION_KEYS - _OWNER_ONLY_KEYS` means any new `finance.*` key is automatically granted to admin unless explicitly added to a new exclusion set in the same commit. Ship a regression test asserting no `finance.*` key appears in `DEFAULT_ROLE_PERMISSIONS["admin"]`.
3. **Existing `reports/dashboard` endpoint (gated by `require_admin`, not `finance.*`) is a live regression risk** if extended with margin fields — audit every pre-existing money-adjacent endpoint (reports, dashboard, PDF export, AI chat, client portal), not just newly built ones.
4. **AI hallucination and leakage via existing chat/checklist/alert surfaces** — Claude tool handlers that fetch "project context" will start returning cost/margin fields once those columns exist, unless tool-result construction filters by the calling user's `finance.*` permission as its own authorization boundary, and every AI-stated dollar figure must trace to a tool-sourced value, never an estimate.
5. **Retroactive rate changes silently rewrite historical margin/cost history** — labor cost must snapshot the effective rate at calculation time (via the effective-dated `LaborRate` table), never a live join to a mutable "current rate."
6. **Legacy pre-v4.0 jobs showing fabricated $0/100% margins** — `SUM()` over empty cost records must not silently coerce to `$0` cost; track a "cost data completeness" flag and explicitly branch "no data" vs. a real result, especially before AI quote planning uses historical data as pricing grounding.
7. **Float/mixed-precision drift** — the mobile client already computes quote/invoice totals with Dart `double`; new margin/budget entities must use a decimal-safe pattern instead, and backend aggregation must ban implicit `float()` casts on money paths.

## Implications for Roadmap

Based on combined research, the following phase structure is recommended. Ordering is constrained by hard data dependencies (cost data before margin, margin before budgeting/AI) and by the RBAC/split-brain pitfalls that must be resolved at the schema level before any financial data exists.

### Phase 1: Financial Schema Foundation + RBAC
**Rationale:** Every other v4.0 feature reads/writes `finance.*`-gated data. The Job↔Project cost-anchor resolution and the admin-exclusion-set fix are schema/permission decisions that are expensive to retrofit once cost records exist without them. This has no feature dependencies and is the only valid starting point.
**Delivers:** `cost_entries`, `labor_rates`, `budgets` tables; `time_entries` extended (nullable `job_id`, new nullable `trade_scope_id`/`task_id`, XOR validator); `finance.*` permission keys seeded (owner + project_manager default, explicitly excluded from admin's auto-derived set)
**Addresses:** finance.* RBAC (table stakes), cost categories (table stakes)
**Avoids:** Pitfall 1 (Job/Project split-brain), Pitfall 5 (admin wildcard inheritance), Pitfall 4 (pre-existing endpoints bypassing finance.*) — audit `reports/router.py` and `dashboard/service.py` in this phase

### Phase 2: Actual-Cost Capture and Labor Rates
**Rationale:** Cost capture and labor-rate management are independent, low-risk CRUD slices with no dependency on each other, and both are hard prerequisites for margin computation. Effective-dated `LaborRate` (not a mutable `User.hourly_rate` column) must be the initial design, since retrofitting after cost records exist without rate snapshots requires a lossy backfill.
**Delivers:** Itemized material/subcontractor cost entries (amount, category, trade scope/job, date); effective-dated hourly cost rate per contractor
**Uses:** `Decimal`/`Numeric` end-to-end, `TenantScopedRepository`/`BaseService` conventions
**Avoids:** Pitfall 2 (burden-rate omission — flag unburdened labor cost explicitly in UI/AI output), Pitfall 7 (retroactive rate rewrites), Pitfall 3 (double-counting — new cost table must never reuse `QuoteLineItem`/`InvoiceLineItem` for cost math)

### Phase 3: Profit Margin Tracking
**Rationale:** The single highest-value deliverable — directly satisfies the milestone's headline requirement — and should land as soon as its two inputs (cost capture, labor rates) exist, before budgeting or AI. `FinanceService` follows the existing `ReportingService` precedent (plain aggregation class, on-the-fly SQL, no snapshot table).
**Delivers:** `GET /finance/projects/{id}/margin`, `GET /finance/jobs/{id}/margin` — revenue (Quote/Invoice) minus cost (CostEntry + TimeEntry x LaborRate) = margin, per project and per trade scope
**Implements:** `FinanceService` (Pattern 3: on-the-fly aggregation, no materialized view until scale demands it)
**Avoids:** Pitfall 9 (legacy jobs with no cost data showing fabricated 100% margin — requires an explicit completeness flag), Pitfall 10 (float/decimal drift — shared `to_money()` utility, no client-side `double` for new margin entities)

### Phase 4: Budgeting and Overrun Alerts
**Rationale:** Budgeting and overrun-risk both consume margin/cost output from Phase 3. Naive static-threshold alerting cries wolf against front-loaded material costs and back-loaded labor spend; alert delivery must not reuse the existing GC↔contractor chat/notification pipeline without a `finance.*` permission check on the recipient.
**Delivers:** Budget CRUD per project/trade scope; budget-vs-actual view; trend/velocity-based overrun-risk alerts routed through a dedicated finance-gated channel
**Uses:** APScheduler (new job alongside existing checklist/alert jobs), existing FCM infrastructure with permission-scoped recipient filtering
**Avoids:** Pitfall 8 (alert noise / leaking financial status to non-finance roles via existing notification pipeline)

### Phase 5: Web Financial Dashboard
**Rationale:** Consumes the cost/labor/margin/budget endpoints from Phases 2-4. Extends the existing v2.0 reporting dashboard rather than building an isolated screen, matching user expectation that margin data lives alongside existing revenue/utilization reporting.
**Delivers:** `features/finance/` web module (CostEntryForm, BudgetForm, MarginSummaryCard), Financials tab on project detail, company-wide margin view under Reports, permission-gated nav
**Uses:** Recharts (`ComposedChart`, stacked `BarChart`, `ReferenceLine`), TanStack Query via existing `/api/proxy` pattern
**Avoids:** Pitfall 4 continuation — new dashboard components must call dedicated `/finance/*` endpoints, never embed margin fields on existing `Project`/`Job` response schemas

### Phase 6: AI Profitability Analysis
**Rationale:** Requires clean, structured margin and budget-vs-actual data (Phases 3-4) to reason over — sequencing AI before the underlying data is stable risks low-trust, noisy AI output on a feature users will rely on for financial decisions.
**Delivers:** Nightly per-company scan flagging margin erosion / budget overrun risk, with Claude-generated severity/impact/remediation text persisted as `DashboardAlert` rows
**Uses:** Existing `AIService` Claude tool-use plumbing, Structured Outputs/`strict: true`, APScheduler cron (mirrors `run_alert_detection`)
**Avoids:** Pitfall 6 (AI hallucination/leakage) — every numeric claim must trace to a tool call; the existing non-finance AI surfaces (chat, checklists, schedule alerts) must be retrofitted in this phase to strip financial fields from their prompt context, since this is a cross-cutting concern surfaced by adding finance columns to entities those tools already read

### Phase 7: AI-Assisted Quote Building
**Rationale:** Most independent of the two AI features — only needs historical pricing data (Phase 2), not the margin/budget machinery — so it can run in parallel with Phases 4-6 if sequencing constraints require it. Has a cold-start dependency (thin suggestions for companies with little history) that shapes UX but doesn't block launch.
**Delivers:** On-demand, single-shot structured generation of priced labor+material line items for a new quote, human-reviewed and approved before sending — never autonomous
**Uses:** `QuoteEstimatorService` (stateless Claude tool-use call), historical `QuoteLineItem.unit_price` + `LaborRate` aggregation via SQL, not embeddings/vector search
**Avoids:** Pitfall 9 continuation (historical dataset must filter to jobs with `has_actual_cost_data = true`, excluding pre-v4.0 jobs with fabricated margins from the pricing baseline)

### Phase Ordering Rationale

- Phase 1 must come first in its entirety — both the split-brain cost-anchor resolution and the admin-permission-exclusion fix are schema/catalog decisions that are cheap now and expensive (data migration, security incident response) after cost data exists.
- Phases 2 and 3 are the "boring, foundational" data-capture layer that PITFALLS.md and ARCHITECTURE.md both independently flag as needing to be solid before AI features consume it — sequencing AI earlier risks reasoning over incomplete/noisy data and damaging user trust in financial AI output specifically (a higher-stakes trust failure than in the existing checklist/chat AI features).
- Phase 4 (budgeting) depends on Phase 3 (margin) because "overrun risk" requires actual-vs-budget comparison, which requires actual costs to already be computed correctly.
- Phase 5 (web dashboard) is placed after the backend financial core (2-4) is complete so it consumes stable endpoints rather than co-evolving with backend schema changes.
- Phase 6 (AI profitability) depends on 3-4 for clean structured input; Phase 7 (AI quoting) only depends on Phase 2 and can be pulled forward or parallelized with the team's AI workstream without blocking on 3-6, per ARCHITECTURE.md's build-order analysis.
- The RBAC audit of pre-existing endpoints (Pitfall 4) is explicitly called out to happen in Phase 1, not deferred — it's a retrofit of code that already exists (`reports/router.py`), not new code, and the longer it's deferred the more new financial fields there are to audit.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1 (Schema Foundation + RBAC):** The exact cost-anchor resolution algorithm for orphan jobs (no trade_scope/project link) needs a concrete design spike against real data — ARCHITECTURE.md and PITFALLS.md both flag this as the single highest-risk design decision, worth a short research-phase pass to enumerate all current job/project linkage states in the data before writing the resolution logic.
- **Phase 6 (AI Profitability Analysis):** Retrofitting role-scoped tool context into the existing chat/checklist/schedule-alert AI surfaces (built pre-v4.0, per Phase 21/26) is a cross-cutting change to code outside this milestone's new module — needs a research/audit pass to enumerate every existing Claude tool handler and its data-fetch pattern before deciding the filtering mechanism.
- **Phase 4 (Budgeting/Overrun Alerts):** Trend/velocity-based overrun projection (accounting for front-loaded materials vs. back-loaded labor) needs a short domain-research or prototyping pass — static-threshold alerting is well-understood, but the "avoid crying wolf" requirement calls for a specific algorithm decision not fully specified by any research file.

Phases with well-documented patterns (research-phase can likely be skipped):
- **Phase 2 (Cost Capture + Labor Rates):** Standard CRUD following existing `TenantScopedModel`/`BaseService`/`TenantScopedRepository` conventions; effective-dated rate table is a well-established pattern (ARCHITECTURE.md provides a concrete `LaborRate` model).
- **Phase 3 (Margin Tracking):** `FinanceService` has a direct precedent in the existing `ReportingService` — aggregation SQL patterns (`FILTER`, window functions) are standard PostgreSQL 13/SQLAlchemy 2.0.
- **Phase 5 (Web Dashboard):** Directly extends the existing v2.0 Recharts/TanStack Query reporting dashboard pattern; no new UI paradigm.
- **Phase 7 (AI Quote Building):** Reuses the existing `AIService` tool-use plumbing at a simpler (stateless, single-shot) call shape than the existing multi-turn intake conversation.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Verified against official Anthropic SDK changelog/docs (Structured Outputs GA date confirmed), official PostgreSQL feature-version history, and direct inspection of `.planning/PROJECT.md` for current stack state; zero new dependencies reduces uncertainty surface substantially |
| Features | MEDIUM-HIGH | Cross-referenced against 6+ named competitor platforms (Buildertrend, Knowify, ServiceTitan, Jobber, CoConstruct, Procore) via WebSearch; domain/business-logic research rather than library-API research, so slightly lower confidence than a Context7-verified technical claim, but consistent findings across independent sources |
| Architecture | HIGH | Grounded in direct reading of the existing codebase (models, services, routers, migrations, scheduler, RBAC catalog) — not external ecosystem research; every recommended pattern has a cited precedent already shipping in this repo |
| Pitfalls | HIGH | Grounded directly in this codebase's models, routers, and permission catalog (e.g., the exact `_ADMIN_KEYS` derivation and the exact `require_admin` gating on `reports/router.py` were read directly, not inferred); construction-domain pitfalls (burden rate, front-loaded costs) are industry-standard practice, medium confidence but not load-bearing for the codebase-specific findings |

**Overall confidence: HIGH**

### Gaps to Address

- **Orphan job / cost-anchor resolution algorithm:** No research file specifies the exact traversal logic for jobs with no trade_scope/project link. Must be resolved as a concrete design decision in Phase 1 before any `CostEntry`/`Budget` migration ships — flag for a short research-phase or design-spike pass.
- **Burden rate default value:** PITFALLS.md recommends a configurable `burden_multiplier` per company but does not specify a construction-industry-realistic default (commonly cited range is 20-50% on top of base wage). Needs a product decision, ideally validated against real contractor data, before Phase 2 ships.
- **Mobile scope for trade-scope/task time tracking:** ARCHITECTURE.md explicitly flags this as an open roadmap decision — whether trade-scope/task clock-in ships in the mobile UI this milestone, or whether v4.0 labor-cost-from-time-entries is initially job-only (simpler) with project/trade-scope time tracking following in a later milestone. This affects Phase 2's scope and should be settled during roadmap creation, not left implicit.
- **Overrun-alert projection algorithm:** "Trend/velocity-based" alerting is recommended over static thresholds, but no research file specifies the exact projection formula (e.g., linear burn-rate extrapolation vs. phase-weighted expectation). Needs a short design pass in Phase 4.
- **AI cost-data completeness threshold:** PITFALLS.md recommends a minimum-data threshold before alerting/AI analysis kicks in (to avoid false alarms on sparse data) but doesn't specify the exact threshold (e.g., minimum cost entry count, minimum days elapsed). Product decision needed before Phase 4/6.

## Sources

### Primary (HIGH confidence)
- Direct codebase inspection: `backend/app/features/jobs/models.py`, `projects/models.py`, `quotes/models.py`, `invoices/models.py`, `billing_milestones/models.py`, `dashboard/models.py`/`service.py`, `reports/router.py`/`service.py`, `ai/service.py`, `core/permissions.py`, `core/security.py`, `core/scheduler.py`, `core/base_service.py`/`base_repository.py`, `users/models.py`, `companies/models.py`
- `mobile/lib/features/quotes/domain/quote_entity.dart`, `invoices/domain/invoice_entity.dart` — confirmed existing `double`-based money math (precision gap source)
- `.planning/PROJECT.md` — v4.0 milestone scope, RBAC defaults, current stack state
- [Structured outputs — Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)
- [anthropic-sdk-python CHANGELOG.md](https://raw.githubusercontent.com/anthropics/anthropic-sdk-python/main/CHANGELOG.md) — Structured Outputs GA v0.77.0 (2026-01-29)

### Secondary (MEDIUM confidence)
- [Job Costing & Budget Overview — Buildertrend](https://buildertrend.com/help-article/job-costing-budget-overview/), [Cost Codes — Buildertrend](https://buildertrend.com/help-article/cost-codes-overview/)
- [Job costing software for trade contractors — Knowify](https://knowify.com/job-costing-software/)
- [Job Costing Software — ServiceTitan](https://www.servicetitan.com/features/job-costing-software), [Calculate technician burden rates — ServiceTitan Help](https://help.servicetitan.com/docs/calculate-technician-burden-rates)
- [Insights Dashboard — Jobber Help Center](https://help.getjobber.com/hc/en-us/articles/30100867609367-Insights-Dashboard), [Job Costing — Jobber](https://help.getjobber.com/hc/en-us/articles/14343244961175-Job-Costing)
- [Construction change order software — CoConstruct](https://www.coconstruct.com/features/change-order-software)
- [Procore Software Review 2025 — ConstructionBase.ai](https://www.constructionbase.ai/blog/procore-features-pricing-and-limitations-explained)
- [WIP schedules — AICPA & CIMA](https://www.aicpa-cima.com/professional-insights/article/wip-schedules-blueprints-for-solid-construction-accounting)
- [12 Best AI Estimating Software for Construction in 2026 — ConstructionPlacements](https://www.constructionplacements.com/best-ai-estimating-software-construction/)
- WebSearch: PostgreSQL GROUPING SETS/ROLLUP/CUBE/materialized views (EDB, Citus Data, Cybrosys)
- WebSearch: Python Decimal money-handling best practices (LearnPython.com, Shakuro)

### Tertiary (LOW confidence)
- General construction burden/overhead rate ranges (20-50% on top of base wage) — industry-standard practice cited without a specific default figure validated for this product's target audience; needs product-level validation before Phase 2

---
*Research completed: 2026-07-24*
*Ready for roadmap: yes*
