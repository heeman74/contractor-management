---
phase: 33-profit-margin-tracking
verified: 2026-07-27T00:00:00Z
status: passed
score: 29/29 must-haves verified
requirements_status:
  MARG-01: satisfied
  MARG-02: satisfied
  MARG-03: satisfied
---

# Phase 33: Profit Margin Tracking — Verification Report

**Phase Goal:** Owner/PM can trust the profit margin shown for any job, trade scope, or project — real numbers where data exists, an honest flag where it doesn't
**Verified:** 2026-07-27
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Success Criteria (ROADMAP.md)

| # | Criterion | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Owner/PM can view profit margin (revenue minus actual cost) for any job or trade scope | ✓ VERIFIED | Backend E2E tests 1-5 pass (invoiced anchor, quote fallback, pre-tax D-13, scope anchor, finance.view 403). Web Jest (222 pass) + mobile widget E2E (25 pass) render Revenue/Margin rows on job and trade-scope surfaces |
| 2 | Owner/PM can view a project-level margin rollup aggregating across trade scopes | ✓ VERIFIED | Backend E2E tests 6-9 pass: D-12 same-traversal netting (revenue 1500.00, cost 450.00, margin 1050.00/70.0%), invoices-beat-quote-per-anchor, mixed basis, D-14 project-level quote fallback. `margin=rollup.margin` wired in router.py; `margin: rollup.margin` passed through web ProjectCostsCard; mobile project variant renders via `CostBreakdown.tryFromJson` |
| 3 | Incomplete cost data displays an explicit flag instead of a fabricated margin | ✓ VERIFIED | Keystone test 10 passes: revenue 2000.00 / zero cost → margin_percent "100.0" AND `incomplete=true` with `no_cost_data`. Test 11 (unrated_labor), test 12 (D-07: no revenue ≠ flagged), test 13 (project propagation from any anchor). Web state-12 contract (`isBreakdownEmpty` returns false when revenue exists so the flag cannot be hidden) verified in CostBreakdownSummary.tsx:59; mobile flagged-state widget test passes |

