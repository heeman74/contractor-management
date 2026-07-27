---
phase: 32
slug: labor-rates-and-cost-rollup
status: planned
nyquist_compliant: true
wave_0_complete: true
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

Task IDs assigned at planning (2026-07-26). Every task's own `<verify><automated>` runs
the file listed here; no task depends on a test file created by a later task.

| Req ID | Behavior | Plan/Task | Test Type | Automated Command | File Created By |
|--------|----------|-----------|-----------|-------------------|-----------------|
| COST-05 | Rate resolution rule (boundary dates, created_at ties, future-dated, unrated, UTC work-day, half-up cents) | 32-01 T1 | unit (pure fn) | `cd backend && .venv/bin/python -m pytest tests/unit/test_labor_derivation.py -x -q` | 32-01 T1 |
| COST-04 | LaborRate schemas/repository/service import + construct cleanly | 32-01 T2 | unit | `cd backend && .venv/bin/python -m pytest tests/unit -x -q` | 32-01 T1 + existing |
| COST-04 | POST rate + effective date; history preserved & ordered; backdated & future-dated accepted; duplicate-day tie-break; 403 for admin/worker; unknown-user 404; RLS isolation | 32-01 T3 | integration | `cd backend && .venv/bin/python -m pytest tests/test_phase_32_e2e.py -k rate -x -q` | 32-01 T3 |
| COST-06 | Breakdown schema shapes: Decimal-as-string, `basis` default, rollup backward-compat | 32-02 T1 | unit | `cd backend && .venv/bin/python -m pytest tests/unit -x -q` | 32-02 T1 (extends test_finance_schemas.py) |
| COST-05 | Success criterion 2: later rate change leaves history unchanged; backdated rate fills unrated; active/deleted sessions excluded; project labor via jobs.project_id | 32-02 T2 | integration | `cd backend && .venv/bin/python -m pytest tests/test_phase_32_e2e.py -k derivation -x -q` | 32-02 T2 |
| COST-06 | Job/scope/project breakdowns: category totals, labor row, `labor_tracked_at_job_level`, grand_total, `total` backward-compat, 403 matrix, RLS isolation | 32-02 T2 | integration | `cd backend && .venv/bin/python -m pytest tests/test_phase_32_e2e.py -k breakdown -x -q` | 32-02 T2 |
| COST-06 | Reserved labor category rejected on create/update (422); legacy labor entries fold into the labor row | 32-02 T3 | integration | `cd backend && .venv/bin/python -m pytest tests/test_phase_32_e2e.py -k labor_category -x -q` | 32-02 T3 |
| COST-04 | RateHistoryDialog: headline, validation copy, empty state, superseded/future badges, tie-break helpers | 32-03 T1 | unit (Jest) | `cd web && npm test -- rate-history --watchAll=false` | 32-03 T1 |
| COST-04 | Team page Cost Rate column gated `finance.rates.manage`; batched current rates; add-rate POST payload; empty state | 32-03 T2 | E2E (Playwright) | `cd web && npx playwright test tests/phase-32-labor-rates.spec.ts` | 32-03 T2 |
| COST-06 | CostBreakdownSummary: row order, "{H} hrs unrated" badge, unburdened popover, trade-scope note, loading/error/empty states | 32-04 T1 | unit (Jest) | `cd web && npm test -- cost-breakdown --watchAll=false` | 32-04 T1 |
| COST-06 | Breakdown rendered on job/scope/project surfaces; Labor absent from AddCost picker | 32-04 T2 | E2E (Playwright) | `cd web && npx playwright test tests/phase-32-labor-rates.spec.ts` | 32-03 T2 (extended by 32-04 T2) |
| COST-06 | Mobile breakdown parsing: strict job/scope parse, tolerant optional rollup fields, FormatException cases | 32-05 T1 | unit | `cd mobile && flutter test test/unit/features/finance/cost_breakdown_parsing_test.dart` | 32-05 T1 |
| COST-06 | Mobile widget/providers/mounts + labor picker filter compile and pass unit suite | 32-05 T2 | unit + analyze | `cd mobile && flutter test test/unit/features/finance/ && dart analyze lib/features/finance lib/features/jobs lib/features/projects` | 32-05 T1 |
| COST-06 | Mobile phase E2E: breakdown render, unrated chip, unburdened caption, job-level note, offline state, gating, picker filter | 32-05 T3 | E2E (widget) | `cd mobile && flutter test test/e2e/phase_32_labor_cost_e2e_test.dart` | 32-05 T3 |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

No separate Wave 0 plan is needed. Per CLAUDE.md ("E2E test files MUST be created
alongside the feature code, not as a follow-up task"), every missing test file is
created by the same task that needs it, before that task's verify command runs:

- [x] `backend/tests/unit/test_labor_derivation.py` — created by 32-01 Task 1 (TDD: behaviors specified before implementation)
- [x] `backend/tests/test_phase_32_e2e.py` — created by 32-01 Task 3; extended by 32-02 Tasks 2 and 3 (sequential waves, no write conflict)
- [x] `web/src/app/(dashboard)/team/_components/__tests__/rate-history-dialog.test.tsx` — created by 32-03 Task 1
- [x] `web/tests/phase-32-labor-rates.spec.ts` — created by 32-03 Task 2 (Wave 2); extended by 32-04 Task 2 (Wave 3)
- [x] `web/src/features/finance/__tests__/cost-breakdown-summary.test.tsx` — created by 32-04 Task 1
- [x] `mobile/test/unit/features/finance/cost_breakdown_parsing_test.dart` — created by 32-05 Task 1
- [x] `mobile/test/e2e/phase_32_labor_cost_e2e_test.dart` — created by 32-05 Task 3
- Framework install: none — all four harnesses already configured and in use.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual polish of unburdened popover / caption placement | COST-06 (D-06) | Aesthetic/placement judgment on real renderer | Open job/scope/project cost sections on web + mobile; confirm the info affordance is discoverable and readable |

Everything else is automatable per CLAUDE.md UAT rules (mock Dio at `MockDioClient.instance`, seed Drift, assert rendering).

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies — 13/13 tasks carry an `<automated>` command
- [x] Sampling continuity: no 3 consecutive tasks without automated verify — every task verifies
- [x] Wave 0 covers all MISSING references — each missing file is created by the task that verifies against it
- [x] No watch-mode flags — Jest runs use `--watchAll=false`
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planner-completed 2026-07-26 (task IDs assigned)
