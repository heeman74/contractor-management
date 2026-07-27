---
phase: 32-labor-rates-and-cost-rollup
verified: 2026-07-27T00:00:00Z
status: passed
score: 32/32 must-haves verified
---

# Phase 32: Labor Rates and Cost Rollup Verification Report

**Phase Goal:** Labor cost is derived automatically and accurately from tracked time, and Owner/PM can see a complete, itemized picture of what every job actually cost
**Verified:** 2026-07-27
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

All 32 truths across the five plans' `must_haves` were verified against the actual codebase (not SUMMARY claims).

**32-01 — Labor-rate foundation (COST-04, COST-05)**

| # | Truth | Status | Evidence |
| --- | ----- | ------ | -------- |
| 1 | POST a rate with past/present/future effective date, append-only | ✓ VERIFIED | Only `@router.post` + `@router.get` on `/labor-rates/` (router.py:206,219 — no PATCH/DELETE); `test_rate_backdated_is_accepted`, `test_rate_future_dated_excluded_from_current_but_kept_in_history` pass |
| 2 | GET full rate history with superseded and future rows present | ✓ VERIFIED | `LaborRateRepository.list_history_for_user`; `test_rate_create_and_history_preserved` passes |
| 3 | One current rate per worker in a single request | ✓ VERIFIED | `list_current_rates` groups one `list_all_rates()` fetch via `_group_rates_by_user` + shared resolver (service.py:304-306); `test_rate_current_list_returns_one_row_per_user` passes |
| 4 | No `finance.rates.manage` (incl. admin) → 403 on read and write | ✓ VERIFIED | Exactly 2 inline `require_permission("finance.rates.manage")` gates; `test_rate_endpoints_403_for_admin` / `_worker` pass |
| 5 | Rate rule: latest `effective_from <= work day`, tie by `created_at`, else unrated | ✓ VERIFIED | `resolve_rate_row_for_work_date` (bisect_right, ascending pre-sort = tie-break); 11 DB-free unit tests in `test_labor_derivation.py` pass |

**32-02 — Derivation + breakdown (COST-05, COST-06)**

| # | Truth | Status | Evidence |
| --- | ----- | ------ | -------- |
| 6 | Job labor = completed seconds × rate effective on UTC work day | ✓ VERIFIED | `_derive_labor` → `summarize_labor`; `test_derivation_uses_rate_effective_on_work_day_not_today` passes |
| 7 | New rate effective today leaves past job labor unchanged (keystone) | ✓ VERIFIED | `test_derivation_later_rate_change_does_not_rewrite_history` (e2e:450) passes |
| 8 | Backdating converts unrated seconds to rated cost, no recompute step | ✓ VERIFIED | `test_derivation_backdated_rate_fills_unrated_days` (e2e:475) passes — derivation is query-time, nothing stored |
| 9 | Uncovered time reported as `unrated_seconds`, never $0 labor | ✓ VERIFIED | `LaborTotals.unrated_seconds` plumbed to `LaborCostSummary.unrated_seconds`; same test asserts 14400 unrated before backdate |
| 10 | Active / soft-deleted entries contribute zero labor | ✓ VERIFIED | Three predicates: `session_status.in_(("completed","adjusted"))`, `duration_seconds.is_not(None)`, `deleted_at.is_(None)` (repository.py:43-44); `test_derivation_excludes_active_and_deleted_sessions` passes |
| 11 | Job / trade-scope / project breakdowns with per-category totals + grand total | ✓ VERIFIED | `job_cost_breakdown`, `trade_scope_cost_breakdown`, extended `rollup_for_project`; `test_breakdown_job_category_totals_and_grand_total` passes |
| 12 | Trade-scope breakdown: `labor_tracked_at_job_level=true`, no labor figure | ✓ VERIFIED | `_build_breakdown(category_rows, None, tracked_at_job_level=True)` (service.py:225); `test_breakdown_trade_scope_has_no_labor_figure` passes |
| 13 | Existing rollup `total`/`entries` unchanged (mobile parser compat) | ✓ VERIFIED | `test_breakdown_project_rollup_keeps_total_and_entries_backward_compatible` passes; phase 31 tests unregressed |
| 14 | Manual cost entry with reserved labor category → 422 | ✓ VERIFIED | `_reject_reserved_labor_category` called first in create (146) and update (229); 5 `labor_category` tests pass incl. legacy-fold case |

