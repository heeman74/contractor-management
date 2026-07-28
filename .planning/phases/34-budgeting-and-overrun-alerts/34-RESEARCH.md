# Phase 34: Budgeting and Overrun Alerts - Research

**Researched:** 2026-07-27
**Domain:** Budget evaluation + threshold alerting over the shipped Phase 30–33 finance stack (FastAPI/SQLAlchemy async/RLS backend, Next.js web, Flutter mobile)
**Confidence:** HIGH (all findings verified against the codebase directly; no external-library unknowns — every building block already ships in this repo)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Alert model (resolves the STATE.md open blocker)
- **D-01:** **Static 80%/100% thresholds with strict dedup.** Each budget fires exactly once per threshold crossing (80 warning, 100 overrun), tracked persistently so repeat evaluations never re-fire. No velocity/trend projection this phase — that judgment belongs to Phase 36's AI analysis. (Research Pitfall 6's noise problem is repeated alerts; dedup solves it.)
- **D-02:** **Evaluated on cost mutation + nightly sweep.** The affected budget(s) are checked synchronously when a cost entry is created/updated/deleted, AND a nightly cron sweep (Phase 26 APScheduler pattern) evaluates all budgets — required because derived labor grows on clock-outs with no cost-entry mutation to hook.
- **D-03:** **Thresholds re-arm on budget increase.** Raising a budget (manual edit or positive quote-revision delta) clears fired thresholds for that budget; crossing 80%/100% of the NEW total fires fresh alerts.
- **D-04:** **Independent per-budget alerting.** Project and scope budgets evaluate and alert independently against their own thresholds — a scope crossing never cascades a project-level notice. Alert content names the entity, threshold, spend, and budget figures.

#### Alert delivery (from SC3 + Phase 30 D-11)
- **D-05:** Dashboard alerts use new financial `alert_type` values (requires a migration for the `dashboard_alerts_alert_type_check` constraint) and are registered in Phase 30's `FINANCIAL_ALERT_TYPES` so the shipped permission-aware filter hides them from non-finance roles. FCM push goes only to users holding `finance.view` in the company.

#### Quote-revision → budget (BUDG-04)
- **D-06:** **Linkage mapping mirrors the cost/margin traversal:** a trade-scope-anchored quote adjusts that scope's budget; a job-anchored quote adjusts the project budget via `jobs.project_id` (a job with no project adjusts nothing); a project-level quote adjusts the project budget.
- **D-07:** **Delta is signed and pre-tax.** delta = new approved revision's pre-tax total − the previous approved quote's pre-tax total (Phase 33 D-13 basis). Downward revisions lower the budget too — the budget tracks committed revenue in both directions; a resulting below-spend budget simply fires honest overrun alerts.
- **D-08:** **No-op when no budget exists.** Approval proceeds normally and no budget is auto-created; the delta applies only where a budget row exists.
- **D-09:** The trigger is approval of the NEW quote row created by `revise_quote` (old row status='revised', new row revision_number+1) — the first approval of a revision chain establishes the baseline; subsequent approved revisions apply deltas.

#### Budget management
- **D-10:** **Full edit + soft-delete, no floor.** Budgets can be edited to any positive amount — including below current spend (next evaluation fires the crossed thresholds immediately, which is honest) — and soft-deleted like every other entity (deleted budgets stop evaluating). Gated `finance.manage`.
- **D-11:** **Total-only UI in v4.0.** The per-category breakdown rows (D-09 Phase 30) stay dormant — no allocation editor, no category-level thresholds.

#### UI surfaces
- **D-12:** **Extend the Costs sections** on project and trade-scope screens with budgeted vs spent vs remaining rows plus an inline "Set budget" action. No dedicated budgets screen. Established 31/32/33 pattern.
- **D-13:** **Web-edit + both-view.** Budget create/edit on web only (like rates, Phase 32 D-09 precedent), gated `finance.manage`; the budget-vs-actual view ships on both web and mobile, gated `finance.view`. Mobile fetches via API; no budget data persisted to Drift.

### Claude's Discretion
- Threshold-crossing state storage shape (fired-threshold columns on Budget vs a separate table), and how re-arm (D-03) resets it.
- Exact alert_type names, alert copy strings (a Phase 34 UI-SPEC pass locks UI strings), FCM payload shape, deep-link behavior.
- "Spent" computation reuse — how the budget evaluation calls into the shipped Phase 33 rollup/margin cost queries without duplicating traversal logic.
- Whether scope budgets use the scope's cost breakdown (scope-anchored costs only, labor "tracked at job level" exclusion noted honestly) — must be consistent with what the scope Costs section displays as spend.
- API shape (budget CRUD endpoints + budget-vs-actual in breakdown responses vs separate), additive-only extension of existing responses per the established mobile parsing contract.
- Migration numbering; nightly sweep scheduling details.

