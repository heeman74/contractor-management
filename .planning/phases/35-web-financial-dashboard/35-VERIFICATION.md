---
phase: 35-web-financial-dashboard
verified: 2026-07-28T00:00:00Z
status: passed
score: 11/11 must-haves verified
re_verification: null
requirements:
  - id: MARG-04
    status: satisfied
    evidence: "Three gated endpoints + two web routes; 24/24 backend E2E, 41/41 backend unit, 134/134 web jest green"
notes:
  playwright_attested_not_reproduced: true
  deferred_items: 1
---

# Phase 35: Web Financial Dashboard Verification Report

**Phase Goal:** Owner/PM can see the financial health of every project and the company as a whole at a glance, in the same reporting experience they already use
**Verified:** 2026-07-28
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | **SC1** — Owner/PM views margin trend + budget-vs-actual charts for any project | ✓ VERIFIED | `GET /projects/{id}/financials` (router.py:175) and `/financials/trend` (router.py:186) both live and gated; `margin-trend-chart.tsx`, `scope-budget-bars.tsx`, `category-mix-chart.tsx` render from real hook data; 6 trend tests + 2 drill-down tests green |
| 2 | **SC2** — Company-wide rollup alongside v2.0 reporting, same navigation and visual conventions | ✓ VERIFIED | `GET /financials/company` (router.py:230); `/financials` route reuses `ChartCard` + shared `chart-theme.ts`; sidebar entry sits in the same `navItems` array as Reports; 6 portfolio tests green |
| 3 | **SC3** — User without `finance.*` sees no nav item and no financial route at all | ✓ VERIFIED | Four independent layers, each independently exercised — see SC3 table below |
| 4 | Trend final bucket **is** the shipped project rollup (reconciliation keystone) | ✓ VERIFIED | `test_trend_final_bucket_reconciles_with_project_rollup` asserts `final_bucket["cost"] == rollup.grand_total` **and** `_assert_margin_matches(final_bucket, rollup.margin)`; implementation replays D-01 per edge, not deltas |
| 5 | Window slices buckets, never records | ✓ VERIFIED | `window_slice` (trend_math.py:174) slices the produced bucket list; test asserts every shared month is byte-identical across 3 windows and that the narrow window's earliest bucket is far from zero |
| 6 | Company rollup query count does not grow with project count (D-03) | ✓ VERIFIED | `_MAX_COMPANY_ROLLUP_STATEMENTS = 15`, pinned to an observed 13, with **equality** at 5 vs 25 projects as the contract; AST scan confirms zero `await` inside any loop/comprehension in `portfolio_service.py` |
| 7 | Company rollup latency under a committed, measured ceiling (D-03) | ✓ VERIFIED | `_COMPANY_ROLLUP_LATENCY_BUDGET_MS = 400`, tightened from 1500 per the VALIDATION follow-up rule; recorded medians 127/199/252 ms — **I re-measured 150 ms** |
| 8 | Attention tiers read live threshold state, not fired claim columns (D-11) | ✓ VERIFIED | Both directions asserted: `live_over` (over budget, `overrun_fired_at IS NULL`) **is** listed; `stale_claim` (real `overrun_fired_at`, crossing undone) **is not**. Fired-column state pinned first (lines 1332-1333) so neither direction can pass vacuously |
| 9 | 35-01 refactor left Phase 32/33/34 suites green with no test-file edits | ✓ VERIFIED | The relocation commit `288f7d7` touched **zero** test files; across all 60 Phase 35 commits the only test files touched are the 10 new ones. No import update was needed at all |
| 10 | `BulletBarChart` is generic, serving both budget surfaces | ✓ VERIFIED | `BulletBarRow` carries `id`/`label` (no `projectId`/`tradeScopeId`); `testId` is a prop; `onRowClick` optional. Consumed by both `project-budget-bars.tsx` and `scope-budget-bars.tsx` |
| 11 | Phase 30 D-06 boundary held — Reports untouched, no financial leaks | ✓ VERIFIED | The only pre-existing file Phase 35 modified is `sidebar.tsx`, **+2 lines**. `chart-theme.ts` and `chart-empty-state.tsx` are NEW files imported only by financials surfaces — Reports imports neither |

**Score:** 11/11 truths verified

### SC3 — Four Independent Layers

