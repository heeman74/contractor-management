---
phase: 32
slug: labor-rates-and-cost-rollup
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-26
---

# Phase 32 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from 32-RESEARCH.md § Validation Architecture. The per-task map is
> completed by the planner (task IDs assigned at plan time).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Backend framework** | pytest + pytest-asyncio + httpx ASGI client (config in `backend/pyproject.toml`, fixtures in `backend/tests/conftest.py` — `seed_two_tenants`, `clean_tables`, JWT via `create_access_token`) |
| **Backend quick run** | `cd backend && .venv/bin/python -m pytest tests/test_phase_32_e2e.py -x -q` |
| **Backend full suite** | `cd backend && .venv/bin/python -m pytest` |
| **Web framework** | Jest (`web/jest.config.ts`, tests in `__tests__/` dirs) + Playwright (`web/playwright.config.ts`, specs in `web/tests/*.spec.ts`) |
| **Web quick run** | `cd web && npm test -- cost-breakdown && npx playwright test tests/phase-32-labor-rates.spec.ts` |
| **Web full suite** | `cd web && npm test && npx playwright test` |
| **Mobile framework** | flutter_test + mocktail + Drift in-memory; E2E in `mobile/test/e2e/` |
| **Mobile quick run** | `cd mobile && flutter test test/e2e/phase_32_labor_cost_e2e_test.dart` |
| **Mobile full suite** | `cd mobile && flutter test` |
| **Estimated runtime** | ~30s per-task quick runs |

---

## Sampling Rate

- **After every task commit:** the task's own test file (`pytest tests/test_phase_32_e2e.py -x -q` / `npm test -- <pattern>` / `flutter test <file>`) + platform linters (ruff / eslint+tsc / dart analyze).
- **After every plan wave:** full platform suite for the touched platform(s).
- **Before `/gsd:verify-work`:** all three full suites green + Playwright phase spec.
- **Max feedback latency:** ~30 seconds.

---

## Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| COST-04 | POST rate + effective date; history preserved & ordered; 403 for admin/worker; duplicate-day tie-break; future-dated allowed | integration | `pytest tests/test_phase_32_e2e.py -k rate -x` | ❌ Wave 0 |
| COST-04 | Team page rate column/dialog gated `finance.rates.manage`; history renders | unit (Jest) + E2E (Playwright) | `npm test -- rate-history` · `npx playwright test tests/phase-32-labor-rates.spec.ts` | ❌ Wave 0 |
| COST-05 | Rate resolution rule (boundary dates, ties, unrated, UTC work-day) | unit (pure fn) | `pytest tests/unit/test_labor_derivation.py -x` | ❌ Wave 0 |
| COST-05 | Success criterion 2: later rate change leaves history unchanged; backdated rate fills unrated; active sessions excluded | integration | `pytest tests/test_phase_32_e2e.py -k derivation -x` | ❌ Wave 0 |
| COST-06 | Job/scope/project breakdowns: category totals, labor row, `labor_tracked_at_job_level` on scopes, grand_total, `total` backward-compat, 403 matrix, RLS isolation | integration | `pytest tests/test_phase_32_e2e.py -k breakdown -x` | ❌ Wave 0 |
| COST-06 | Web breakdown rendering incl. "X hrs unrated" badge + unburdened popover + scope note | unit (Jest) + E2E (Playwright) | `npm test -- cost-breakdown` · Playwright spec above | ❌ Wave 0 |
| COST-06 | Mobile breakdown fetch/parse (tolerant optional fields) + widget render + offline state | unit + widget + E2E | `flutter test test/e2e/phase_32_labor_cost_e2e_test.dart` | ❌ Wave 0 |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `backend/tests/test_phase_32_e2e.py` — COST-04/05/06 integration (naming convention: `test_phase_{N}_e2e.py`; copy `_seed_cost_categories`/`_token` helpers from `test_phase_31_e2e.py`)
- [ ] `backend/tests/unit/test_labor_derivation.py` — pure rate-resolution unit tests (a `tests/unit/` dir exists)
- [ ] `web/src/features/finance/__tests__/` additions + `web/tests/phase-32-labor-rates.spec.ts` (Playwright; mirror `cost-capture.spec.ts` auth/nav approach)
- [ ] `mobile/test/e2e/phase_32_labor_cost_e2e_test.dart` (naming: `phase_{N}_{feature}_e2e_test.dart`)
- Framework install: none — all four harnesses already configured and in use.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual polish of unburdened popover / caption placement | COST-06 (D-06) | Aesthetic/placement judgment on real renderer | Open job/scope/project cost sections on web + mobile; confirm the info affordance is discoverable and readable |

Everything else is automatable per CLAUDE.md UAT rules (mock Dio at `MockDioClient.instance`, seed Drift, assert rendering).

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