### Deferred Ideas (OUT OF SCOPE)
- Velocity/trend-based overrun projection with front-loading heuristics — Phase 36 AI territory (research Pitfall 6 full recommendation)
- Per-category budget allocation UI + category-level thresholds — schema ready, revisit post-v4.0
- Mobile budget editing — web-only this milestone, consistent with rates
- Scope-crossing → project-level rollup notices — rejected as Pitfall 6 noise; revisit only if owners ask
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BUDG-01 | Owner/PM can set a budget per project and per trade scope | `Budget` model + `BudgetCreate` schema (XOR project/scope) already shipped dormant — see "Surface 1"; CRUD endpoints follow the finance router `require_permission` pattern |
| BUDG-02 | Owner/PM can view budgeted vs spent vs remaining at project and trade level | Spend = Phase 33 rollup/breakdown reuse ("Spend computation"); additive `budget` block on `CostBreakdownResponse`/`ProjectCostRollupResponse` ("API shape") |
| BUDG-03 | Alerts at 80%/100% via dashboard + FCM, finance-gated | Fired-threshold columns + atomic claim ("Threshold state"); `dashboard_alerts_alert_type_check` migration + `FINANCIAL_ALERT_TYPES` registration ("Surface 3"); finance.view holder FCM targeting ("Surface 4"); APScheduler sweep ("Surface 5") |
| BUDG-04 | Approving a quote revision adjusts the linked budget by the revision delta | `approve_quote` hook + `revise_quote` fixes + `revised_from_quote_id` chain link + `margin_math.pre_tax_total` delta ("Surface 2") |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **OOP architecture required:** new models inherit `TenantScopedModel`; services inherit `TenantScopedService`; repositories inherit `TenantScopedRepository`; response schemas inherit `BaseResponseSchema`; no standalone service functions.
- **N+1 rule:** never query in a loop; `lazy="raise"` relationships; `selectinload`/`joinedload` for eager loads; column-only aggregates preferred.
- **No `db.commit()` in services** — `get_db` owns the transaction; use `db.flush()` for generated IDs. (Cron sessions are the exception: `scheduler.py` commits explicitly because it creates its own sessions.)
- **Flutter:** no bare `as` casts on API data; `FormatException` on shape mismatch; tolerant of ADDED optional keys, strict on existing ones; Riverpod `AsyncNotifier` for async build.
- **Clean code:** ~20-line functions, named constants (no magic `0.80`), DRY, 0–3 args.
- **Testing:** every new service function/endpoint gets tests before merging; phase E2E required (`backend/tests/test_phase_34_e2e.py`, `mobile/test/e2e/phase_34_*_e2e_test.dart`, Playwright in `web/tests/`); run `ruff check`/`ruff format`, `dart analyze`, `npm run lint` + `npx tsc --noEmit`, `pytest`, `flutter test` before commit; `docker compose up migrate` after new Alembic migrations.
- Pre-commit hooks installed and must pass; `RUF006` (unassigned `asyncio.create_task`) is already ignored in `backend/pyproject.toml` — fire-and-forget is sanctioned.

## Summary

Everything Phase 34 needs already exists in the codebase as a shipped, verified building block — this phase is wiring, not invention. The `Budget` model and `BudgetCreate` schema shipped dormant in Phase 30; the "spent" figure is exactly Phase 33's breakdown/rollup math; the alert pipeline (DashboardAlert + permission-aware filter + FCM service + APScheduler) shipped in Phases 24/26/30. The one genuinely new design element — threshold-crossing state — is best stored as two nullable timestamp columns on `budgets` claimed with an atomic `UPDATE ... WHERE fired_at IS NULL RETURNING id` (the Phase 25 `mark_invoiced` double-billing pattern), which gives exactly-once firing under the mutation-eval-vs-cron race for free.

Two critical code findings change the plan for BUDG-04. First, **`revise_quote` currently drops `trade_scope_id` and `project_id`** when creating the new revision row (`quotes/service.py:432-446` copies only `job_id`) — a scope-quote revision becomes an orphan, so D-06's linkage cannot work until this is fixed. Second, **`revise_quote` does not allow revising an `approved` quote** (`quotes/service.py:419` allows only sent/viewed/declined/expired), which means under current rules a chain can never contain two approved revisions — BUDG-04's delta case is unreachable until `approved` is added to the revisable set. Additionally there is no chain link between revisions; the recommendation is to add `quotes.revised_from_quote_id` in the same migration so the "previous approved quote" lookup is exact rather than heuristic.

One scope clarification from code inspection: the dashboard-alert UI exists **on web only** (monitoring page `AlertPanel`). Mobile has no alert list surface — mobile's delivery channel for BUDG-03 is the FCM push. The budget-vs-actual *view* (BUDG-02) ships on both platforms per D-13, embedded additively in the existing breakdown/rollup responses.

**Primary recommendation:** Build a `BudgetService` in `app/features/finance/` that reuses the shipped repository queries for spend, stores fired-threshold timestamps on `budgets`, hooks `FinanceService` cost mutations + `QuoteService.approve_quote` + a new nightly `_run_for_all_companies` cron job, and delivers via new `budget_warning`/`budget_overrun` alert types registered in `FINANCIAL_ALERT_TYPES` plus a finance.view-targeted FCM method — with migration 0035 carrying the constraint change, the two budget columns, and the quote chain-link column.

## Standard Stack

