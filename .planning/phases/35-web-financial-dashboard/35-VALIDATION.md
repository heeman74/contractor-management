---
phase: 35
slug: web-financial-dashboard
status: planned
plans: 11
per_task_map_complete: true
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-28
---

# Phase 35 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from 35-RESEARCH.md § Validation Architecture. The per-task map is
> completed by the planner (task IDs assigned at plan time).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Backend framework** | pytest + pytest-asyncio + httpx AsyncClient (real `contractorhub_test` DB); conftest forces DATABASE_URL, runs `alembic upgrade head`, `clean_tables` autouse |
| **Backend quick run** | `cd backend && source .venv/bin/activate && python -m pytest tests/test_phase_35_e2e.py -q` |
| **Backend full suite** | `cd backend && source .venv/bin/activate && python -m pytest -q` |
| **Web unit framework** | Jest 30 + ts-jest + jsdom + @testing-library/react (`jest.config.ts`) |
| **Web unit quick run** | `cd web && npx jest src/features/finance src/app/\(dashboard\)/financials` |
| **Web E2E framework** | Playwright 1.58 (chromium, `webServer: npm run dev`) |
| **Web E2E quick run** | `cd web && npx playwright test tests/phase-35-financials.spec.ts` |
| **Static gates** | `cd web && npm run lint && npx tsc --noEmit`; `cd backend && ruff check . && ruff format --check .` |
| **Estimated runtime** | ~30s per-task quick runs |

---

## Sampling Rate

- **Per task commit:** `pytest tests/test_phase_35_e2e.py -q` and/or `npx jest src/features/finance src/app/\(dashboard\)/financials` + platform linters.
- **Per wave merge:** `pytest tests/test_phase_3{3,4,5}_e2e.py -q` + `npm test` + `npm run lint && npx tsc --noEmit`.
- **Phase gate:** full backend suite, `npm test`, `npm run test-e2e`, ruff — all green before `/gsd:verify-work`.
- **Max feedback latency:** ~30 seconds (except the sanctioned phase-gate full suites).

---

## Phase Requirements → Test Map

*Plan/Task assigned by the planner 2026-07-28. Every row has an owning task.*

