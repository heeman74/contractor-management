---
phase: 33
slug: profit-margin-tracking
status: planned
nyquist_compliant: true
wave_0_complete: false
per_task_map_complete: true
created: 2026-07-27
---

# Phase 33 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from 33-RESEARCH.md § Validation Architecture. The per-task map is
> completed by the planner (task IDs assigned at plan time).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Backend framework** | pytest (asyncio_mode=auto, testpaths=["tests"], config in `backend/pyproject.toml`; fixtures `seed_two_tenants`, tenant clients in `conftest.py`) |
| **Backend quick run** | `cd backend && .venv/bin/pytest tests/test_phase_33_e2e.py -x -q` |
| **Backend full suite** | `cd backend && .venv/bin/pytest` |
| **Web framework** | Jest 30 (`web/jest.config.ts`) + Playwright 1.58 (`web/playwright.config.ts`, specs in `web/tests/`) |
| **Web quick run** | `cd web && npm test -- cost-breakdown && npx playwright test tests/phase-33-margin.spec.ts --project=chromium` |
| **Web full suite** | `cd web && npm test && npm run test-e2e:chromium` |
| **Mobile framework** | flutter_test + mocktail (`mobile/test/`, E2E in `mobile/test/e2e/`) |
| **Mobile quick run** | `cd mobile && flutter test test/e2e/phase_33_margin_e2e_test.dart` |
| **Mobile full suite** | `cd mobile && flutter test` |
| **Estimated runtime** | ~30s per-task quick runs |

---

## Sampling Rate

- **After every task commit:** the task's own test file (`.venv/bin/pytest tests/test_phase_33_e2e.py -x -q` for backend tasks; `npm test -- <pattern>` / `flutter test <file>` for frontend tasks) + platform linters (`ruff check`, `npx tsc --noEmit`, `dart analyze`).
- **After every plan wave:** full backend `pytest` + `flutter test` + `npm test`.
- **Before `/gsd:verify-work`:** all three full suites + Playwright chromium green.
- **Max feedback latency:** ~30 seconds.

---

## Phase Requirements → Test Map

Per-task map completed at plan time (2026-07-27). "Created by" is the task that writes the test
file; "Green by" is the task whose verify command must exit 0.

| Req ID | Behavior | Test Type | Automated Command | Created by | Green by |
|--------|----------|-----------|-------------------|-----------|----------|
| MARG-01 | Pure margin math (percent rounding, zero revenue, negative margin, document_total discount/tax, D-01 resolution) | unit | `cd backend && .venv/bin/pytest tests/unit -k margin -x` | 33-01 T1 | 33-01 T2 |
| MARG-01 | Invoice/quote response totals unchanged after the shared-helper extraction | integration | `cd backend && .venv/bin/pytest tests/test_phase_16_e2e.py tests/test_phase_25_e2e.py tests/unit/test_quote_validation.py tests/test_project_quotes_e2e.py -q` | existing | 33-01 T3 |
| MARG-01 | Job/scope margin: invoiced revenue, latest-approved-quote fallback + basis, pre-tax revenue, $·% math, finance.view 403 for admin | integration | `cd backend && .venv/bin/pytest tests/test_phase_33_e2e.py -k "anchor or basis or forbidden" -x` | 33-02 T1 | 33-03 T1 |
| MARG-02 | Project rollup: same-traversal netting (mixed job/scope anchors), per-anchor D-01 resolution, D-14 project-level quote | integration | `cd backend && .venv/bin/pytest tests/test_phase_33_e2e.py -k traversal -x` | 33-02 T1 | 33-03 T2 |
| MARG-03 | Incomplete flag: unrated-labor trigger, legacy zero-cost keystone, D-07 no-revenue not flagged, project any-anchor propagation | integration | `cd backend && .venv/bin/pytest tests/test_phase_33_e2e.py -k "incomplete or legacy" -x` | 33-02 T1 | 33-03 T1 (anchor) · 33-03 T2 (project) |
| MARG-01/02/03 | No regression in the shipped cost/labor surfaces after the WorkSession + rate-fetch refactors | integration | `cd backend && .venv/bin/pytest tests/test_phase_31_e2e.py tests/test_phase_32_e2e.py tests/unit -q` | existing | 33-02 T2 |
| MARG-01/03 (web) | Margin section states 1-12 (invoiced/quoted/mixed/flagged/negative/percent-absent/no-revenue/absent) + `isBreakdownEmpty` state-12 contract | component (Jest) | `cd web && npm test -- cost-breakdown margin-summary` | 33-04 T2 | 33-04 T2 |
| MARG-01/02 (web) | Margin visible on job/scope/project pages for owner, absent without finance.view, keystone legacy job still rendered | E2E (Playwright) | `cd web && npx playwright test tests/phase-33-margin.spec.ts --project=chromium` | 33-04 T3 | 33-04 T3 |
| MARG-01/03 (mobile) | Tolerant `MarginSummary.tryFromJson` parse (present/absent/malformed/wrong types) | unit | `cd mobile && flutter test test/features/finance/margin_summary_parse_test.dart` | 33-05 T1 | 33-05 T1 |
| MARG-01/02/03 (mobile) | Margin rows + chip + captions + negative color render on job/scope/project variants; gated by financePermissionProvider | E2E (widget) | `cd mobile && flutter test test/e2e/phase_33_margin_e2e_test.dart` | 33-05 T3 | 33-05 T3 |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Every missing test file is created by a named task BEFORE the code it validates is written
(no task in this phase has a `<verify>` that points at a non-existent file):

- [ ] `backend/tests/unit/test_margin_math.py` — **33-01 Task 1** (RED before margin_math.py exists)
- [ ] `backend/tests/test_phase_33_e2e.py` — **33-02 Task 1** (RED; green in 33-03; reuses `seed_two_tenants`, tenant clients, and the phase-32 seed helpers)
- [ ] `web/src/features/finance/__tests__/margin-summary-section.test.tsx` — **33-04 Task 2** (written alongside the component, TDD task)
- [ ] `web/tests/phase-33-margin.spec.ts` — **33-04 Task 3** (login through UI then SPA-navigate — direct `page.goto` leaves permissions disabled, STATE.md 32-04 lesson)
- [ ] `mobile/test/features/finance/margin_summary_parse_test.dart` — **33-05 Task 1** (parser units, TDD task)
- [ ] `mobile/test/e2e/phase_33_margin_e2e_test.dart` — **33-05 Task 3** (MockDio at Dio level, ProviderScope overrides; Riverpod 3 `Override` via `flutter_riverpod/misc.dart`, STATE.md 32-05 lesson)
- Framework install: none — all harnesses already configured and in use.

Sampling continuity check: no plan has 3 consecutive tasks without an automated verify —
every task in 33-01…33-05 carries a runnable `<automated>` command.

---

## Manual-Only Verifications

None — all verification items automatable per CLAUDE.md UAT-automation rules (visual polish deferred to the UI-SPEC checker).

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planner-completed 2026-07-27 (per-task map assigned)