No new libraries. Every dependency is already installed and in production use:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SQLAlchemy async + asyncpg | shipped | Budget CRUD, atomic threshold claims | Whole backend |
| APScheduler (`AsyncIOScheduler`) | shipped | Nightly budget sweep | Phase 26 cron pattern, `app/core/scheduler.py` |
| firebase-admin | shipped | FCM push to finance.view holders | Phase 24 `NotificationService` |
| Alembic | shipped | Migration 0035 | `backend/migrations/versions/` (latest = `0034_cost_receipts.py`) |
| TanStack Query + base-ui dialogs (web) | shipped | Budget hooks + Set-budget dialog | Phase 31/32 finance hooks/dialogs |
| Riverpod 3 + Dio (mobile) | shipped | Budget-vs-actual fetch (no Drift persistence, D-13) | Phase 32-05 online-only breakdown pattern |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Fired-at columns on `budgets` | Separate `budget_threshold_events` table | Table needs a "generation" counter to express re-arm; columns express re-arm as `SET NULL` — simpler, sufficient for exactly 2 static thresholds (D-11 forbids category thresholds) |
| `UPDATE ... WHERE fired_at IS NULL RETURNING` claim | `SELECT ... FOR UPDATE` on budget row | FOR UPDATE holds a row lock across the alert-build work; the claim-first pattern is lock-free and already proven in Phase 25 `mark_invoiced` |
| Additive `budget` block in breakdown responses | Dedicated `GET /budgets?anchor=` read endpoints | Separate reads add a round trip per surface and a second "spent" code path; embedding reuses the exact figures the Costs section already renders (consistency requirement in Claude's-discretion notes) |

**Installation:** none — `npm view` checks unnecessary; no new packages.

## Architecture Patterns

### Recommended code layout (backend)

```
backend/app/features/finance/
├── models.py            # + warning_fired_at / overrun_fired_at on Budget
├── schemas.py           # + BudgetUpdate, BudgetResponse, BudgetVsActual
├── budget_service.py    # NEW: BudgetService (CRUD + evaluation + alert emission)
├── budget_repository.py # NEW (or extend repository.py): BudgetRepository (claims, spends)
├── service.py           # FinanceService cost mutations call BudgetService.evaluate_for_*
├── router.py            # + POST/PATCH/DELETE /budgets endpoints
backend/app/features/quotes/service.py   # approve_quote hook + revise_quote fixes
backend/app/features/dashboard/service.py # FINANCIAL_ALERT_TYPES populated
backend/app/features/notifications/service.py # + send_budget_alert_notification
backend/app/core/scheduler.py            # + run_budget_sweep job
backend/migrations/versions/0035_budget_alerts_and_quote_chain.py
```

Import-cycle check (verified): `quotes/service.py → finance/budget_service.py → finance/repository.py → quotes/models.py` is acyclic — `quotes/models.py` imports nothing from `quotes/service.py`. Safe.

---

### Surface 1 — Finance: Budget model, spend reuse, response extension

**What already ships (verified):**
- `Budget` model: `backend/app/features/finance/models.py:151-182` — `project_id` XOR `trade_scope_id` (ASYMMETRY: project, not job), `total NUMERIC(10,2)`, TenantScopedModel (soft-delete via `deleted_at`), `breakdowns` relationship (dormant per D-11).
- `BudgetCreate` schema: `finance/schemas.py:196-218` — XOR validator + breakdown-sum guard already written. Phase 34 adds `BudgetUpdate` (total only) and response schemas.
- No budget repository/service/router exists — router header (`finance/router.py:8-19`) lists only cost/labor endpoints. All budget CRUD is net-new.
- Permission gating pattern: `await require_permission("finance.manage")(current_user, db)` called inline inside endpoint bodies (`finance/router.py:72,118,133`), `finance.view` for reads (`:86,104`).

**Spend computation reuse (Claude's discretion — recommendation):**

- **Scope budget spend** = the scope Costs section's `grand_total` = sum of all non-deleted cost entries at the scope (all categories; labor excluded honestly since labor is job-anchored — `trade_scope_cost_breakdown` at `finance/service.py:444-456` passes `labor=None`). For evaluation this reduces to one aggregate: `SELECT SUM(amount) FROM cost_entries WHERE trade_scope_id = :id AND deleted_at IS NULL`. For the sweep, ONE grouped query serves all scope budgets: `... WHERE trade_scope_id IN (:ids) GROUP BY trade_scope_id` (mirrors `_category_totals_where`, `finance/repository.py:108-120`). This is exactly consistent with the displayed scope spend — the consistency requirement is satisfied by construction.
- **Project budget spend** = the project rollup's `grand_total` = dual-outerjoin cost entries + derived labor with legacy-labor folding. Reuse the existing pieces, skipping the margin legs (they cost 2–3 extra revenue queries the evaluation doesn't need): `repository.rollup_for_project(project_id)` + `repository.completed_work_sessions_for_project(project_id)` + `FinanceService._rates_by_contractor(sessions)` + `summarize_labor` + `_build_breakdown(...).grand_total` (`finance/service.py:316-343` shows the exact sequence). Recommend extracting a `project_spend(project_id) -> Decimal` method on `FinanceService` (or a shared helper) that `rollup_for_project` and `BudgetService` both call, so no third spend definition ever exists.
- Sweep looping: scope spends in one grouped query; project spends loop over the (bounded) set of projects that have budgets, each iteration being the same 3-query bounded op the rollup endpoint already performs. This mirrors `detect_schedule_slips`' per-project iteration and should carry a comment citing the precedent (CLAUDE.md N+1 rule is about per-row queries, not bounded per-entity service calls — but the plan should state this explicitly).

**Response extension (additive-only, mobile strict/tolerant contract):**

`CostBreakdownResponse` (`finance/schemas.py:145-161`) and `ProjectCostRollupResponse` (`:164-181`) each already grew additively in Phases 32/33 (`categories`, `labor`, `margin` — all optional with defaults). Add:

```python
class BudgetVsActual(BaseModel):
    """Budgeted vs spent vs remaining for one project or trade-scope budget."""
    budget_id: uuid.UUID
    total: Decimal
    spent: Decimal
    remaining: Decimal   # total - spent; negative when over budget (honest, D-10)

# on both response models, additive:
budget: BudgetVsActual | None = None   # None = no budget set (drives "Set budget" empty state)
```

`budget_id` must be present — the web Set-budget dialog needs it for PATCH/DELETE without a second lookup endpoint. `spent` in the scope response MUST be the same figure as that response's `grand_total` (assert in tests). Decimals auto-serialize as JSON strings (established).

**Cost-mutation hooks (D-02):** `FinanceService.create_cost_entry` (`service.py:288`), `update_cost_entry` (`:458`), `delete_cost_entry` (`:468`). After the flush, evaluate the affected budget(s): a scope-anchored entry affects the scope budget AND the scope's project budget (`trade_scopes.project_id`, verified NOT NULL at `projects/models.py:134`); a job-anchored entry affects the project budget via `jobs.project_id` (nullable — no project, no-op). At most 2 budget evaluations per mutation, same transaction. Note `update_cost_entry` keeps the anchor immutable (Phase 31 decision), so "before" and "after" budgets are the same set.

---

### Surface 2 — Quotes: approval hook, revision chain, delta math

**Hook point:** `QuoteService.approve_quote`, `quotes/service.py:271-308`. After `quote.status = "approved"; quote.approved_at = ...; await self.db.flush()` (lines 295-297) and the job/project branches, apply the budget delta **in the same session** — `get_db` commits the whole request atomically, so budget adjustment + status change + threshold evaluation commit or roll back together. No extra transaction machinery needed.

**CRITICAL FINDING 1 — `revise_quote` drops anchors (must fix for D-06):**
`quotes/service.py:432-446` constructs the new revision with `job_id=old_quote.job_id` only. `trade_scope_id` and `project_id` are NOT copied. A revised scope quote (Phase 25 `create_for_scope` sets `job_id=None, trade_scope_id=X`) therefore produces a revision with BOTH anchors null — an orphan that (a) breaks D-06 linkage, and (b) already silently breaks Phase 33's revenue leg for revised scope quotes (the approved revision no longer matches `_anchor_filter`). Phase 34 must fix `revise_quote` to carry `trade_scope_id=old_quote.trade_scope_id` and `project_id=old_quote.project_id`. This is a pre-existing bug fix, not a behavior change.

**CRITICAL FINDING 2 — approved quotes are not revisable (must extend for BUDG-04):**
`quotes/service.py:419`: `self._require_quote_status(old_quote, {"sent", "viewed", "declined", "expired"}, "revise")`. Under these rules an approved quote can never be superseded, so no chain can ever contain a *second* approved revision — D-09's delta case is unreachable. Phase 34 must add `"approved"` to the revisable set. Margin consistency is automatic: the old row flips to `status='revised'` and drops out of the `Quote.status == 'approved'` revenue leg (`finance/repository.py:343`), and the newly approved revision takes over — no double count. The DB `quotes_status_check` constraint (`quotes/models.py:87-91`) already permits the `revised` value; no constraint change needed for this.

**Previous-approved-quote lookup — recommendation: add an explicit chain link.**
There is no parent pointer between revisions today; chain membership is only implied by shared anchor + `revision_number`. A heuristic lookup (same anchor, `status='revised'`, `approved_at IS NOT NULL`, `revision_number = new - 1`) is ambiguous when two independent chains exist at one anchor (`list_by_scope` confirms multiple quotes per scope is normal). Recommend migration 0035 adds `quotes.revised_from_quote_id UUID NULL REFERENCES quotes(id)`, set by `revise_quote`. Then at approval time: walk `revised_from_quote_id` back until a row with `approved_at IS NOT NULL` is found → that row's pre-tax total is the baseline; if the walk ends with none found → this is the chain's first approval → establish baseline, apply NO delta (D-09). The walk is bounded by chain length (single-digit); implement as a simple loop with a per-step indexed lookup or a recursive CTE — either is acceptable at this scale (document the choice).

**Delta math (D-07):** For each of the two quotes, pre-tax total = `pre_tax_total(DocumentAmounts(subtotal, discount_type, discount_value, tax_rate))` from `finance/margin_math.py:103-105` — the single source of the discount math, bit-for-bit the shipped schema math (Phase 33 D-13 basis). Subtotal = `sum(item.quantity * item.unit_price)` over the quote's line items (both quotes load via `get_with_line_items`; the old quote's line items are intact — `_replace_line_items` only touches drafts). Quantize to cents like `_quoted_revenue` (`finance/service.py:105-107`). `delta = new_total - previous_total` (signed `Decimal`). Apply: `budget.total = budget.total + delta` (floor at nothing — D-10 says no floor; a negative-going budget below spend just fires honest alerts on next evaluation). If `delta > 0` → re-arm (D-03). After applying, evaluate that budget's thresholds in the same transaction.