**32-03 — Team page rates UI (COST-04)**

| # | Truth | Status | Evidence |
| --- | ----- | ------ | -------- |
| 15 | Cost Rate column shows current rate or em dash | ✓ VERIFIED | `team/page.tsx:168` header, rate/`—` cells; Playwright spec test 1 (executor-verified green) |
| 16 | Rate dialog: add rate appears in history without closing | ✓ VERIFIED | `RateHistoryDialog` keeps open on success, invalidation refreshes; Jest rate-history suite in 194-pass run; Playwright test 4 |
| 17 | Full history visible with `Starts {date}` and `Superseded` badges | ✓ VERIFIED | Badge strings present in dialog (9 matches for Superseded/Starts/empty-state); `supersededRateIds`/`nextFutureRate` helpers unit-tested |
| 18 | Without `finance.rates.manage`: no column, no rate values anywhere | ✓ VERIFIED | Three `canManageRates &&` conditionals (header:166, cell:203, dialog:239); leak audit: `labor-rates|hourlyCost` confined to features/finance + team surfaces |
| 19 | Current rates load in one batched request | ✓ VERIFIED | Single `useCurrentLaborRates(canManageRates)` + `rateByUserId` map; no per-row hook |

**32-04 — Web breakdown surfaces (COST-06)**

| # | Truth | Status | Evidence |
| --- | ----- | ------ | -------- |
| 20 | Category totals + Total row on job, trade-scope, and project Costs surfaces | ✓ VERIFIED | `CostBreakdownSummary` mounted in all three files (grep -l confirms); Jest cost-breakdown suite passes |
| 21 | Unrated badge `{H} hrs unrated` with hours visible | ✓ VERIFIED | `formatUnratedHours` exported + unit-tested (1 hr / 2 hrs / 12.5 hrs cases) |
| 22 | Info affordance: `Wage cost only — excludes payroll tax, insurance, overhead.` | ✓ VERIFIED | Verbatim string + `PopoverTrigger` in CostBreakdownSummary.tsx; no `asChild`, no tooltip.tsx invented |
| 23 | Trade-scope labor row reads `Tracked at job level` | ✓ VERIFIED | String present; `variant="trade-scope"` in TradeScopeDetail.tsx |
| 24 | Project Total Spent prefers grand total, falls back to cost-entry total | ✓ VERIFIED | `rollup?.grandTotal ?? rollup?.total ?? "0"` with `data-testid="project-cost-total"` preserved (ProjectCostsCard.tsx:33-35) |
| 25 | Labor category not selectable in AddCost picker | ✓ VERIFIED | `selectableCategories` filter over `LABOR_CATEGORY_NAME` (AddCostDialog.tsx:35,52,174) |

**32-05 — Mobile breakdown (COST-06)**

| # | Truth | Status | Evidence |
| --- | ----- | ------ | -------- |
| 26 | Category totals + total on mobile job/scope/project detail | ✓ VERIFIED | `CostBreakdownSummary` mounted in all three screens; mobile E2E group "COST-06 job breakdown" passes |
| 27 | `{H} hrs unrated` chip when time has no covering rate | ✓ VERIFIED | E2E asserts `12.5 hrs unrated`; `formatUnratedHours` helper unit-tested |
| 28 | Static unburdened caption under every mobile labor figure | ✓ VERIFIED | Verbatim string in widget; E2E asserts presence (job) and absence (trade scope) |
| 29 | Trade-scope labor row reads `Tracked at job level`, no amount | ✓ VERIFIED | String in widget; E2E trade-scope group passes |
| 30 | Offline fetch failure → `Breakdown unavailable offline`, cached list still renders | ✓ VERIFIED | E2E offline group passes with Drift in-memory seed |
| 31 | Labor category not selectable in mobile add-cost sheet | ✓ VERIFIED | `_selectableCategories` filter (add_cost_sheet.dart:20,167); E2E picker test passes |
| 32 | Rate values never reach the device | ✓ VERIFIED | `grep -r "labor_rates\|hourly_cost\|hourlyCost" mobile/lib` → zero matches; amounts are backend strings, `double.parse`/`toDouble()` absent from the widget |