| Layer | Mechanism | Verified by |
|-------|-----------|-------------|
| Nav | `sidebar.tsx:88` `permission: "finance.view"`, filtered at line 120 via `can(item.permission)` | Code read + Playwright (attested) |
| Render | `FinanceGate` mounted once at `financials/layout.tsx`, guards both routes | `finance-gate.test.tsx` (green) |
| Fetch | `enabled: can(FINANCE_VIEW_PERMISSION)` on all three hooks; fails closed while permissions load | `financials-hooks.test.tsx` — zero-fetch on denied **and** on still-loading (green, run by verifier) |
| Backend | `require_permission("finance.view")` on all three endpoints | `test_financial_endpoints_forbidden_without_finance_view` — loops all 3 URLs, asserts 403 + detail (green) |

The gate and the fetch-guard import the same key from `types.ts`, so the two branches cannot drift.

### Required Artifacts

| Plan | Artifacts | Status |
|------|-----------|--------|
| 35-01 … 35-11 | 28 declared across 11 plans | ✓ 28/28 exist, substantive, wired |

No stubs, no orphans, no placeholder returns.

### Key Link Verification

`gsd-tools` reported 22 links with 6 unverified. All 6 were investigated manually; **none is a real gap**:

| Link | Tool result | Reality |
|------|-------------|---------|
| sidebar → `permission: "finance.view"` | not found | ✓ Present, `sidebar.tsx:88` — tool's quote-escaping |
| hooks → `enabled:.*can\(` | invalid regex | ✓ Present on all 3 hooks — double-escaped pattern |
| router → `projects/{project_id}/financials` | not found | ✓ Present, `router.py:175` — brace escaping |
| `useCompanyFinancials()` | not found | ✓ Present, dashboard line 44 — paren escaping |
| `useProjectMarginTrend(` | invalid regex | ✓ Present, drill-down line 75 |
| `coalesce(Quote.approved_at, Quote.created_at)` | not found | ✓ Present at **`repository.py:347`**, consumed by label `row.approved_on` in `portfolio_repository.py:223`. The plan predicted the wrong file; the query builder correctly lives with its siblings. Plan-prediction mismatch, not a wiring gap |

### Data-Flow Trace (Level 4)

| Artifact | Data source | Flows | Status |
|----------|-------------|-------|--------|
| `company-financials-dashboard.tsx` | `useCompanyFinancials()` → `/api/v1/financials/company` | portfolio/projects/attention destructured into every child prop | ✓ FLOWING |
| `project-financials-dashboard.tsx` | `useProjectFinancials` + `useProjectMarginTrend` | separate query keys; `window` only in the trend key | ✓ FLOWING |
| `margin-trend-chart.tsx` | trend buckets | `connectNulls` false → null margin renders a gap, not $0 | ✓ FLOWING |

Zero hardcoded-empty props found across the financials tree. Loading and error states replace figures rather than leaving stale money on screen.

### Behavioral Spot-Checks

| Check | Command | Result | Status |
|-------|---------|--------|--------|
| Backend E2E | `pytest tests/test_phase_35_e2e.py -q` | **24 passed** in 99s | ✓ PASS |
| Backend unit | `pytest tests/unit/test_trend_math.py tests/unit/test_portfolio_math.py -q` | **41 passed** | ✓ PASS |
| Web unit | `npx jest src/features/finance "src/app/(dashboard)/financials"` | **134 passed**, 9 suites | ✓ PASS |
| D-03 measurement | `pytest -k "latency_budget or query_count" -s` | `D-03 company rollup median: 150 ms`, 2 passed | ✓ PASS |
| Web typecheck | `npx tsc --noEmit` | exit 0 | ✓ PASS |
| Web lint | `npm run lint` (`--max-warnings 0`) | clean | ✓ PASS |
| Backend lint/format | `ruff check .` / `ruff format --check .` | All checks passed; 308 files formatted | ✓ PASS |
| Playwright | `npx playwright test tests/phase-35-financials.spec.ts` | not re-run (needs dev server) | ? SKIP — see below |

**Reproduced the documented flakiness cause.** My first backend run reported 11 failures. Root cause: I had launched the unit tests concurrently, and the autouse `clean_tables` truncate deadlocked against the E2E run (`asyncpg.exceptions.DeadlockDetectedError`). Re-run in isolation: **24/24 green**. This independently confirms the shared-test-DB contention that 35-01-SUMMARY documented — it is an environment constraint, not a product defect.

### Requirements Coverage