**Linkage resolution (D-06):** `quote.trade_scope_id` set → scope budget for that scope. `quote.job_id` set → `Job.project_id` (nullable) → project budget. Neither set (project-level quote) → `quote.project_id` → project budget. `quote.project_id` is populated at first approval by `_convert_project_quote` (`service.py:341`), so a revision of a project-level quote carries it once Finding 1 is fixed. D-08: budget lookup returns None → no-op, approval proceeds.

---

### Surface 3 — Dashboard: alert types, constraint migration, permission filter

**Verified locations:**
- `DashboardAlert` model: `dashboard/models.py:22-80`. `alert_type` CHECK constraint `dashboard_alerts_alert_type_check` at lines 64-67 currently allows only `schedule_slip | rescheduling_suggestion | dependency_risk` → **migration required** (D-05). `project_id` is **NOT NULL** — scope-budget alerts must set `project_id = scope.project_id` plus `trade_scope_id`; project-budget alerts set `project_id` with `trade_scope_id=None`. `impact_text` NOT NULL — the alert copy lives here. `severity` constrained to `info|warning|critical`.
- `FINANCIAL_ALERT_TYPES`: `dashboard/service.py:60` — `frozenset()` today. Populate with the new types; the filter in `get_alerts` (`service.py:734-753`) then hides them from non-finance callers with zero new filter code. The router computes `has_finance_view` via `effective_permissions` (`dashboard/router.py:96-99`).
- **Gotcha:** `tests/unit/test_finance_scrub.py:48-51` asserts `FINANCIAL_ALERT_TYPES == frozenset()` ("inert today" contract, comment says Phase 36 updates it — Phase 34 gets there first). This test MUST be updated in the same plan that populates the set, or CI fails.
- Read/dismiss endpoints ship: `POST /dashboard/alerts/{id}/read|accept|dismiss` (`dashboard/router.py:103-135`); `AlertRepository.mark_read/dismiss_alert` (`repository.py:74-84`). Budget alerts need only `read`/`dismiss` (no rescheduling payload).
- Web alert surface: `web/src/app/(dashboard)/monitoring/_components/AlertPanel.tsx` — renders by `severity` config (info/warning/critical icons); only `rescheduling_suggestion` is special-cased. New budget types render through the existing severity path; optionally add a small type label/icon.
- **Mobile has NO dashboard-alert surface** (verified by exhaustive grep — no alerts list/screen exists in `mobile/lib`). BUDG-03's mobile channel is the FCM push; do not plan a mobile alert-list feature (that would be new scope, not an extension).

**Recommended alert_type names:** `budget_warning` (80%, severity `warning`) and `budget_overrun` (100%, severity `critical`). Two distinct types (not one type with a threshold field) so the CHECK constraint, `FINANCIAL_ALERT_TYPES`, and dashboard filtering/rendering stay declarative.

**Alert copy (UI-SPEC pass will lock exact strings; per CONTEXT specifics):**
- Warning: `"{Project} — {Trade} scope has spent $8,200 of its $10,000 budget (82%)"` / project variant `"{Project} has spent $X of its $Y budget (NN%)"`.
- Overrun: same shape with "exceeded"/over-budget phrasing. Entity names require fetching `project.name` (+ `trade_scope.trade_name` for scope budgets) during evaluation — one extra bounded lookup per fired alert only.

**DashboardAlert row for budget alerts:** `alert_type=budget_warning|budget_overrun`, `severity=warning|critical`, `impact_text=<copy>`, `days_behind=None`, `remediation_text=None`, `affected_scope_ids=[]`, `rescheduling_payload=None`. Persist via `self.db.add(...)` + flush like `_persist_alerts` (`dashboard/service.py:494-527`).

---

### Surface 4 — Notifications: FCM targeting finance.view holders