| Req | Behavior | Type | Automated command | Plan / Task | File exists? |
|---|---|---|---|---|---|
| MARG-04 / SC1 | Trend endpoint returns dense monthly buckets; final bucket equals `rollup_for_project`'s margin block (self-verifying reconciliation) | integration | `pytest tests/test_phase_35_e2e.py::test_trend_final_bucket_reconciles_with_project_rollup -x` | 35-07 T3 | ❌ Wave 0 |
| MARG-04 / SC1 | Same month identical across 3m/6m/12m/all windows (windows slice buckets, not records) | integration | `pytest tests/test_phase_35_e2e.py::test_trend_window_slices_buckets_not_records -x` | 35-07 T3 | ❌ Wave 0 |
| MARG-04 / SC1 | Approved quote with `approved_at IS NULL` still reconciles | integration | `pytest tests/test_phase_35_e2e.py::test_trend_quote_without_approved_at_uses_created_at -x` | 35-07 T3 | ❌ Wave 0 |
| MARG-04 / SC1 | Months with no activity carry forward cumulative values (dense buckets) | integration | `pytest tests/test_phase_35_e2e.py::test_trend_buckets_are_dense -x` | 35-07 T3 | ❌ Wave 0 |
| MARG-04 / SC1 | Pre-revenue buckets return `revenue=null`, `margin=null`, `basis="none"` | integration | `pytest tests/test_phase_35_e2e.py::test_trend_absent_revenue_is_null_not_zero -x` | 35-07 T3 | ❌ Wave 0 |
| MARG-04 / SC1 | Unknown `window` value rejected | integration | `pytest tests/test_phase_35_e2e.py::test_trend_rejects_unknown_window -x` | 35-07 T3 | ❌ Wave 0 |
| MARG-04 / SC1 | Drill-down per-scope budget-vs-actual `spent` matches `trade_scope_spend` | integration | `pytest tests/test_phase_35_e2e.py::test_project_financials_scope_budgets_match_scope_spend -x` | 35-06 T3 | ❌ Wave 0 |
| MARG-04 / SC1 | Drill-down carries aggregates only — no `entries[]` | integration | `pytest tests/test_phase_35_e2e.py::test_project_financials_returns_aggregates_without_entries -x` | 35-06 T3 | ❌ Wave 0 |
| MARG-04 / SC1 | Trend line renders gaps for null margin; no `$0` point | unit (jest) | `npx jest "src/app/(dashboard)/financials"` | 35-10 T2 | ❌ Wave 0 |
| MARG-04 / SC1 | Month bucketing, as-of replay and window slicing are correct in isolation | unit (pytest) | `pytest tests/unit/test_trend_math.py -q` | 35-01 T2 | ❌ Wave 0 |
| MARG-04 / SC2 | Company rollup per-project figures equal `rollup_for_project` (equivalence pin) | integration | `pytest tests/test_phase_35_e2e.py::test_company_rollup_matches_rollup_for_project -x` | 35-05 T3 | ❌ Wave 0 |
| MARG-04 / SC2 | Portfolio totals include flagged projects; badge count == incomplete tier size (D-09) | integration | `pytest tests/test_phase_35_e2e.py::test_portfolio_totals_include_flagged_projects_with_count -x` | 35-05 T3 | ❌ Wave 0 |
| MARG-04 / SC2 | Estimated (quote-basis) revenue share surfaced; basis `mixed` when both legs | integration | `pytest tests/test_phase_35_e2e.py::test_portfolio_surfaces_quoted_revenue_share -x` | 35-05 T3 | ❌ Wave 0 |
| MARG-04 / SC2 | Attention tiers ordered overrun(worst % first) → warning → incomplete (D-08) | integration | `pytest tests/test_phase_35_e2e.py::test_attention_list_tier_ordering -x` | 35-05 T3 | ❌ Wave 0 |
| MARG-04 / SC2 | Overrun tier survives a budget raise that nulled `overrun_fired_at` (D-11 live state) | integration | `pytest tests/test_phase_35_e2e.py::test_attention_tiers_use_live_threshold_state -x` | 35-05 T3 | ❌ Wave 0 |
| MARG-04 / SC2 | Soft-deleted project / cost entry / budget excluded | integration | `pytest tests/test_phase_35_e2e.py::test_company_rollup_excludes_soft_deleted -x` | 35-05 T3 | ❌ Wave 0 |
| MARG-04 / SC2 | Tier ladder + portfolio aggregation correct in isolation | unit (pytest) | `pytest tests/unit/test_portfolio_math.py -q` | 35-01 T3 | ❌ Wave 0 |
| MARG-04 / SC2 | Overview + drill-down render with Reports conventions (ChartCard aria-labels, skeleton, empty state) | e2e | `npx playwright test tests/phase-35-financials.spec.ts -g "renders"` | 35-11 T3 | ❌ Wave 0 |
| MARG-04 / SC2 | Portfolio tiles, budget bars, attention list, projects table honesty states | unit (jest) | `npx jest "src/app/(dashboard)/financials"` | 35-09 T1-T3 | ❌ Wave 0 |
| **D-03** | Query count identical for 5-project and 25-project companies (primary N+1 guard) | integration | `pytest tests/test_phase_35_e2e.py::test_company_rollup_query_count_is_constant_in_project_count -x` | 35-08 T1 | ❌ Wave 0 |
| **D-03** | Company rollup median latency < committed ceiling at 25 projects / ~5,000 records | integration | `pytest tests/test_phase_35_e2e.py::test_company_rollup_latency_budget -x -s` | 35-08 T2 | ❌ Wave 0 |
| **D-03** | Statement counter records and detaches | integration | `pytest tests/test_phase_35_e2e.py::test_sql_statement_counter_records_statements -x` | 35-02 T2 | ❌ Wave 0 |
| **D-03** | Multi-project seeder produces figures the shipped rollup confirms | integration | `pytest tests/test_phase_35_e2e.py -k seed_company_portfolio` | 35-02 T3 | ❌ Wave 0 |
| MARG-04 / SC3 | All three endpoints 403 for admin token (no finance.view) | integration | `pytest tests/test_phase_35_e2e.py::test_financial_endpoints_forbidden_without_finance_view -x` | 35-08 T3 | ❌ Wave 0 |
| MARG-04 / SC3 | Tenant B cannot read tenant A's project financials (RLS) | integration | `pytest tests/test_phase_35_e2e.py::test_project_financials_rls_isolation -x` | 35-06 T3 | ❌ Wave 0 |
| MARG-04 / SC3 | Tenant B's company rollup excludes tenant A entirely (RLS) | integration | `pytest tests/test_phase_35_e2e.py::test_company_rollup_is_tenant_isolated -x` | 35-08 T3 | ❌ Wave 0 |
| MARG-04 / SC3 | Gate renders loading / deny / children branches | unit (jest) | `npx jest src/features/finance/__tests__/finance-gate.test.tsx` | 35-03 T2 | ❌ Wave 0 |
| MARG-04 / SC3 | Denied user's hooks issue **zero** fetches; permitted user's issue exactly one each (the load-bearing half of the SC3 keystone) | unit (jest) | `npx jest src/features/finance/__tests__/financials-hooks.test.tsx` | 35-04 T3 | ❌ Wave 0 |
| MARG-04 / SC3 | Response mappers preserve nulls and hit the right paths | unit (jest) | `npx jest src/features/finance/__tests__/financials-api.test.ts` | 35-04 T2 | ❌ Wave 0 |
| MARG-04 / SC3 | Non-finance user sees no Financials nav item | e2e | `npx playwright test tests/phase-35-financials.spec.ts -g "nav item"` | 35-11 T2 | ❌ Wave 0 |
| MARG-04 / SC3 | Direct `/financials` + `/financials/[id]` → deny panel AND zero `/api/v1/financials/*` proxy requests | e2e | `npx playwright test tests/phase-35-financials.spec.ts -g "direct navigation"` | 35-11 T2 | ❌ Wave 0 |
| MARG-04 / SC3 | Finance user sees nav item and reaches both routes by SPA navigation | e2e | `npx playwright test tests/phase-35-financials.spec.ts -g "finance user"` | 35-11 T2 | ❌ Wave 0 |
| Regression | Shipped revenue-resolution helpers relocated with zero behavior change | integration | `pytest tests/test_phase_32_e2e.py tests/test_phase_33_e2e.py tests/test_phase_34_e2e.py -q` | 35-01 T1 | ✅ exists |
| Regression | Query-builder renames + date columns leave shipped callers unaffected | integration | `pytest tests/test_phase_33_e2e.py tests/test_phase_34_e2e.py -q` | 35-05 T1, 35-07 T1 | ✅ exists |
| Regression | Reports page untouched (Phase 30 D-06) | e2e | `npx playwright test tests/phase-18-reports.spec.ts` | 35-03, 35-11 T3 | ✅ exists |
| Regression | Phase 33/34 web finance surfaces unchanged | e2e | `npx playwright test tests/phase-33-margin.spec.ts tests/phase-34-budgets.spec.ts` | 35-11 T3 | ✅ exists |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## D-03 Latency Budget (state this in the plan)