### Observable Truths (must_haves across 33-01…33-05)

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | One rounding policy for margin dollars/percent (cents / one decimal) | ✓ | margin_math.py: `CENTS`/`PERCENT_PLACES`, ROUND_HALF_UP only in `margin_percent_for`; 28 unit tests pass |
| 2 | Revenue resolves invoices → latest approved quote → nothing (D-01/D-03) | ✓ | `resolve_anchor_revenue` never sums/maxes; E2E tests 1, 2, 7 pass |
| 3 | Revenue is pre-tax on both legs (D-13) | ✓ | `pre_tax_total`; E2E test 3 (900.00 from 1000 − 10% disc, tax excluded) passes |
| 4 | Zero cost + revenue → incomplete, never clean 100% (D-05, Pitfall 9) | ✓ | `missing_cost_data`; keystone unit + E2E test 10 pass |
| 5 | No revenue source → absent margin, NOT flagged (D-07) | ✓ | `summarize_margin` early return; E2E test 12 passes |
| 6 | Invoice/quote totals + margin revenue share one math implementation | ✓ | Both schemas import `discount_for`/`tax_for`/`document_total`; inline branches deleted (grep 0); phase 16/25/quotes suites pass (74 tests) |
| 7 | Per-anchor invoice revenue in one bounded query | ✓ | `RevenueRepository._invoice_amounts_query` GROUP BY, coalesce ZERO_MONEY, no `float(` |
| 8 | Only latest approved quote backs revenue | ✓ | `QUOTE_STATUS_APPROVED` constant, `created_at DESC` + limit(1); E2E test 2 |
| 9 | Project revenue uses the same dual-outerjoin traversal as cost (D-12) | ✓ | `TradeScope.project_id == project_id` appears 3× (cost + invoice + quote legs); E2E test 6 |
| 10 | Per-job tracked time identifiable (sibling can't mask legacy job) | ✓ | `WorkSession.job_id` (labor_derivation.py:52), `_labor_by_job`; E2E test 13 |
| 11 | Integration contract existed as executable tests before assembly | ✓ | 13 named async tests in test_phase_33_e2e.py, all pass |
| 12 | Margin block on GET /jobs/{id}/cost-breakdown | ✓ | `job_cost_breakdown` → `_anchor_margin` → `model_copy(update={"margin": margin})` |
| 13 | Same block on GET /trade-scopes/{id}/cost-breakdown | ✓ | Scope path with `RevenueAnchor(trade_scope_id=...)`; E2E test 4 |
| 14 | Project margin via one traversal on GET /projects/{id}/cost-entries | ✓ | `_project_margin` + `ProjectMarginContext`; router `margin=rollup.margin` |
| 15 | Margin only on finance.view-gated responses, no new endpoints/gates | ✓ | E2E test 5 (admin 403 "Missing permission: finance.view"); zero margin refs in invoice/quote routers and reports feature |
| 16 | Web: Revenue + Margin rows beneath Total on all three surfaces | ✓ | `<MarginSummarySection margin={breakdown?.margin ?? null} />` in CostBreakdownSummary (all variants); Playwright spec (5 tests) executor-verified green |
| 17 | Web: quoted caption present, invoiced caption absent | ✓ | Named constants + Jest state tests |
| 18 | Web: flagged margin shows chip + caption + number | ✓ | FinanceFlagChip shared with unrated badge; Jest + Playwright keystone test |
| 19 | Web: no-revenue neutral note (state 7) | ✓ | `margin-no-revenue` testid + verbatim string |
| 20 | Web: legacy zero-cost job still renders (state 12) | ✓ | `isBreakdownEmpty` checks `revenueBasis !== "none"` |
| 21 | Web: negative margin destructive-colored, signed | ✓ | `formatMarginDollars("-350.00") → "-$350.00"`, `text-destructive` class asserted |
| 22 | Mobile: Revenue/Margin rows on job, scope, project surfaces | ✓ | `MarginSummarySection(margin: breakdown?.margin)` mounted (cost_breakdown_summary.dart:115); 25 tests pass |
| 23 | Mobile: quoted caption / invoiced none | ✓ | Widget E2E states 1-2 |
| 24 | Mobile: amber chip + caption + number when flagged | ✓ | `FinanceFlagChip` shared class; keystone widget test |
| 25 | Mobile: no-revenue neutral note | ✓ | State-7 widget test |
| 26 | Mobile: absent margin block parses cleanly, renders nothing | ✓ | `MarginSummary.tryFromJson` tolerant parse; 12 parser unit tests |
| 27 | Mobile: nothing persisted to Drift (D-10) | ✓ | No Drift/upsert refs in margin_summary_section.dart |
| 28 | Chip recipe shared, cannot drift (web + mobile) | ✓ | Inline chip literals removed from both CostBreakdownSummary implementations (grep 0) |
| 29 | Older backend without margin key degrades gracefully | ✓ | `mapMarginSummary(null) → null` (web); `tryFromJson` null path (mobile); tested both |

**Score:** 29/29 truths verified

### Required Artifacts (Levels 1-3)

| Artifact | Provides | Lines | Status |
| --- | --- | --- | --- |
| `backend/app/features/finance/margin_math.py` | DB-free document/revenue/margin math | 186 (≥120) | ✓ VERIFIED — contains `def summarize_margin`, no SQLAlchemy/FastAPI imports |
| `backend/tests/unit/test_margin_math.py` | Pure-math coverage | 292 (≥120), 28 tests | ✓ VERIFIED |
| `backend/tests/test_phase_33_e2e.py` | 13-test integration contract | 648 (≥400) | ✓ VERIFIED — 13 pass, no `float(` |
| `backend/app/features/finance/repository.py` | RevenueRepository bounded aggregates | 463 | ✓ VERIFIED |
| `backend/app/features/finance/labor_derivation.py` | WorkSession.job_id | line 52 | ✓ VERIFIED |
| `backend/app/features/finance/schemas.py` | MarginSummary + 2 additive fields | `margin: MarginSummary \| None = None` ×2 | ✓ VERIFIED |
| `backend/app/features/finance/service.py` | `_anchor_margin` / `_project_margin` assembly | 539 | ✓ VERIFIED |
| `backend/app/features/finance/router.py` | `margin=rollup.margin` wiring | 313 | ✓ VERIFIED |
| `web/src/features/finance/components/MarginSummarySection.tsx` | 12 UI-SPEC states | 119 | ✓ VERIFIED — all verbatim copy strings present |
| `web/src/features/finance/components/FinanceFlagChip.tsx` | Shared chip recipe (`bg-brand/15`) | 22 | ✓ VERIFIED — imported by both consumers |
| `web/tests/phase-33-margin.spec.ts` | Playwright coverage | 345, 5 tests | ✓ VERIFIED (green per executor; not re-run here — requires dev server) |
| `mobile/lib/features/finance/data/cost_breakdown.dart` | `static MarginSummary? tryFromJson` | 175 | ✓ VERIFIED — no bare `as` casts |
| `mobile/lib/features/finance/presentation/widgets/margin_summary_section.dart` | Margin rows/chip/captions | 136 | ✓ VERIFIED |
| `mobile/lib/features/finance/presentation/widgets/breakdown_row_widgets.dart` | Shared FinanceFlagChip primitives | 87 | ✓ VERIFIED |
| `mobile/test/e2e/phase_33_margin_e2e_test.dart` | Widget E2E all states + gating | 433, 10 testWidgets + helpers | ✓ VERIFIED |

### Key Link Verification

| From | To | Via | Status |
| --- | --- | --- | --- |
| invoices/schemas.py | margin_math | `from app.features.finance.margin_math import` | ✓ WIRED (inline math deleted, grep 0) |
| quotes/schemas.py | margin_math | same | ✓ WIRED |
| finance/repository.py | margin_math | DocumentAmounts/RevenueAnchor value objects | ✓ WIRED |
| finance/repository.py | invoices+jobs+trade_scopes | dual outerjoin, `TradeScope.project_id == project_id` ×3 | ✓ WIRED |
| finance/service.py | margin_math | summarize_margin / resolve_anchor_revenue / missing_cost_data | ✓ WIRED |
| finance/service.py | RevenueRepository | `RevenueRepository(self.db)` ×2 | ✓ WIRED |
| finance/router.py | ProjectCostRollupResponse.margin | `margin=rollup.margin` | ✓ WIRED |
| web api.ts | MarginSummary | `mapMarginSummary(raw.margin)` ×2 | ✓ WIRED |
| web CostBreakdownSummary | MarginSummarySection | rendered after Total row | ✓ WIRED |
| web ProjectCostsCard | rollup.margin | `margin: rollup.margin` in synthetic breakdown | ✓ WIRED |
| mobile cost_breakdown_summary.dart | MarginSummarySection | `MarginSummarySection(margin: breakdown?.margin)` last Column child | ✓ WIRED |
| mobile cost_breakdown.dart | margin JSON key | `MarginSummary.tryFromJson(json['margin'])` in fromJson | ✓ WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Real Data | Status |
| --- | --- | --- | --- | --- |
| MarginSummarySection (web) | `breakdown.margin` | fetchCostBreakdown / fetchProjectCostRollup → mapMarginSummary → backend | Yes — backend assembles from live Invoice/Quote/CostEntry/TimeEntry queries (13 DB-backed E2E tests) | ✓ FLOWING |
| MarginSummarySection (mobile) | `breakdown?.margin` | finance_repository fetch → CostBreakdown.fromJson | Yes — same wire contract, tolerant parse | ✓ FLOWING |
| ProjectCostRollupResponse.margin | `rollup.margin` | FinanceService.rollup_for_project → RevenueRepository dual-outerjoin queries | Yes — E2E test 6 nets real seeded invoices/costs/time | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| Margin math unit contract | `pytest tests/unit -k margin -q` | 28 passed | ✓ PASS |
| Full phase 33 backend contract | `pytest tests/test_phase_33_e2e.py -q` | 13 passed | ✓ PASS |
| Invoice/quote totals + cost surfaces regression | `pytest tests/test_phase_16_e2e.py tests/test_phase_25_e2e.py tests/unit/test_quote_validation.py tests/test_project_quotes_e2e.py tests/test_phase_31_e2e.py tests/test_phase_32_e2e.py -q` | 74 passed | ✓ PASS |
| Web full Jest suite | `npm test -- --watchAll=false` | 26 suites / 222 tests passed | ✓ PASS |
| Mobile phase 33 E2E + parser | `flutter test test/e2e/phase_33_margin_e2e_test.dart test/features/finance/margin_summary_parse_test.dart` | 25 passed | ✓ PASS |
| Lint: ruff / tsc / dart analyze | finance + touched files | all clean | ✓ PASS |
| Playwright phase spec | `npx playwright test tests/phase-33-margin.spec.ts` | executor-verified green (needs dev server; not re-run) | ✓ PASS (executor) |

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
| --- | --- | --- | --- | --- |
| MARG-01 | 33-01…33-05 | Profit margin per job/trade scope | ✓ SATISFIED | E2E tests 1-5; web/mobile render + gating tests |
| MARG-02 | 33-02…33-05 | Project-level margin rollup across trades | ✓ SATISFIED | E2E tests 6-9 (D-12 traversal, mixed basis, D-14 fallback); project surfaces wired on both clients |
| MARG-03 | 33-01…33-05 | Incomplete-data flag instead of misleading numbers | ✓ SATISFIED | Keystone test 10, tests 11-13; state-12 contract on web; flagged widget state on mobile |

No orphaned requirements: REQUIREMENTS.md maps exactly MARG-01/02/03 to Phase 33; every plan declares a subset of these three.

### Phase 30 D-06 Boundary

Zero `margin` references in `backend/app/features/invoices/router.py`, `backend/app/features/quotes/router.py`, and the entire `backend/app/features/reports/` feature. Invoice/quote schemas reference margin_math only for the shared document-total helpers (display totals, not margin data). Web and mobile invoice/quote/report features contain no MarginSummary usage. Boundary intact.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| mobile margin_summary_section.dart | 19, 87, 128 | `_absentFigurePlaceholder = '—'` | ℹ️ Info | Plan-specified defensive placeholder for the revenue-present/margin-null edge — not a stub |

No TODO/FIXME/stub patterns, no `float(` in money code, no bare `as` casts, no dead code found in phase files.

### Human Verification Required

None. 33-VALIDATION.md declares all verification items automatable; visual polish is deferred to the UI-SPEC checker. All copywriting, color (destructive negatives, amber chip), and gating behaviors are asserted by automated tests.

### Gaps Summary

None. All 29 must-have truths verified against the codebase; all three ROADMAP success criteria observable through passing DB-backed integration tests and client-side rendering tests; the D-06 boundary is intact; no regressions across 74 prior-phase tests.

---

_Verified: 2026-07-27_
_Verifier: Claude (gsd-verifier)_