**Verified plumbing (`notifications/service.py`):**
- Tokens are per-user rows (`DeviceToken`); `repository.get_tokens_for_user(user_id)`; `_dispatch_to_tokens` sends per token via a thread-pool executor; `UnregisteredError` auto-cleans stale tokens; everything degrades gracefully when `GOOGLE_APPLICATION_CREDENTIALS` is unset (`_resolve_messaging`, lines 394-410). New method `send_budget_alert_notification` should copy the `send_task_rejection_notification` shape (lines 261-308: outer try/except, never raises).
- **Selecting finance.view holders — no helper exists; build one.** Two verified ingredients: (1) `effective_permissions` (`core/security.py:212-226`) shows the resolution rule — `RbacRepository(db).get_map()` for stored rows, falling back to `DEFAULT_ROLE_PERMISSIONS` per role, expanded via `expand()` (handles the owner `*` wildcard). Compute `finance_roles = {role for role in all roles if "finance.view" in expand(role_keys)}`. (2) The user-by-role query pattern in `queue_task_completion_digest` (`notifications/service.py:164-177`): `select(User).join(UserRole, UserRole.user_id == User.id).where(UserRole.role.in_(finance_roles), User.company_id == company_id, User.deleted_at.is_(None))`. Note `RbacRepository.get_map()` is RLS-scoped — in cron context `set_current_tenant_id(company.id)` is already called by `_run_for_all_companies` before the service runs.
- **Fire pattern:** request context (cost-mutation / quote-approval evaluation) → `asyncio.create_task(...)` per the inspection precedent (`inspection/service.py:105-116`); prefer the checklist variant (`checklists/service.py:185-204`) that passes only primitives and opens its own session inside the task, because the request session closes when the response returns — a create_task holding the request's session is a use-after-close risk. **Cron context** (nightly sweep) → just `await` the notification method directly; it never raises and the scheduler session is alive for the whole job.

**FCM payload recommendation:** `title="Budget warning"|"Budget exceeded"`, `body=<same copy as impact_text>`, `data={"type": "budget_alert", "alert_type": ..., "alert_id": ..., "project_id": ..., "trade_scope_id": <or "">}` — data values must all be strings (FCM constraint, existing senders comply). Deep-link: mobile has no alert surface, so tap behavior can be default-open (or navigate to the project screen if trivially wired); keep the payload shaped for a future alert screen. LOW effort, planner's choice.

---

### Surface 5 — APScheduler: nightly sweep

**Verified pattern (`app/core/scheduler.py`):** jobs register in `lifespan` via `scheduler.add_job(fn, CronTrigger(hour=H, minute=0), id=..., replace_existing=True, misfire_grace_time=...)`. The `_run_for_all_companies(job_name, service_class, method_name, target_date)` helper (lines 39-88) iterates active companies with bounded concurrency, opens a session per company, calls `set_current_tenant_id(company.id)`, invokes `getattr(svc, method_name)(company_id=company.id, target_date=target_date)`, and commits/rolls back explicitly. **The sweep method must therefore be a method on a service class with exactly that keyword signature** — e.g. `BudgetService.sweep_budgets(company_id, target_date) -> int`.