**Seed:** one company with 25 projects × (4 scopes, 2 jobs, 20 cost entries, 50 completed time entries, 2 invoices, 2 approved quotes) + 25 project budgets + 100 scope budgets ≈ 5,000 financial records.

**Two assertions, both required:**
1. **Query-count invariant (primary, deterministic):** SQL statement count for `GET /financials/company` at 25 projects **equals** the count at 5 projects, measured via a `before_cursor_execute` listener. The equality is the contract; the absolute value (~9–11, given the scope-label and scope-spend queries on top of the 8 core aggregates) is **pinned to whatever the first run observes** and recorded in `_MAX_COMPANY_ROLLUP_STATEMENTS` — never a guessed constant.
2. **Wall-clock ceiling:** discard one warm-up, time 5 requests, median < **1500 ms** (the initial committed value in `_COMPANY_ROLLUP_LATENCY_BUDGET_MS`, plan 35-08 T2).

**Follow-up rule:** if the first measured median ≪ 1500 ms, tighten the committed ceiling to ~2× the measured median. If it exceeds 1500 ms, the cache/snapshot decision reopens as a follow-up — never silently added this phase.

**Caveat to record:** in-process ASGI + local Postgres is evidence, not a production SLO.

---

## Wave 0 Requirements

- [ ] **35-02 T1** `backend/tests/test_phase_35_e2e.py` — all backend rows; reuse the `test_phase_34_e2e.py` endpoint-driven helper set (`_seed_cost_categories`, `_create_project`, `_create_trade_scope`, `_create_job`, `_create_budget`, `_add_cost_entry`, `_post_rate`, `_seed_time_entry`, `_pm_headers`, `_admin_headers`)
- [ ] **35-02 T3** `_seed_company_portfolio(project_count, …)` multi-project seeding helper — the phase's largest test scaffolding
- [ ] **35-02 T2** `_count_sql_statements()` query-counting context manager via `sqlalchemy.event.listen(engine.sync_engine, "before_cursor_execute", …)` — **no precedent in this repo**; write in Wave 0
- [ ] **35-11 T1-T3** `web/tests/phase-35-financials.spec.ts` — SC3 keystone + render specs (template: `phase-34-budgets.spec.ts`; login through UI + SPA-navigate)
- [ ] **35-03 T1-T2 / 35-04 T2 / 35-09 / 35-10** Web Jest specs under `src/app/(dashboard)/financials` + `src/features/finance/__tests__/` additions
- [ ] **35-01 T2-T3** Backend pure-math unit tests (`tests/unit/test_trend_math.py`, `tests/unit/test_portfolio_math.py`)
- Framework install: none — all harnesses configured and in use.

---

## Manual-Only Verifications

None — visual chart polish falls to the UI-SPEC checker/UAT pass.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (33 tasks, every one carries an `<automated>` command)
- [x] Wave 0 covers all MISSING references (plans 35-01/35-02/35-03 land in wave 1)
- [x] No watch-mode flags
- [x] Feedback latency < 30s (phase-gate full suites and the 25-project D-03 seed sanctioned)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** per-task map completed at plan time 2026-07-28