**Score:** 32/32 truths verified

### Required Artifacts

All 26 artifacts across the five plans passed existence + substantive checks via `gsd-tools verify artifacts` (26/26). Highlights:

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `backend/app/features/finance/labor_derivation.py` | Pure DB-free rate-resolution + labor math | ✓ VERIFIED | 109 lines; zero sqlalchemy/fastapi/float; bisect_right, ROUND_HALF_UP, per-session quantize; single home of `LABOR_CATEGORY_NAME` |
| `backend/app/features/finance/repository.py` | LaborRateRepository + bounded derivation queries | ✓ VERIFIED | Column-only session selects with 3 predicates; one shared `_category_totals_where` GROUP BY; `user_exists`, `is_reserved_labor_category` |
| `backend/app/features/finance/service.py` | LaborRateService + breakdown/rollup/guard | ✓ VERIFIED | `_derive_labor` = 1 extra round trip (no N+1); `_build_breakdown` folds legacy labor rows; no `db.commit()` |
| `backend/app/features/finance/router.py` | Gated labor-rate + breakdown endpoints | ✓ VERIFIED | 2× `finance.rates.manage` gates, breakdowns on `finance.view`; append-only (no PATCH/DELETE) |
| `backend/tests/test_phase_32_e2e.py` | COST-04/05/06 integration coverage | ✓ VERIFIED | 30 e2e tests: 13 rate, 6 derivation, 6 breakdown, 5 labor_category — all green |
| `web/src/.../rate-history-dialog.tsx` | Headline, add-rate form, badged history | ✓ VERIFIED | All UI-SPEC strings present; exported pure helpers |
| `web/src/features/finance/components/CostBreakdownSummary.tsx` | Shared breakdown block | ✓ VERIFIED | Popover disclosure, unrated badge, trade-scope note, error/empty states |
| `mobile/lib/features/finance/data/cost_breakdown.dart` | Strict/tolerant typed models | ✓ VERIFIED | `is`-check parsing, `whereType<CategoryTotal>()`, FormatException on shape breaks |
| `mobile/test/e2e/phase_32_labor_cost_e2e_test.dart` | Phase E2E suite | ✓ VERIFIED | 10 tests green, real Drift in-memory DB |

### Key Link Verification

12/13 auto-verified by `gsd-tools verify key-links`; the 3 flagged were manually confirmed as tool regex-escaping false negatives:

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| finance/router.py | `finance.rates.manage` | inline gates | ✓ WIRED | `grep -c` = exactly 2 (manual check; tool escaping issue) |
| finance/service.py | labor_derivation.py | `resolve_rate_row_for_work_date` / `summarize_labor` | ✓ WIRED | Single source of the rule; no SQL duplication |
| finance/repository.py | labor_rates / TimeEntry / jobs.project_id | RLS-scoped selects, project join | ✓ WIRED | Pattern found |
| finance/service.py | reserved labor CostCategory | 422 guard, create + update | ✓ WIRED | Exact detail string `"Labor cost is derived from tracked time."` |
| team/page.tsx | usePermissions | `can("finance.rates.manage")` | ✓ WIRED | Column, cell, and dialog all gated |
| finance/hooks.ts | cost-entries cache | `useAddLaborRate` invalidates both prefixes | ✓ WIRED | hooks.ts:146-147 (manual check; tool false negative) |
| finance/api.ts | `/api/v1/labor-rates/` + `/cost-breakdown` | apiGet/apiPost | ✓ WIRED | Pattern found |
| jobs/[id]/page.tsx (+2 surfaces) | CostBreakdownSummary | mounted inside finance.view gates | ✓ WIRED | All three web + all three mobile mounts confirmed |
| mobile finance_repository.dart | `/jobs/{id}/cost-breakdown` | Dio get + is-check parsing | ✓ WIRED | finance_repository.dart:123,129 (manual check; tool false negative) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| team/page.tsx Cost Rate column | `currentRates` → `rateByUserId` | `useCurrentLaborRates` → GET /labor-rates/ → `list_all_rates()` DB query | Yes | ✓ FLOWING |
| CostBreakdownSummary (web, all 3) | `breakdown` | `useJobCostBreakdown` etc. → breakdown endpoints → GROUP BY + `summarize_labor` over TimeEntry rows | Yes | ✓ FLOWING |
| ProjectCostsCard Total Spent | `rollup.grandTotal` | extended `rollup_for_project` (real entries + derived labor) | Yes | ✓ FLOWING |
| Mobile CostBreakdownSummary (all 3) | `breakdownAsync.value` | FutureProviders → Dio → same endpoints | Yes | ✓ FLOWING |