Recommended job: `run_budget_sweep` at a fixed overnight hour (e.g. 05:00 UTC, before the 06:00 checklists; any pre-workday hour is fine — planner's choice), `misfire_grace_time=3600`. Idempotency comes free from the persistent fired-threshold state: re-running the sweep re-evaluates and the atomic claim prevents duplicate alerts — no extra idempotency machinery (unlike the checklist upsert pattern, none is needed here).

---

### Threshold-crossing state (Claude's discretion — recommendation)

**Store on `budgets` as two nullable timestamps:**

```sql
ALTER TABLE budgets
  ADD COLUMN warning_fired_at TIMESTAMPTZ,
  ADD COLUMN overrun_fired_at TIMESTAMPTZ;
```

- **Fire rule:** with `spent` and `total` as Decimals, `warning` fires when `spent >= total * Decimal("0.80")` and `warning_fired_at IS NULL`; `overrun` fires when `spent >= total` and `overrun_fired_at IS NULL`. A jump from 0% to 120% fires BOTH (each once). Constants named (`WARNING_THRESHOLD = Decimal("0.80")` etc. — CLAUDE.md no-magic-numbers).
- **Exactly-once under the mutation-vs-cron race (research focus #5):** claim before creating the alert with a raw atomic update — the shipped Phase 25 `mark_invoiced` precedent (STATE.md): `UPDATE budgets SET warning_fired_at = now() WHERE id = :id AND warning_fired_at IS NULL AND deleted_at IS NULL RETURNING id`. Zero rows returned → another evaluator (concurrent request or the cron) already claimed it → skip alert creation. This is the uniqueness guarantee; no unique index or advisory lock needed. The claim and the `DashboardAlert` insert are in one transaction, so a crash between them rolls back the claim.
- **Re-arm (D-03):** on any `total` increase (manual PATCH with `new > old`, or positive quote-revision delta), set both columns to NULL in the same UPDATE that changes `total`. Decreases do NOT reset (a decrease below spend leaves previously-fired thresholds fired for the old total but likely unfired... note: after a decrease the *unfired* thresholds of the new smaller total fire on next evaluation — e.g. overrun fires if it hadn't; already-fired ones stay deduped, which matches D-01/D-10 honest semantics).
- **Soft-deleted budgets stop evaluating** (D-10): every evaluation/sweep query filters `deleted_at IS NULL` (BaseRepository does NOT do this automatically — Phase 31 pitfall, `finance/repository.py:10-13` documents it).

### Migration 0035 (numbering verified: latest is `0034_cost_receipts.py`)

One migration, e.g. `0035_budget_alerts_and_quote_chain.py`:
1. `ALTER TABLE dashboard_alerts DROP CONSTRAINT dashboard_alerts_alert_type_check` + re-ADD with `('schedule_slip','rescheduling_suggestion','dependency_risk','budget_warning','budget_overrun')`. (DDL runs as the migration role; FORCE RLS on `dashboard_alerts` — Phase 26 — does not affect DDL.)
2. `ALTER TABLE budgets ADD COLUMN warning_fired_at TIMESTAMPTZ, ADD COLUMN overrun_fired_at TIMESTAMPTZ`.
3. `ALTER TABLE quotes ADD COLUMN revised_from_quote_id UUID REFERENCES quotes(id)` (nullable; no backfill possible or needed — pre-existing chains have no approvals-after-approvals anyway given Finding 2).
No RLS/policy changes; existing tenant policies cover new columns. Run `docker compose up migrate` after (CLAUDE.md).

### API shape (Claude's discretion — recommendation)

| Endpoint | Gate | Notes |
|----------|------|-------|
| `POST /budgets/` | finance.manage | `BudgetCreate` (shipped schema); reject duplicate active budget per anchor (409) — one budget per project/scope is the implied model |
| `PATCH /budgets/{id}` | finance.manage | `BudgetUpdate{total: Decimal>0}`; re-arm if increased; evaluate after change (D-10 below-spend fires immediately "on next evaluation" — evaluating inline on edit is the honest reading) |
| `DELETE /budgets/{id}` | finance.manage | soft-delete (`deleted_at`), stops evaluating |
| budget-vs-actual reads | finance.view | embedded `budget` block in existing `GET /trade-scopes/{id}/cost-breakdown` and `GET /projects/{id}/cost-entries` (rollup) responses — no new read endpoints |

Job cost-breakdown gets NO budget block (budgets anchor project/scope only — the Phase 30 asymmetry).

### UI composition (research focus #6 — states for the UI-SPEC pass)

**Web (edit + view):**
- `ProjectCostsCard` (project page) and the scope Costs section in `TradeScopeDetail.tsx` gain a budget group after the Total row: rows for `Budget`, `Spent`, `Remaining` (Remaining negative → red + over-budget chip; reuse `FinanceFlagChip` amber for warning-range if desired — UI-SPEC decides). Follow `CostBreakdownSummary.tsx` row rhythm (its private `BreakdownRow`, lines 123-130).
- "Set budget" inline action (shown when `budget == null`, `finance.manage` holders only) and an "Edit" affordance when present → `SetBudgetDialog` modeled on Phase 32's `RateHistoryDialog` precedent: form reset via `onOpenChange` wrapper, NOT `useEffect` (react-hooks/set-state-in-effect fails `--max-warnings 0` — Phase 32-03 lesson). Delete inside the dialog.
- New hooks in `web/src/features/finance/hooks.ts`: `useSetBudget`/`useUpdateBudget`/`useDeleteBudget` invalidating the breakdown/rollup query keys (pattern: `invalidateAllCostEntries`, `hooks.ts:92`).
- Permission source: `usePermissions` — Playwright must log in through the UI then SPA-navigate (Phase 32-04: direct `page.goto` leaves permissions disabled and finance cards never render).
- States to enumerate for UI-SPEC: no budget + no permission (nothing), no budget + manage (Set budget), budget under 80%, 80–100% (warning styling), over 100% (overrun styling), loading (`—` amounts, established), error (breakdown error line, established).

**Mobile (view only, D-13):**
- Extend `cost_breakdown_summary.dart` / project rollup section with budget rows using the shared `BreakdownRow`/`BreakdownCaption` primitives (`breakdown_row_widgets.dart`) and `FinanceFlagChip` for over-budget. Data flows through `finance_repository.dart` + `cost_providers.dart` (`_projectRollupFetchProvider` shares one network call — Phase 32-05); parse the new `budget` key tolerantly (absent = older backend = render nothing), keep existing keys strict. No Drift, no editing (captions may note "Set on web" — UI-SPEC decides).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| "Spent" figure | Any new SUM/traversal | `rollup_for_project` pieces + `category_totals`/scope SUM (Surface 1) | CONTEXT hard rule: no third spend definition; folding/soft-delete/traversal subtleties already solved |
| Pre-tax quote total | Re-implementing discount math | `margin_math.pre_tax_total` | Bit-for-bit shipped schema math (Phase 33 D-13); banker's-rounding quantize already correct |
| Exactly-once firing | Locks, advisory locks, unique-violation catching | `UPDATE ... WHERE fired_at IS NULL RETURNING id` | Phase 25 `mark_invoiced` proven pattern; lock-free |
| Finance-gated alert visibility | Per-endpoint filtering | Populate `FINANCIAL_ALERT_TYPES` | Phase 30 D-11 filter ships and is tested; registration is the whole integration |
| Multi-company cron iteration | Custom company loop | `_run_for_all_companies` | Tenant context, error isolation, concurrency, commit handling all done |
| FCM dispatch/token hygiene | New sender | `NotificationService._dispatch_to_tokens` + a new `send_budget_alert_notification` | Stale-token cleanup, thread-pool, graceful no-credential skip all done |
| Permission resolution | Role-name checks (e.g. `role in ("owner","project_manager")`) | `expand()` + `RbacRepository.get_map()` with `DEFAULT_ROLE_PERMISSIONS` fallback | Companies edit the matrix (FINSEC-02); role-name checks would leak/miss custom grants |

**Key insight:** the phase's risk is not algorithmic complexity — it's consistency drift (a second spend definition, a second discount math, a second permission rule). Every one of those already has a single source of truth to call.

## Common Pitfalls

### Pitfall 1: revise_quote anchor loss ships unfixed
**What goes wrong:** BUDG-04 tests pass for job quotes but scope-quote revisions silently adjust nothing (orphan anchors), and revised scope quotes vanish from margin revenue.
**Why:** `quotes/service.py:432-446` copies only `job_id`.
**Avoid:** Fix in the same plan that adds the approval hook; add a regression test that a revised scope quote keeps `trade_scope_id` (and a project-level revision keeps `project_id`).
**Warning sign:** any budget-delta test that only covers job-anchored quotes.

### Pitfall 2: BUDG-04 unreachable because approved quotes can't be revised
**What goes wrong:** the delta path is dead code — no chain can contain two approvals.
**Avoid:** add `"approved"` to `revise_quote`'s allowed statuses (line 419) with tests covering approved→revised→(send/view)→approved delta application, and verify revenue hand-off (old approved drops out of the quoted leg).

### Pitfall 3: Request-scoped session inside `asyncio.create_task`
**What goes wrong:** FCM task runs after the request session closed → intermittent `InterfaceError`/silent failures.
**Avoid:** pass primitives into the task and open a fresh session inside (checklists `_dispatch_notifications` pattern, `checklists/service.py:185-204`), or gather targets before scheduling and pass token/user IDs only.

### Pitfall 4: `FINANCIAL_ALERT_TYPES` unit test breaks CI
**What goes wrong:** `tests/unit/test_finance_scrub.py:51` pins the set to empty.
**Avoid:** update that test in the same commit that populates the set; also re-point `test_phase_30_e2e.py`'s monkeypatch-based leak test at the real types (it currently uses `dependency_risk` as a stand-in — documented at STATE.md Phase 30-04).

### Pitfall 5: Evaluating with a stale spend inside the mutation transaction
**What goes wrong:** evaluation queries run before the new cost entry is flushed → threshold check uses pre-mutation spend and misses a crossing until the nightly sweep.
**Avoid:** hook AFTER `flush()` (all three mutation methods already flush); evaluation queries in the same session then see the pending row.

### Pitfall 6: Scope spend definition drifts from the scope Costs display
**What goes wrong:** evaluation uses one SUM, the breakdown shows another (e.g. legacy labor-category folding differences) → "82% spent" alert while the screen shows a different total; users lose trust.
**Avoid:** scope spend = scope breakdown `grand_total` by construction (all categories, no derived labor); add a test asserting the embedded `budget.spent == grand_total` on the scope breakdown response.

### Pitfall 7: Alert noise / permission leak (research PITFALLS.md #8)
**What goes wrong:** repeated alerts or pushes to non-finance devices.
**Avoid:** D-01 dedup (atomic claim), D-05 registration in `FINANCIAL_ALERT_TYPES`, FCM recipients derived from the live RBAC matrix only. Keystone test three (CONTEXT): non-finance role sees no budget alerts and gets no push.

### Pitfall 8: Numeric drift in threshold comparison
**What goes wrong:** float math (`spent/total >= 0.8`) misfires at boundaries.
**Avoid:** pure `Decimal` comparison (`spent >= total * Decimal("0.80")`); alert copy percent formatted like `margin_percent_for` (quantize, ROUND_HALF_UP) — never `float`.

## Code Examples

### Atomic threshold claim (Phase 25 pattern applied to budgets)
```python
# Source: backend precedent — invoices mark_invoiced (STATE.md Phase 25);
# raw SQL UPDATE ... RETURNING for race-free exactly-once claims.
_CLAIM_WARNING = text("""
    UPDATE budgets SET warning_fired_at = now()
    WHERE id = :budget_id AND warning_fired_at IS NULL AND deleted_at IS NULL
    RETURNING id
""")
result = await self.db.execute(_CLAIM_WARNING, {"budget_id": budget_id})
if result.scalar_one_or_none() is None:
    return  # another evaluator already fired this threshold
```

### Nightly sweep registration
```python
# Source: backend/app/core/scheduler.py:131-145 (existing job registration shape)
scheduler.add_job(
    run_budget_sweep,
    trigger=CronTrigger(hour=BUDGET_SWEEP_HOUR_UTC, minute=0),
    id="budget_sweep",
    replace_existing=True,
    misfire_grace_time=BUDGET_SWEEP_MISFIRE_GRACE_SECONDS,
)
# run_budget_sweep delegates to _run_for_all_companies(
#     "run_budget_sweep", BudgetService, "sweep_budgets", today)
# → BudgetService.sweep_budgets(company_id=..., target_date=...) signature is REQUIRED.
```

### Finance.view holder selection (composed from two verified shipped pieces)
```python
# Sources: app/core/security.py:212-226 (resolution rule),
#          app/features/notifications/service.py:164-177 (user-by-role query)
role_map = await RbacRepository(db).get_map()          # RLS-scoped to current tenant
finance_roles = [
    role for role in set(DEFAULT_ROLE_PERMISSIONS) | set(role_map)
    if "finance.view" in expand(role_map.get(role, DEFAULT_ROLE_PERMISSIONS.get(role, [])))
]
stmt = (
    select(User.id).join(UserRole, UserRole.user_id == User.id)
    .where(UserRole.role.in_(finance_roles),
           User.company_id == company_id, User.deleted_at.is_(None))
)
```

### Quote delta (single sources only)
```python
# Source: app/features/finance/margin_math.py:103-105; service.py:105-107 (_quoted_revenue)
def _pre_tax_quote_total(quote: Quote) -> Decimal:
    subtotal = sum((i.quantity * i.unit_price for i in quote.line_items), ZERO_MONEY)
    amounts = DocumentAmounts(subtotal=subtotal, discount_type=quote.discount_type,
                              discount_value=quote.discount_value, tax_rate=quote.tax_rate)
    return pre_tax_total(amounts).quantize(CENTS)

delta = _pre_tax_quote_total(new_quote) - _pre_tax_quote_total(previous_approved)  # signed
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `FINANCIAL_ALERT_TYPES` empty (inert filter) | Populated with `budget_warning`/`budget_overrun` | This phase | Filter + FCM gating become live; two tests must update |
| `revise_quote` copies `job_id` only | Carries all three anchors + `revised_from_quote_id` | This phase (bug fix) | D-06 linkage + Phase 33 revenue correctness for revised scope quotes |
| Revise allowed from sent/viewed/declined/expired | + approved | This phase | Makes BUDG-04 reachable |
| Budget schema dormant (Phase 30 D-09) | CRUD + evaluation live (total-only) | This phase | `BudgetCategoryBreakdown` stays dormant (D-11) |

**Deprecated/outdated:** nothing external; no library-version concerns (no new packages).

## Open Questions

1. **Exact sweep hour** — any pre-workday UTC hour works; 05:00 UTC recommended (before 06:00 checklists so budget alerts exist when owners open the app). Planner picks; LOW stakes.
2. **One-budget-per-anchor enforcement** — schema has no unique partial index on active budgets. Recommend service-level 409 on duplicate active anchor (matching how category-name conflicts are handled at service level); a partial unique index (`WHERE deleted_at IS NULL`) is optional hardening the planner may add to migration 0035. Either satisfies the phase.
3. **Chain-walk implementation** — loop of indexed lookups vs recursive CTE for `revised_from_quote_id`. Chains are single-digit; the simple loop is fine (document why the CLAUDE.md no-loop-queries rule doesn't bite: bounded by chain length, not row count). Planner's choice.
4. **Mobile FCM tap behavior** — no alert surface exists on mobile; default notification-open is acceptable for this phase. Flag in UI-SPEC.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Docker (Postgres + migrate) | migration 0035, backend tests | ✓ | 20.10.21 | — |
| pytest | backend tests | ✓ | 8.3.4 | — |
| Flutter | mobile tests | ✓ | 3.41.4 | — |
| npm / Node | web lint/test/Playwright | ✓ | npm 10.8.2 | — |
| Firebase credentials (`GOOGLE_APPLICATION_CREDENTIALS`) | live FCM only | env-dependent | — | Shipped graceful skip in `NotificationService`; tests mock — not blocking |

**Missing dependencies with no fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Backend | pytest 8.3.4, `asyncio_mode=auto`, `testpaths=["tests"]` (`backend/pyproject.toml`); ASGI client + JWT-bearer fixtures in `conftest.py` |
| Web unit | Jest (`npm run test`, `web/jest.config.ts`) |
| Web E2E | Playwright (`npm run test-e2e`), `testDir: ./tests` → `web/tests/phase-34-*.spec.ts` (precedent: `phase-33-margin.spec.ts`) |
| Mobile | `flutter test`; E2E in `mobile/test/e2e/phase_34_*_e2e_test.dart` |
| Quick run | `cd backend && pytest tests/test_phase_34_e2e.py -x` |
| Full suite | `cd backend && pytest` · `cd mobile && flutter test` · `cd web && npm run lint && npx tsc --noEmit && npm run test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BUDG-01 | Budget CRUD (XOR anchor, finance.manage gate, soft-delete, 403s) | integration | `pytest tests/test_phase_34_e2e.py -k budget_crud -x` | ❌ Wave 0 |
| BUDG-02 | budget-vs-actual embedded in breakdown/rollup; `spent == grand_total` consistency | integration | `pytest tests/test_phase_34_e2e.py -k budget_vs_actual -x` | ❌ Wave 0 |
| BUDG-02 | Web/mobile budget rows render (incl. over-budget state) | unit/widget + E2E | `npm run test -- budget` · `flutter test test/e2e/phase_34_budgets_e2e_test.dart` · `npm run test-e2e -- phase-34` | ❌ Wave 0 |
| BUDG-03 | 80/100 fire exactly once; re-arm on increase; race (concurrent eval) fires once; non-finance sees nothing + no FCM (keystone tests 1 & 3) | unit + integration | `pytest tests/unit/test_budget_evaluation.py -x` · `pytest tests/test_phase_34_e2e.py -k alerts -x` | ❌ Wave 0 |
| BUDG-03 | Sweep evaluates all budgets idempotently | integration | `pytest tests/test_phase_34_e2e.py -k sweep -x` | ❌ Wave 0 |
| BUDG-04 | Signed delta on approved revision (up + down, keystone test 2); anchors carried; no-op without budget; baseline on first approval | integration | `pytest tests/test_phase_34_e2e.py -k quote_delta -x` | ❌ Wave 0 |

Manual-only: none — FCM is mocked at the messaging layer (precedent: `test_phase_24_fcm_rejection.py`); visual chip/color checks fall to the UI-SPEC/UAT pass.

**Test-fixture note (Phase 33-02 lesson):** approving quotes in fixtures via the endpoint requires draft→sent→(viewed)→approve transitions and triggers project creation for project-level quotes; Phase 33 fixtures approve via raw SQL (`SET LOCAL` + `UPDATE`). Phase 34's delta tests must exercise the REAL `approve_quote` endpoint for the hook, so drive the status machine through endpoints (send → approve), or set pre-approval status via SQL and call approve.

### Sampling Rate
- **Per task commit:** `pytest tests/test_phase_34_e2e.py -x` (plus `ruff check`, `dart analyze`/`npm run lint` for touched platforms)
- **Per wave merge:** full backend `pytest` + `flutter test` + web `lint`/`tsc`/`jest`
- **Phase gate:** all suites green + Playwright `phase-34` spec before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `backend/tests/test_phase_34_e2e.py` — BUDG-01..04 integration coverage
- [ ] `backend/tests/unit/test_budget_evaluation.py` — threshold math, dedup/claim, re-arm, delta math (pure/unit)
- [ ] Update `backend/tests/unit/test_finance_scrub.py` (empty-set pin) and `test_phase_30_e2e.py` leak test (stand-in type → real types)
- [ ] `web/tests/phase-34-budgets.spec.ts` — Set-budget dialog + budget rows + alert panel
- [ ] `web/src/features/finance/__tests__/budget-section.test.tsx` (+ SetBudgetDialog test)
- [ ] `mobile/test/e2e/phase_34_budgets_e2e_test.dart` — budget rows render from mocked Dio breakdown, tolerant parsing of absent `budget` key
- Framework install: none needed.

## Sources

### Primary (HIGH confidence — direct code reads, this session)
- `backend/app/features/finance/{models,schemas,repository,service,margin_math}.py` — Budget schema, spend queries, breakdown assembly, pre-tax math
- `backend/app/features/quotes/{service,models}.py` — approve/revise flows, status machine, anchor handling (Findings 1 & 2 verified at lines 419 and 432-446)
- `backend/app/features/dashboard/{models,service,repository,router}.py` — alert_type constraint, FINANCIAL_ALERT_TYPES, permission filter, endpoints
- `backend/app/features/notifications/service.py` — FCM dispatch, token repo, fire-and-forget precedents
- `backend/app/core/{scheduler,permissions,security}.py` — cron pattern, permission catalog/resolution
- `backend/app/features/rbac/repository.py`, `backend/migrations/versions/0032_financial_schema_and_rbac.py` — RBAC map, migration/RLS conventions; latest migration = 0034
- `web/src/features/finance/*`, `web/src/app/(dashboard)/monitoring/_components/AlertPanel.tsx`, `web/src/lib/hooks/useDashboard.ts` — web surfaces
- `mobile/lib/features/finance/*` — mobile widgets/providers; exhaustive grep confirming no mobile alert surface
- `.planning/phases/34-budgeting-and-overrun-alerts/34-CONTEXT.md`, `.planning/research/PITFALLS.md` (#8), `STATE.md` decisions log

### Secondary / Tertiary
- None needed — no external-web claims are made in this document.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; all versions in-repo
- Architecture/hook points: HIGH — every hook point read directly with line references
- Quote-machinery findings (bug + status gap): HIGH — verified in source; the *fix shape* (`revised_from_quote_id`) is a recommendation (MEDIUM) with a documented heuristic alternative
- Pitfalls: HIGH — grounded in shipped tests and STATE.md decision log

**Research date:** 2026-07-27
**Valid until:** stable (internal codebase research) — re-verify only if Phases 30–33 files change before planning
