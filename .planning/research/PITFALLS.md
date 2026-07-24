# Pitfalls Research

**Domain:** Adding job costing, profit margins, budgeting, and AI-driven financial analysis to an existing multi-tenant construction management app (ContractorHub v4.0)
**Researched:** 2026-07-24
**Confidence:** HIGH (grounded directly in this codebase's models, routers, and permission catalog — not generic industry pitfalls)

This research is grounded in direct inspection of the current codebase:
- `backend/app/features/jobs/models.py` — `Job`, `TimeEntry` (no rate field, no trade_scope link)
- `backend/app/features/projects/models.py` — `Project` → `TradeScope` → `Task` hierarchy
- `backend/app/features/quotes/models.py` / `invoices/models.py` — both `Quote` and `Invoice` have **nullable `job_id` AND nullable `trade_scope_id`** ("either must be set")
- `backend/app/core/permissions.py` — permission catalog, `DEFAULT_ROLE_PERMISSIONS`, `_ADMIN_KEYS` (wildcard-minus-two derivation)
- `backend/app/features/reports/router.py` / `service.py` — existing revenue reporting, gated by `require_admin`/`require_roles`, **not** the granular `require_permission()` catalog
- `mobile/lib/features/quotes/domain/quote_entity.dart` / `invoices/domain/invoice_entity.dart` — client-side money math already uses `double`, not Decimal

This document supersedes the prior v3.0-milestone PITFALLS.md (AI planning / chat / photo annotation risks), which is out of scope for this milestone.

---

## Critical Pitfalls

### Pitfall 1: Job ↔ Project split-brain for cost attachment

**What goes wrong:**
The system has two partially-linked hierarchies: the legacy `Job` (v1.0, has `TimeEntry`, `JobNote`, GPS) and the newer `Project → TradeScope → Task` (v3.0). `Quote` and `Invoice` already straddle both — each has a nullable `job_id` **and** a nullable `trade_scope_id`, with a schema validator enforcing "at least one is set." When v4.0 adds actual-cost capture (materials, subcontractor invoices) and margin calculation, a new cost-entry model will face the same fork: does a materials receipt attach to a `Job`, a `TradeScope`, or both? If cost entry and revenue (quote/invoice) don't resolve to the same anchor entity per record, margin queries will silently miss costs (job-anchored cost, trade-scope-anchored revenue) or double-count (both linked, summed separately).

**Why it happens:**
The two hierarchies evolved at different milestones (Job in v1.0, Project/TradeScope in v3.0) and were never fully merged — `Quote`/`Invoice` papered over the gap with dual nullable FKs rather than resolving which entity is authoritative for money. `TimeEntry` (existing labor source) is anchored to `Job` only, with **no FK to `TradeScope` or `Project` at all**. Per-trade quoting (Phase 25) exists, so trade-scope-level revenue is already real, but trade-scope-level *labor cost* has no path today.

**How to avoid:**
- Before writing any margin/budget query, define one canonical cost-anchor resolution: e.g., every actual-cost row and every quote/invoice row resolves to a single `project_id` (derive it: `trade_scope.project_id` if trade_scope_id set, else look up the job's linked project if that link exists, else the job itself is the anchor for legacy standalone jobs with no project).
- If `Job` and `TradeScope` remain unlinked for old data, the margin engine must treat "orphan jobs" (job with no trade_scope/project link) as their own aggregation root — do not attempt to force old jobs into the new hierarchy.
- Add an explicit resolvable path from `TimeEntry`'s cost-aggregation to a project anchor — either backfill via `Job` or require new time entries for v4.0-created projects to resolve through `trade_scope → project`. Do not join through `Job.bookings` or guess.
- Write one integration test that asserts: for a given project, `sum(actual_costs) + sum(labor_from_time_entries)` and `sum(quote/invoice revenue)` both resolve through the *same* traversal path, so a project with mixed job-linked and trade-scope-linked records still nets out correctly.

**Warning signs:**
- Margin dashboards show `$0` or `NULL` cost for projects that clearly have logged time entries.
- Two different reports (e.g., project-level margin vs. job-level margin) disagree on total spend for what a user considers "the same job."
- A cost or revenue row exists with `job_id` set but no discoverable `trade_scope_id`/`project_id`, making it invisible to project-level rollups.

**Phase to address:**
Actual-cost data layer / profit margin tracking phase — resolve the anchor-entity question in the schema design step, before any margin calculation code is written.

---

### Pitfall 2: Labor cost calculated without burden/overhead rate (misleading margins)

**What goes wrong:**
`TimeEntry` (existing model) has `clocked_in_at`, `clocked_out_at`, `duration_seconds` — **no rate field of any kind**. If v4.0 naively multiplies `duration_seconds * some_hourly_rate` to get labor cost, and that rate is only the contractor's base wage, the resulting margin will overstate profitability by omitting payroll tax, insurance, workers' comp, equipment, and overhead — the "burden rate" that typically adds 20-50% on top of base wage in construction. A project can show a healthy 25% margin on paper while actually losing money once burden is applied.

**Why it happens:**
Time tracking was built in v1.0 purely for schedule/attendance purposes, with no cost dimension. It's tempting to bolt on a single flat "hourly_rate" number per contractor and call labor costing "done," because that's the minimum needed to produce a nonzero cost figure — but a single flat rate without a burden multiplier is one of the most common construction job-costing mistakes.

**How to avoid:**
- Model at minimum two rate components per contractor (or per company default): `base_hourly_rate` and `burden_multiplier` (or `burden_rate_per_hour`), and store the *effective* rate used at time of calculation on the cost record itself (see Pitfall 7 — don't leave it as a live join to a rate that can change later).
- Default burden multiplier should be configurable per company (construction burden rates vary widely by region/trade), not hardcoded.
- Surface the distinction in the UI/AI output: "labor cost" should be explicitly labeled as burdened or unburdened so owners aren't misled by a number that looks like cost but is really just gross wages.
- AI profitability analysis (Claude) must be given the burdened figure, not raw wages, or its "margin erosion" flags will be wrong from the start.

**Warning signs:**
- Margin reports look suspiciously good compared to the owner's intuition/QuickBooks numbers.
- Only one rate field exists on the contractor/user model with no burden concept.
- AI quote planning prices labor using the same unburdened rate as the cost-tracking side, making quotes systematically underpriced.

**Phase to address:**
Actual-cost data layer phase (schema for rates) with explicit sign-off on a domain-realistic default burden rate, before the profit margin tracking phase ships.

---

### Pitfall 3: Double-counting costs across quote line items, actual costs, and invoices

**What goes wrong:**
The system already has `QuoteLineItem` (estimated labor/material line items) and `InvoiceLineItem` (billed line items) — both are **revenue-side** records with `item_type IN ('labor','material')`. v4.0 adds a third, cost-side concept: actual materials/subcontractor cost entries. If the actual-cost feature is built naively, it's easy to (a) treat quote line items as if they were costs (they're estimated revenue, not spend), (b) double-count materials that appear both as an invoice line item passed through to the client *and* as a separately entered actual cost, or (c) count subcontractor invoices both as a "cost entry" and again if a matching `Invoice` record was also created for internal tracking.

**Why it happens:**
`item_type` on both `QuoteLineItem` and `InvoiceLineItem` already reuses the word "material," which invites confusion between "what we billed the client for materials" and "what we actually spent on materials." Without a hard schema/naming separation, it's natural for a developer (or the AI) to sum `InvoiceLineItem` totals as a proxy for "actual cost" since it's already there and looks similar.

**How to avoid:**
- Introduce a distinctly-named new table (e.g., `actual_costs` or `job_cost_entries`) that is unambiguously cost-side only, with a `source` enum (`materials`, `subcontractor`, `labor_derived`) and never reuses `QuoteLineItem`/`InvoiceLineItem` for cost math.
- Margin formula must be exactly: `revenue = sum(invoice line items actually billed)` (or quote total if no invoice yet) **minus** `cost = sum(actual_costs) + sum(burdened labor from time_entries)`. Never sum quote line items into cost, and never let invoice line items feed the cost side even though they're structurally similar rows.
- If subcontractor invoices are entered as actual-cost records, make sure they're not *also* double-entered into the existing `Invoice` model (which represents money owed *to* the company, not money the company owes out) — these are different directions of cash flow and must not share a table without a clear `direction` discriminator.
- Add a unique/idempotency constraint or a UI-level guard preventing the same source document (e.g., photo of a subcontractor invoice) from producing two cost entries.

**Warning signs:**
- Margin percentage exceeds gross quote markup (a mathematical impossibility if cost includes revenue-side rows by mistake).
- Cost total changes when a quote is revised (revision should never move actual cost).
- Subcontractor spend appears in both a "money out" report and a "money in" report.

**Phase to address:**
Actual-cost data layer phase — establish the schema and formula contract with tests before profit margin tracking or AI profitability phases consume it.

---

### Pitfall 4: New reports/dashboard endpoints bypass the finance.* permission model entirely

**What goes wrong:**
The existing `reports` feature (`backend/app/features/reports/router.py`) already computes `_get_revenue_by_month` and other money aggregates, but is gated by `require_admin` / `require_roles(current_user, "contractor", "admin", ...)` — a completely different, coarser authorization mechanism than the granular `require_permission("quotes.view")`-style catalog used by `quotes`/`invoices` routers. If v4.0 adds margin/cost fields to this existing `/reports/dashboard` endpoint (the natural place to put them, since it already renders revenue-by-month), those new fields will be gated by `require_admin`, not the new `finance.*` permission — meaning any user with the `admin` role sees profit/margin data even though PROJECT.md explicitly scopes v4.0 financial data to **owner and project_manager only by default**. This is a live regression risk, not a hypothetical one — the exact endpoint and exact gating mechanism already exist and already disagree with the new requirement.

**Why it happens:**
It's the path of least resistance to extend an endpoint that already renders "revenue" with a few more fields ("cost", "margin") rather than build a new endpoint from scratch — but that shortcut silently inherits the old, wrong authorization check. Nobody re-audits an existing endpoint's auth decorator when adding fields to its response schema.

**How to avoid:**
- Audit every existing endpoint that could plausibly be extended with cost/margin/budget data: `reports/router.py` (`require_admin`), `dashboard/router.py` (check its gating — Phase 26 AI alerts), `projects`/`jobs` routers' detail endpoints, PDF export endpoints, and the AI chat/checklist endpoints. For each, either (a) split financial fields into a separate, `finance.*`-gated endpoint/response, or (b) explicitly add a second permission check inside the handler that filters financial fields out of the response for callers lacking `finance.*` — never rely on the existing role check alone.
- Do not conflate "admin role" with "finance access" going forward — the new model explicitly excludes admin from `finance.*` by default (see Pitfall 5). Treat every pre-v4.0 endpoint as guilty (leaking) until proven to filter on `finance.*`.
- Write an authorization test matrix: for each role (owner, admin, project_manager, gc, foreman, contractor, worker, client), assert exactly which endpoints return cost/margin fields and which return `403` or omit those fields.

**Warning signs:**
- A financial field appears in a Pydantic response schema whose endpoint's only guard is `require_admin`, `require_roles`, or nothing.
- Grep for `margin`, `profit`, `actual_cost`, `budget` in schemas turns up fields on response models attached to routes without a `finance.*` `require_permission` call.
- Manual test: log in as `admin` (not owner/project_manager) and confirm profit data is genuinely inaccessible everywhere, not just on the "obvious" new endpoints.

**Phase to address:**
Financial RBAC (finance.* permissions) phase — must ship an audit of all pre-existing money-adjacent endpoints, not just gate new ones. This phase should run early/in parallel with the first financial-data phase, not last.

---

### Pitfall 5: Admin role silently inherits finance.* via wildcard-derived permission set

**What goes wrong:**
`backend/app/core/permissions.py` derives admin's permission set as `_ADMIN_KEYS = sorted(PERMISSION_KEYS - set(_OWNER_ONLY_KEYS))` — i.e., admin automatically gets **every** catalog key except the two explicitly listed `_OWNER_ONLY_KEYS` (`company.settings.manage`, `company.billing.manage`). This is a deliberate "admin = everything except these two" design. If new `finance.*` keys (e.g., `finance.margins.view`, `finance.costs.view`, `finance.budgets.manage`) are simply added to `PERMISSION_CATALOG` without also adding them to `_OWNER_ONLY_KEYS` (or an equivalent new exclusion set), admin will automatically and silently receive full financial access — directly contradicting the v4.0 requirement that finance data defaults to **owner + project_manager only**.

**Why it happens:**
The wildcard-minus-exclusion-list pattern was designed for a world where "admin should get everything except company-level settings/billing." It was never designed with a third access tier (finance, restricted to two specific roles rather than "everyone but owner") in mind. Adding new permission keys is a one-line change to `PERMISSION_CATALOG`; remembering to also update `_OWNER_ONLY_KEYS` (whose name doesn't even suggest it should hold finance keys) is easy to forget.

**How to avoid:**
- Rename or extend the exclusion mechanism to make the intent explicit — e.g., a new `_FINANCE_ONLY_KEYS` set explicitly excluded from `_ADMIN_KEYS`, or restructure `_ADMIN_KEYS` derivation as `PERMISSION_KEYS - _OWNER_ONLY_KEYS - _FINANCE_ONLY_KEYS`.
- Every new `finance.*` catalog entry must be added to this exclusion set in the same commit that adds it to `PERMISSION_CATALOG` — enforce with a test that asserts no `finance.*` key (iterate `PERMISSION_CATALOG` for `key.startswith("finance.")`) appears in `DEFAULT_ROLE_PERMISSIONS["admin"]`.
- Confirm the product intent for `owner`'s wildcard (`[WILDCARD]`) — owner already gets everything via `"*"`, which is correct per requirements; the risk is entirely on the admin derivation, not owner.
- Since PROJECT.md says finance permissions are "adjustable per-company via the Roles & Permissions matrix," make sure the *default* seed is owner+PM only, but don't hardcode elsewhere that admin can never have it — the toggle must remain company-editable, just not admin-default.

**Warning signs:**
- A test seeds a fresh company, creates an `admin` user, and that user can successfully call a `finance.*`-gated endpoint without the company having explicitly granted it.
- Code review of the permissions module doesn't show a finance-specific exclusion list, only the two-item `_OWNER_ONLY_KEYS`.

**Phase to address:**
Financial RBAC phase — the permission catalog change and the exclusion-set change must ship together, with a regression test as described above.

---

### Pitfall 6: AI (Claude) hallucinates financial figures or leaks cost/margin data to unauthorized roles via chat, checklists, or alerts

**What goes wrong:**
Two distinct failure modes:
1. **Hallucination:** AI profitability analysis and AI quote planning are Claude-driven (per PROJECT.md). If the AI is asked to "flag margin erosion" or "price a quote from company history" and the underlying data is sparse (see Pitfall 10) or the prompt doesn't force grounding in actual queried numbers, Claude can produce plausible-sounding but fabricated dollar figures, percentages, or "based on similar past jobs" claims that have no basis in the database.
2. **Leakage via existing AI surfaces:** This app already has AI-generated daily checklists, AI project intake, AI contractor interviews, GC↔contractor chat, and AI dashboard alerts (Phase 26, using Claude tool use). Contractors, foremen, and workers already interact with these AI surfaces. If a contractor asks the AI chat "why is this task taking so long" or the AI schedule-adaptation alert system pulls project context to explain a delay, and the underlying tool/prompt context includes cost or margin data (because it's now sitting in the same `Project`/`TradeScope` rows the AI already reads), that financial data can leak into a chat response or checklist item visible to a `contractor`/`foreman`/`worker` role — none of whom should have `finance.*` access.

**Why it happens:**
The existing AI tool-use pattern (`backend/app/features/ai/prompts/tools.py`, `dashboard/prompts/alert_system.py`) was built before financial data existed on these entities. Tools that fetch "project context" or "task context" for the AI will naturally start returning cost/margin fields once those columns exist on `Project`/`TradeScope`/`Task`, unless someone deliberately scopes what each tool returns by the *permission of the user who triggered the AI call* — not just by what data technically exists on the row.

**How to avoid:**
- Every Claude tool definition/handler must resolve and filter its returned data by the calling user's `finance.*` permission, exactly as HTTP endpoints do — treat tool-result construction as its own authorization boundary, not just the outer endpoint.
- AI profitability analysis and AI quote planning (the two genuinely finance-scoped AI features) should be invoked only from endpoints already gated by `finance.*`, and their system prompts should be given real, queried numbers (via tool calls returning DB-sourced Decimal values) rather than being asked to "estimate" — require the tool-use pattern (already established in this codebase) for any numeric claim, and reject/regenerate responses that state a dollar figure not traceable to a tool result.
- For the *non*-finance AI surfaces (daily checklists, chat, schedule-slip alerts, contractor interview), explicitly strip cost/margin/budget fields from whatever project/task context object is serialized into the prompt — do not assume "the AI doesn't need it so it won't use it"; construct role-scoped context objects the same way role-scoped API responses are constructed.
- Add an automated test that seeds a project with margin data, triggers each existing non-finance AI flow (checklist generation, chat response, schedule alert) as a `contractor`/`foreman` role, and asserts no dollar figures/margin percentages related to `finance.*` fields appear in the generated content.

**Warning signs:**
- A Claude tool handler does a plain `selectinload` of `Project` or `TradeScope` without checking the caller's permissions, then serializes the whole ORM object (or most of its fields) into the prompt.
- AI chat or checklist text mentions specific dollar amounts, "profit," "margin," or "over budget" and the calling user is not owner/project_manager.
- No automated test exists asserting AI-generated content is free of financial data for non-finance roles.

**Phase to address:**
AI profitability management phase and AI quote planning phase, but the *filtering discipline* (role-scoped tool context) must be retrofitted to the existing AI daily-checklist/chat/alert phases as part of the financial RBAC phase — this is a cross-cutting concern, not isolated to the two new AI features.

---

### Pitfall 7: Retroactive rate changes silently rewrite historical margin/cost history

**What goes wrong:**
If labor cost is computed live at query time as `duration_seconds * current_hourly_rate` (a join to a mutable `hourly_rate` field on the contractor/user record) rather than a rate snapshotted at the time the cost was incurred, then editing a contractor's pay rate today changes the calculated cost — and therefore the margin — of every project that contractor ever worked on, including ones completed months ago and already reported/invoiced. The same applies to burden multipliers, tax rates, or company-wide default rates used in budgeting: any "current value" join into historical aggregation silently rewrites the past.

**Why it happens:**
Storing a live FK/join to "the rate" is simpler to build than snapshotting a rate onto each cost record, and it "just works" until someone gives a raise or corrects a rate — at which point historical reports that were already shown to an owner (or included in a closed-period financial summary) change retroactively with no audit trail, undermining trust in the numbers.

**How to avoid:**
- Every cost record (labor-derived or manual) must snapshot the exact rate(s) used (`rate_at_time`, `burden_multiplier_at_time`) at creation/calculation time, not reference a live rate table.
- If a rate correction needs to apply retroactively (e.g., a data-entry error), require an explicit, audited "recalculate historical costs for date range X" action — never an implicit side effect of editing the current rate.
- Budgets and their "spend so far" figures should likewise be computed from snapshotted cost records, so a rate change never moves a budget's overrun status for a period that's already been reported/closed.
- Mirror the existing `TimeEntry.adjustment_log` pattern (JSONB audit trail already used for clock-in/out edits) for rate changes — log who changed a rate, when, old/new value, and whether historical recalculation was triggered.

**Warning signs:**
- A margin calculation function takes only `time_entry_id` and internally joins to `user.hourly_rate` rather than reading a rate stored on a cost record.
- Two runs of the "project margin as of last month" report produce different numbers today than they did last month, with no corresponding data correction logged.

**Phase to address:**
Actual-cost data layer phase — the rate-snapshotting decision must be made in the initial schema design, since retrofitting it after cost records already exist without a rate column requires a lossy backfill.

---

### Pitfall 8: Budget overrun alerts cry wolf (or leak financial status to unauthorized roles)

**What goes wrong:**
Naive overrun alerting (e.g., "alert if spend > 90% of budget") fires constantly on any project where the budget was set conservatively, where early costs are front-loaded (materials bought upfront, labor spread over the whole job), or where an actual-cost entry is late/missing (spend looks fine one day, jumps 30% the next when a subcontractor invoice is finally entered). Combined with the fact that this system already has a precedent for AI-driven proactive alerts (Phase 26's schedule-slip alert system, which itself required "flag issues, create punch list items" workflows to avoid noise) — a budget alert system built without similar noise-reduction discipline will either bury real overruns in false positives (owners start ignoring all financial alerts) or, if the alert delivery reuses the existing notification/chat channels used by contractors and foremen, could leak the fact that "this project is over budget" to roles who shouldn't see financial status at all.

**Why it happens:**
Threshold-based alerting is easy to implement and easy to over-fire; nobody tunes it against real spend patterns (front-loaded material costs, delayed cost entry, phase-based budgets vs. whole-project budgets) until users complain. Reusing the existing FCM/notification/chat pipeline (already built for schedule alerts, per Phase 26) is the path of least resistance but that pipeline's recipient list was designed around trade/schedule visibility, not `finance.*` visibility.

**How to avoid:**
- Base overrun risk on trend/velocity (e.g., projected spend at current burn rate vs. remaining budget and remaining timeline) rather than a single static percentage threshold, and account for known front-loading (materials typically front-loaded, labor typically back-loaded) rather than a flat linear expectation.
- Require a minimum data threshold before alerting (e.g., don't alert on a project with only one cost entry) to avoid false alarms from incomplete data.
- Route budget/margin alerts through a dedicated, `finance.*`-gated notification channel — do not reuse the existing GC↔contractor chat or the existing schedule-slip alert/notification pipeline without adding a permission check on the recipient, since those pipelines currently target GC/contractor/foreman audiences by design.
- Let owners/PMs configure or dismiss alert sensitivity per project (mirrors the existing `dismiss_alert`/`mark_alert_read` pattern already in `dashboard/service.py` for schedule alerts) rather than a single global threshold.

**Warning signs:**
- Alert volume is high enough that owners stop opening them (measure open/dismiss rate).
- A budget alert notification payload or push message is delivered to a device belonging to a `contractor`/`foreman`/`worker` user.
- Alerts fire in the first days of a project before enough cost data exists to make the projection meaningful.

**Phase to address:**
Budgeting phase (alert logic and thresholds) with delivery-channel permission-scoping validated against the financial RBAC phase.

---

### Pitfall 9: Migrating/backfilling historical jobs with no cost data produces misleading $0 or 100% margins instead of "unknown"

**What goes wrong:**
Every job/project created before v4.0 ships has quotes and invoices (revenue) but zero actual-cost records and, for labor, `TimeEntry` rows with no rate applied historically. If the margin engine treats "no cost records found" as `cost = 0`, historical projects will appear to have 100% profit margin — an obviously wrong and potentially embarrassing number if shown to an owner, and actively dangerous if fed into AI profitability analysis, which might "flag" the *newest* real project as underperforming relative to a fabricated 100%-margin historical baseline pulled from company history (this directly undermines AI quote planning, which is explicitly meant to price "from company history").

**Why it happens:**
`SUM()` over an empty set naturally returns `0` (or `NULL` coerced to `0`) in SQL, and it's easy to let that flow straight into a margin percentage calculation without an explicit "insufficient data" branch. Nobody notices in testing because test/demo data is usually created *after* the cost-tracking feature exists.

**How to avoid:**
- Explicitly track a "cost data completeness" flag or period per project/job (e.g., `has_actual_cost_data: bool`, or a `cost_tracking_started_at` timestamp) and have every margin display, report, and AI prompt distinguish "0% margin because costs equal revenue" from "margin unknown — no cost data captured for this job" — never silently coerce the latter into the former.
- AI quote planning's "price from company history" feature must filter its historical dataset to only jobs with complete cost data (post-v4.0 cost tracking, or explicitly backfilled), or it will anchor pricing suggestions on a fabricated 100%-margin baseline from pre-v4.0 jobs.
- If backfill is attempted for old jobs (e.g., approximating labor cost from `TimeEntry` durations with a best-guess historical rate), that data must be clearly flagged as "estimated/backfilled" in both UI and any data fed to Claude, distinct from precisely-captured actual costs.
- Decide explicitly (product decision, not silent default) whether pre-v4.0 jobs get margin displayed at all — many teams choose to simply exclude legacy jobs from margin reporting rather than show a misleading number.

**Warning signs:**
- Historical (pre-v4.0) projects show suspiciously round or suspiciously high margin percentages.
- AI quote planning suggests prices implying much higher margins than the company plausibly maintains.
- No column/flag exists anywhere distinguishing "verified zero cost" from "cost not tracked."

**Phase to address:**
Actual-cost data layer phase (schema: completeness flag) and AI quote planning phase (historical dataset filtering) — must be resolved before AI quote planning ships, since it's the feature most directly poisoned by this gap.

---

### Pitfall 10: Float/mixed-precision drift across aggregates, given the client already computes money with `double`

**What goes wrong:**
The backend correctly uses `Numeric`/`Decimal` columns throughout (`quotes`, `invoices`, and the existing `reports/service.py` explicitly does `Decimal(str(row.paid or 0)).quantize(Decimal("0.01"))`). However, `mobile/lib/features/quotes/domain/quote_entity.dart` and `mobile/lib/features/invoices/domain/invoice_entity.dart` already compute `subtotal`, `taxAmount`, and `total` as Dart `double` — binary floating point, not decimal. This is an existing, live precision gap in the codebase (not hypothetical). v4.0 adds new aggregation surfaces (margin = revenue − cost, summed across many line items and cost entries, then further aggregated to project/company level for budgeting and AI analysis) — if any of this new logic is written client-side using the same `double` pattern already established in `quote_entity.dart`/`invoice_entity.dart`, or if backend aggregation mixes `float()` casts with `Decimal` at any point (e.g., accidentally casting a `Decimal` to `float` before summing, a classic Python pitfall), rounding drift will compound across the larger number of terms in margin/budget sums, producing off-by-cents (or more, at scale) discrepancies between what a project detail page shows and what a company-wide financial rollup shows for the "same" numbers.

**Why it happens:**
Flutter/Dart has no first-class arbitrary-precision decimal type in the standard library, so `double` is the path of least resistance for UI-layer money math, and it's already the established pattern in this codebase for quotes/invoices — a new engineer adding margin display fields will naturally copy the existing pattern rather than question it. On the backend, Python's `Decimal` and `float` interoperate silently (implicit coercion errors are easy to introduce via a stray `float(x)` or a `**` operation), and `Decimal(str(row.value))` (the existing correct pattern in `reports/service.py`) is easy to get right in that one function and easy to forget in a new one.

**How to avoid:**
- Adopt one explicit rounding policy document (e.g., "all money stored as `Numeric(12,2)`, all intermediate aggregation done in `Decimal` with `ROUND_HALF_UP` at the final display quantize step, never before") and apply it uniformly — do not let each new endpoint invent its own rounding.
- On the backend, ban implicit `float` casts on money paths — the existing `Decimal(str(row.value or 0))` pattern from `reports/service.py` should become a shared utility (e.g., `to_money(value)`) reused everywhere new margin/budget aggregation is written, rather than re-implemented ad hoc.
- On the Flutter client, do not extend the existing `double`-based `quote_entity.dart`/`invoice_entity.dart` pattern into new margin/budget entities — use a decimal-safe package (e.g., store money as integer cents, or use a `Decimal` package) for any new client-side money math, especially anything that sums many line items/cost entries (more terms = more compounding drift than the existing 2-3-term quote/invoice totals).
- For any value AI-generated content quotes back to the user (e.g., "your margin is 23.4%"), ensure the AI is given the exact backend-rounded figure via tool result, not asked to compute or re-derive it, so the AI's stated number always matches what the UI shows.
- Add a test that constructs a project with a large number of line items/cost entries with values chosen to expose rounding drift (e.g., repeating decimals like thirds) and asserts project-level and company-level rollups agree to the cent.

**Warning signs:**
- A project detail page's margin doesn't match the same project's contribution to a company-wide margin report, even by a cent.
- Any new Dart file for margin/budget entities declares `double` fields for money.
- `grep` for `float(` in new backend financial code paths.

**Phase to address:**
Actual-cost data layer / profit margin tracking phase — establish the shared rounding utility and client-side decimal-safe pattern before any margin math ships; retrofit is expensive once multiple phases have their own ad hoc math.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|--------------------|-----------------|------------------|
| Extend existing `reports/dashboard` endpoint with margin fields instead of a new finance-scoped endpoint | Faster to ship, reuses existing charts/UI | Inherits wrong (`require_admin`) authorization — see Pitfall 4 | Never — always split or add explicit `finance.*` filtering |
| Compute labor cost as `duration_seconds * user.hourly_rate` live join | No new columns needed, works immediately | Retroactive rate changes rewrite history (Pitfall 7); no burden rate (Pitfall 2) | Only for a throwaway prototype/demo, never for shipped financial data |
| Let AI tool handlers return the full `Project`/`TradeScope` ORM object into the prompt | Less code to write per tool | Leaks finance fields to non-finance AI surfaces (Pitfall 6) | Never once finance columns exist on those models |
| Treat `SUM()` over empty cost records as `$0` cost | No special-casing needed | Fabricates 100% margins on legacy data, poisons AI quote planning (Pitfall 9) | Never for anything shown to a user or fed to AI — acceptable only in throwaway internal debugging queries |
| Use client-side `double` for new margin/budget totals (matching existing `quote_entity.dart` pattern) | Consistent with existing code, no new dependency | Compounding rounding drift as term count grows (Pitfall 10) | Never for anything beyond a rough progress-bar percentage that's never compared cent-for-cent against the backend |
| Reuse existing GC↔contractor chat/notification pipeline for budget alerts | No new delivery infrastructure | Leaks financial status to non-finance roles (Pitfall 8) | Never — build a separate finance-gated delivery path |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|-----------------|-------------------|
| Claude API (AI profitability analysis) | Asking Claude to "estimate" or "analyze" margin from a text summary rather than tool-sourced exact figures | Require tool-use for every numeric claim (mirrors existing `ai/prompts/tools.py` pattern); reject responses stating figures not returned by a tool call |
| Claude API (AI quote planning, "price from company history") | Querying all historical jobs indiscriminately, including pre-v4.0 jobs with no real cost data | Filter historical dataset to jobs with `has_actual_cost_data = true` (Pitfall 9); explicitly exclude/flag backfilled or estimated data |
| Claude API (existing chat/checklist/alert features, Phase 21/23/26) | Assuming these pre-existing AI surfaces are unaffected by v4.0 since they weren't "financial features" | They read the same `Project`/`TradeScope`/`Task` rows that will soon carry cost/margin columns — audit and scope their tool context (Pitfall 6) |
| Existing role-permission matrix UI (editable per company) | Adding `finance.*` keys to `PERMISSION_CATALOG` without updating the admin-exclusion logic | Explicit exclusion set for finance keys, tested (Pitfall 5) |
| Existing RLS (`company_id` via ContextVar + `SET LOCAL`) | Assuming tenant-level RLS is sufficient isolation for financial data | RLS isolates *companies* from each other, not *roles within* a company — `finance.*` is an application-layer (`require_permission`) concern layered on top of, not replacing, RLS |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|-----------------|
| Live-joining current rate tables for every margin query instead of snapshotted rates | Margin dashboard queries slow down as historical job count grows, and get *slower* to reason about correctness over time | Snapshot rates onto cost records at creation (also fixes Pitfall 7) | Noticeable once a company has hundreds of historical jobs and dozens of rate changes |
| Recomputing project margin from scratch (summing all time entries + cost entries + line items) on every dashboard load | Dashboard/report latency grows with project age and line-item count | Maintain a denormalized/cached margin summary per project, invalidated on cost/revenue mutation (mirrors `ClientProfile.average_rating` denormalization pattern already used in this codebase) | Becomes noticeable once a project has hundreds of time entries/cost rows, or on company-wide rollups across many projects |
| AI profitability analysis re-fetching and re-summarizing full project financial history on every chat/alert trigger | Slow AI response times, higher Claude token cost, budget overrun on API spend | Feed AI a pre-computed summary (already-aggregated numbers) via tool result rather than raw row-level data | Breaks noticeably once projects accumulate enough cost/time entries that the tool payload approaches context-size or latency budgets |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Trusting `require_admin`/role-name checks as a proxy for financial authorization | Admin (and any future coarse "admin-like" role) sees profit/margin/budget data never intended for them (Pitfall 4, 5) | Every financial data path must pass through `require_permission("finance.*")`, never a role-name check alone |
| Letting AI tool handlers bypass the calling user's permission scope (since tool code runs server-side "as the AI," not visibly "as a user request") | Financial data leaks into AI-generated content shown to unauthorized roles (Pitfall 6) | Pass the *calling user's* permission set into every tool handler and filter results before they enter the prompt context |
| Exporting reports/PDFs (existing PDF generation feature) that render whatever fields are in the underlying data object, without a finance-specific field allowlist | A PDF export triggered by (or shared with) a non-finance role/client leaks margin/cost data baked into a document that outlives the session/permission check | Financial fields must be explicitly opted into PDF/export templates gated by `finance.*`, not implicitly included because they exist on the underlying model |
| Client portal (`portal.access` permission, used by the `client` role) rendering project detail data that now includes cost/margin fields | Clients — who should never see internal cost/margin — see the company's profit on their own job via the existing client portal | Explicitly audit and strip financial fields from every client-portal-facing response schema; the client role must be doubly excluded (never even considered for `finance.*`) |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-------------------|
| Showing "$0 margin" or "100% margin" for jobs with no cost data instead of "no data" | Owner distrusts the whole feature once they spot an obviously wrong historical number | Explicit "insufficient cost data" state, visually distinct from a real $0/100% result (Pitfall 9) |
| Budget alerts firing early in a project's life before enough spend data exists | Owners start ignoring/muting all budget alerts, missing real overruns later | Minimum data/time threshold before alerting; trend-based rather than static-threshold alerting (Pitfall 8) |
| AI profitability suggestions stated with false confidence ("switch subcontractors to save 15%") without showing the underlying numbers | Owner can't verify or trust the recommendation, or worse, acts on a hallucinated figure | Always show the tool-sourced numbers alongside any AI recommendation, not just the conclusion |
| Presenting unburdened labor cost as "labor cost" without qualification | Owner believes margin is healthier than reality, makes bad pricing decisions | Explicitly label burdened vs. unburdened figures wherever labor cost appears |

## "Looks Done But Isn't" Checklist

- [ ] **Profit margin tracking:** Often missing a distinction between "verified $0 cost" and "no cost data tracked" — verify a pre-v4.0 legacy job doesn't show a fabricated 100% margin.
- [ ] **Actual-cost capture:** Often missing rate/burden snapshotting on each cost record — verify editing a contractor's current rate does not change the calculated cost of a completed historical job.
- [ ] **Budgeting/overrun alerts:** Often missing a check that alert delivery is routed only to `finance.*`-permitted users — verify a `contractor`/`foreman` test user never receives a budget notification via the existing chat/FCM pipeline.
- [ ] **AI profitability management:** Often missing a hard requirement that every numeric claim traces to a tool call — verify by inspecting a sample of AI-generated analyses for any dollar figure not present in the tool result payload.
- [ ] **AI quote planning:** Often missing historical-data filtering — verify pricing suggestions are not anchored on pre-v4.0 jobs with no real cost data.
- [ ] **Financial access control:** Often missing retrofitted checks on *pre-existing* endpoints (reports, dashboard, PDF export, AI chat, client portal) — verify the full authorization test matrix (every role × every money-adjacent endpoint), not just newly-built endpoints.
- [ ] **Job/Project cost attachment:** Often missing a resolved answer for orphan jobs (no trade_scope/project link) — verify legacy jobs still produce a coherent margin figure rather than silently dropping out of rollups.
- [ ] **Rounding/precision:** Often missing a shared money utility — verify no new Dart file for margin/budget uses `double`, and no new Python aggregation path casts `Decimal` to `float`.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|----------------|------------------|
| Admin silently has finance.* access (Pitfall 5) | LOW | Add finance keys to the exclusion set, ship a migration/backfill that removes those keys from any company's already-materialized `admin` role permission rows, audit-log the change, notify affected companies |
| Existing reports endpoint leaked margin data to admin (Pitfall 4) | LOW–MEDIUM | Patch the endpoint to filter fields by `finance.*`, then review access logs (if available) to determine blast radius/notify owners if sensitive data was exposed |
| Historical jobs show fabricated 100%/0% margins (Pitfall 9) | MEDIUM | Backfill a `has_actual_cost_data` flag defaulting to `false` for all pre-v4.0 jobs; update all margin displays/AI prompts to branch on it; no data loss, purely a display/filtering fix |
| Labor cost computed via live rate join, discovered after rate changes already occurred (Pitfall 7) | HIGH | Requires either accepting historical inaccuracy going forward (document it) or attempting a point-in-time rate reconstruction from `TimeEntry.adjustment_log`-style audit history if one exists — otherwise historical cost accuracy for the affected window is unrecoverable |
| Double-counted costs discovered in production margin figures (Pitfall 3) | MEDIUM | Add a `source`/`direction` discriminator retroactively, write a one-time reconciliation script identifying and flagging (not silently deleting) suspected duplicate cost entries for manual review |
| Job/Project split-brain causes missing costs in rollups (Pitfall 1) | MEDIUM | Backfill a resolved `project_id`/anchor on affected cost and time-entry records via best-effort join through existing job/trade_scope links; flag unresolvable orphans explicitly rather than guessing |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|----------------|
| 1. Job/Project split-brain for cost attachment | Actual-cost data layer phase | Integration test: mixed job-linked and trade-scope-linked cost/revenue records roll up correctly to one project total |
| 2. Labor cost without burden rate | Actual-cost data layer phase | Schema review confirms burden multiplier field exists and is applied; sample margin manually cross-checked against a burdened-rate expectation |
| 3. Double-counting costs | Actual-cost data layer phase | Unit test: margin formula never includes `QuoteLineItem`/`InvoiceLineItem` rows as cost inputs; idempotency test for duplicate cost entry prevention |
| 4. New endpoints bypass finance.* via existing reports/dashboard | Financial RBAC phase | Full authorization test matrix across all money-adjacent pre-existing endpoints (reports, dashboard, PDF export, AI chat, client portal) |
| 5. Admin inherits finance.* via wildcard derivation | Financial RBAC phase | Automated test asserting no `finance.*` key appears in `DEFAULT_ROLE_PERMISSIONS["admin"]` |
| 6. AI hallucination/leakage via chat/checklists/alerts | Financial RBAC phase (retrofit) + AI profitability/AI quote planning phases | Test each existing non-finance AI surface (checklist, chat, schedule alert) as a non-finance role, assert no financial content leaks; test finance AI features reject numeric claims not tool-sourced |
| 7. Retroactive rate changes rewrite history | Actual-cost data layer phase | Test: change a contractor's current rate, confirm historical cost records for already-completed periods are unchanged |
| 8. Budget alerts crying wolf / leaking via existing notification pipeline | Budgeting phase | Alert noise measured against realistic front-loaded cost patterns; test confirms non-finance roles never receive budget alert payloads |
| 9. Migration/backfill of historical jobs with no cost data | Actual-cost data layer phase + AI quote planning phase | Legacy job margin displays "no data" not $0/100%; AI quote planning dataset query excludes jobs without `has_actual_cost_data` |
| 10. Float/decimal drift across aggregates | Actual-cost data layer / profit margin tracking phase | Rounding-drift test with many line items summing to a value with repeating decimals; assert project-level and company-level rollups match to the cent |

## Sources

- Direct codebase inspection (HIGH confidence — these are not generic domain pitfalls but specific to this repository's current implementation):
  - `backend/app/features/jobs/models.py`
  - `backend/app/features/projects/models.py`
  - `backend/app/features/quotes/models.py`
  - `backend/app/features/invoices/models.py`
  - `backend/app/core/permissions.py`
  - `backend/app/features/reports/router.py`, `backend/app/features/reports/service.py`
  - `backend/app/features/dashboard/service.py` (existing AI alert pattern, Phase 26)
  - `mobile/lib/features/quotes/domain/quote_entity.dart`
  - `mobile/lib/features/invoices/domain/invoice_entity.dart`
  - `.planning/PROJECT.md` (v4.0 milestone scope and finance.* requirement)
- General construction job-costing domain knowledge (MEDIUM confidence, industry-standard practice, not sourced from a specific external document in this research pass): burden/overhead rate on labor, front-loaded material costs vs. back-loaded labor spend, quote-vs-actual-vs-invoice separation as standard job-costing discipline.

---
*Pitfalls research for: Financial-intelligence features (job costing, margins, budgeting, AI profitability/quote planning) added to an existing multi-trade construction management platform*
*Researched: 2026-07-24*