No hardcoded-empty props, no static returns masquerading as data.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Rate rule + derivation + breakdown + guard (backend) | `pytest tests/unit/test_labor_derivation.py tests/test_phase_32_e2e.py -q` | 41 passed | ✓ PASS |
| Backend lint | `ruff check app/features/finance/` | All checks passed | ✓ PASS |
| Web unit suite (incl. rate-history + cost-breakdown) | `npm test -- --watchAll=false` | 25 suites / 194 tests passed | ✓ PASS |
| Web Playwright phase spec | 10 tests in `phase-32-labor-rates.spec.ts` | Executor-verified green (not re-run) | ✓ PASS |
| Mobile phase E2E | `flutter test test/e2e/phase_32_labor_cost_e2e_test.dart` | 10 passed | ✓ PASS |
| Mobile parsing unit tests | `flutter test test/unit/features/finance/cost_breakdown_parsing_test.dart` | 9 passed | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
| ----------- | ------------ | ----------- | ------ | -------- |
| COST-04 | 32-01, 32-03 | Set worker hourly rate with effective date; history preserved | ✓ SATISFIED | Append-only endpoints + 13 rate tests; Team page column + dialog with full badged history |
| COST-05 | 32-01, 32-02 | Labor derived automatically: tracked time × rate effective on work day | ✓ SATISFIED | Pure resolver + `summarize_labor`; keystone no-retroactive-rewrite and backdate-fills-unrated tests green |
| COST-06 | 32-02, 32-04, 32-05 | Itemized costs per job/scope/project with category totals | ✓ SATISFIED | Breakdown endpoints + all six UI mounts (3 web, 3 mobile) + reserved-category guard on API and both pickers |

No orphaned requirements: REQUIREMENTS.md maps exactly COST-04/05/06 to Phase 32, and every ID appears in at least one plan's `requirements` frontmatter.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| — | — | none | — | No TODO/FIXME/placeholder, no `float()` in money math, no `double.parse` in mobile amounts, no `db.commit()` in services, no rate leakage outside gated surfaces (backend sync, web non-team/finance, entire mobile/lib all clean) |

### Human Verification Required

None blocking. The single manual-only UAT item from 32-VALIDATION.md is aesthetic and non-blocking per CLAUDE.md UAT rules (all functional behavior is covered by automated tests):

- **Visual polish of unburdened popover / caption placement** — open job/scope/project cost sections on web + mobile; confirm the info affordance is discoverable and readable. (Aesthetic judgment only; presence/copy/behavior already asserted by Jest, Playwright, and Flutter E2E.)

### Gaps Summary

No gaps. All three ROADMAP success criteria are proven by automated tests against the real codebase:

1. **Effective-dated rates with preserved history** — append-only API (no PATCH/DELETE exists), history endpoint returns superseded and future rows, UI renders them with badges.
2. **Derivation uses the rate effective on the work day; later changes never rewrite history** — derivation is computed at query time from immutable rate rows via a single pure resolver; `test_derivation_later_rate_change_does_not_rewrite_history` proves the total stays byte-identical after adding a new rate.
3. **Itemized costs per job / trade scope / project by category** — breakdown endpoints plus six UI mounts show Labor/Materials/Subcontractor/Other with totals; trade scopes honestly report "Tracked at job level"; unrated hours are surfaced, never silently $0; double-counting is blocked at API (422) and both pickers.

---

_Verified: 2026-07-27_
_Verifier: Claude (gsd-verifier)_