| Requirement | Source | Description | Status | Evidence |
|-------------|--------|-------------|--------|----------|
| MARG-04 | all 11 plans | Owner/PM can see margin + budget-vs-actual charts on the web financial dashboard | ✓ SATISFIED | Three endpoints + two routes shipped and gated; all three SCs verified |

No orphaned requirements — MARG-04 is the only ID REQUIREMENTS.md maps to Phase 35, and every plan declares it.

### Anti-Patterns Found

None. Scanned all 34 non-test source files touched by Phase 35 for TODO/FIXME/XXX/HACK/placeholder/"coming soon"/"not yet implemented", empty returns and no-op handlers — **zero matches**.

### Code Quality (clean-code skill + CLAUDE.md)

| Standard | Assessment |
|----------|------------|
| Small functions | Longest new Python function is 32 lines including docstring; most under 20. Meets the ~20-line target |
| Meaningful names | `anchor_revenues`, `worst_crossed_budget`, `percentUsedClamped`, `dense_month_keys` — intention-revealing throughout |
| No magic numbers | Constants named and centralized (`chart-theme.ts`, `BUDGET_REFERENCE_PERCENT`, `_MAX_COMPANY_ROLLUP_STATEMENTS`) |
| DRY | `FinanceGate` extracted as the third occurrence of the loading→deny→children recipe; `BulletBarChart` shared by two surfaces; trend reuses the shipped `FinanceRepository` methods so it cannot drift |
| Comments explain WHY | Consistently. Several comments actively defend invariants against future "fixes" (the false-green note in the Playwright spec, the `ORDER BY created_at` note in 35-07) |
| N+1 prevention | AST scan: zero `await` inside any loop or comprehension in `portfolio_service.py` |
| OOP architecture | `PortfolioRepository(TenantScopedRepository[Project])`, `PortfolioService(TenantScopedService[Project])` |
| Response schemas | New aggregate schemas use plain `BaseModel`, matching the shipped `CostBreakdownResponse` / `ProjectCostRollupResponse` precedent. `BaseResponseSchema` requires `id`/`version`/timestamps and is for entity responses; report payloads have no entity identity. Consistent with convention, not a violation |

### Human Verification Required

None blocking. Two informational items:

1. **Playwright suite — executor-attested, not verifier-reproduced.** The 6-test `phase-35-financials.spec.ts` exists and its assertions are load-bearing on inspection, and break-it-once was recorded (removing `<FinanceGate>` produced a real failure, then reverted with an empty diff). I did not re-run it — it needs a dev server. Confidence remains high because the SC3 keystone is independently confirmed at two other layers I *did* run green: the jest zero-fetch tests and the backend 403 loop. Recommend a CI run for completeness.

2. **Visual chart polish** falls to the UI-SPEC checker / UAT pass per 35-VALIDATION ("Manual-Only Verifications: None").

### Gaps Summary

No gaps. All 11 must-have truths hold in the codebase, not merely in the summaries.

Three claims I specifically tried to falsify and could not:

- **The reconciliation keystone is real, not asserted.** `_bucket_for` replays the shipped `anchor_revenues` / `combined_anchor_revenue` over documents effective on or before each month edge. It does not accumulate deltas — which is exactly why a quoted-then-invoiced anchor cannot double-count, and why the final-bucket equality is a genuine self-check rather than a tautology.
- **D-03's guard is the statement count, not the clock.** Equality at 5 vs 25 projects is the contract; the ceiling of 15 is pinned to an observed 13. 35-08 records that deliberately reintroducing a per-project loop diverged the counts 163 vs 43 — the test has teeth.
- **D-11 is tested in both directions,** and 35-08's summary records that the plan's *original* route to the `live_over` state was impossible (34-06 D-10 ships inline evaluation on PATCH, which re-arms and re-claims in one request). The executor found this and built a valid route instead of relaxing the test.

One deferred item, correctly scoped out: two Phase 21 AI specs (`ai-intake`, `ai-interview`) assert `/projects/{id}`, while `refactor-project-preselect.spec.ts` documents that the bare URL 404s by design and the app navigates to `/projects?project={id}`. I corroborated this independently — the only Playwright failure artifact on disk is that ai-intake test, and the preselect spec's comments confirm the query-param form is shipped behavior. Pre-existing drift, not a Phase 35 regression.

---

_Verified: 2026-07-28_
_Verifier: Claude (gsd-verifier)_
