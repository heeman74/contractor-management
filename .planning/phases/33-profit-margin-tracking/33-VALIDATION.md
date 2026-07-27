---
phase: 33
slug: profit-margin-tracking
status: planned
nyquist_compliant: true
wave_0_complete: false
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

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MARG-01 | Job/scope margin: invoiced revenue, quote fallback + basis label, $·% math, finance.view 403 for admin/worker | integration | `.venv/bin/pytest tests/test_phase_33_e2e.py -k "anchor or basis or forbidden" -x` | ❌ Wave 0 |
| MARG-01 | Pure margin math (percent rounding, zero revenue, negative margin, document_total discount/tax) | unit | `.venv/bin/pytest tests/unit -k margin -x` | ❌ Wave 0 |
| MARG-02 | Project rollup: same-traversal netting (mixed job/scope anchors), per-anchor D-01 resolution, mixed basis | integration | `.venv/bin/pytest tests/test_phase_33_e2e.py -k traversal -x` | ❌ Wave 0 |
| MARG-03 | Incomplete flag: unrated-labor trigger, legacy zero-cost keystone, D-07 no-revenue not flagged, project any-anchor propagation | integration | `.venv/bin/pytest tests/test_phase_33_e2e.py -k "incomplete or legacy" -x` | ❌ Wave 0 |
| MARG-01/03 (web) | Margin row states (invoiced/quoted/flagged/no-revenue) in CostBreakdownSummary contexts | component (Jest) | `cd web && npm test -- cost-breakdown` | ✅ extend existing |
| MARG-01/02 (web) | Margin visible on job/scope/project pages for owner, absent without finance.view | E2E (Playwright) | `cd web && npx playwright test tests/phase-33-margin.spec.ts --project=chromium` | ❌ Wave 0 |
| MARG-01/03 (mobile) | Tolerant `MarginSummary.tryFromJson` parse (present/absent/malformed) | unit | `cd mobile && flutter test test/features/finance/` | ❌ Wave 0 |
| MARG-01/02/03 (mobile) | Margin row + chip + captions render on job/scope/project screens; gated by financePermissionProvider | E2E (widget) | `cd mobile && flutter test test/e2e/phase_33_margin_e2e_test.dart` | ❌ Wave 0 |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `backend/tests/test_phase_33_e2e.py` — MARG-01/02/03 integration (reuse seed helpers from `test_phase_25_e2e.py` / `test_phase_32_e2e.py`, `seed_two_tenants`, tenant clients)
- [ ] `backend/tests/unit/test_margin_math.py` — pure-math unit tests (DB-free, mirrors labor_derivation unit tests)
- [ ] `web/tests/phase-33-margin.spec.ts` — Playwright (login through UI then SPA-navigate — direct `page.goto` leaves permissions disabled, STATE.md Phase 32-04 lesson)
- [ ] `mobile/test/features/finance/margin_summary_parse_test.dart` — parser units
- [ ] `mobile/test/e2e/phase_33_margin_e2e_test.dart` — widget E2E (MockDio at Dio level, ProviderScope overrides; Riverpod 3 `Override` via `flutter_riverpod/misc.dart`, STATE.md 32-05 lesson)
- Framework install: none — all harnesses already configured and in use.

---

## Manual-Only Verifications

None — all verification items automatable per CLAUDE.md UAT-automation rules (visual polish deferred to the UI-SPEC checker).

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
