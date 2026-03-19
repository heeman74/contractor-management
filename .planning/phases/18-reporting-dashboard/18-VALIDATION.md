---
phase: 18
slug: reporting-dashboard
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 18 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (web)** | Playwright 1.58.2 |
| **Config file (web)** | `web/playwright.config.ts` |
| **Framework (backend)** | pytest + anyio |
| **Config file (backend)** | `backend/tests/conftest.py` |
| **Quick run command (web)** | `cd web && npx playwright test tests/phase-18-reports.spec.ts --project=chromium` |
| **Quick run command (backend)** | `cd backend && uv run python -m pytest tests/test_phase_18_e2e.py -x` |
| **Full suite command** | `cd web && npm run test-e2e && cd ../backend && uv run python -m pytest` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd web && npx playwright test tests/phase-18-reports.spec.ts --project=chromium`
- **After every plan wave:** Run `cd web && npm run test-e2e && cd ../backend && uv run python -m pytest tests/test_phase_18_e2e.py -x`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 18-01-01 | 01 | 1 | RPT-01 | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "four chart sections"` | ❌ W0 | ⬜ pending |
| 18-01-02 | 01 | 1 | RPT-01 | Backend integration | `uv run python -m pytest tests/test_phase_18_e2e.py::TestDashboard -x` | ❌ W0 | ⬜ pending |
| 18-01-03 | 01 | 1 | RPT-01 | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "revenue chart"` | ❌ W0 | ⬜ pending |
| 18-01-04 | 01 | 1 | RPT-01 | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "jobs chart"` | ❌ W0 | ⬜ pending |
| 18-01-05 | 01 | 1 | RPT-01 | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "quote conversion"` | ❌ W0 | ⬜ pending |
| 18-02-01 | 02 | 1 | RPT-02 | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "date preset 7d"` | ❌ W0 | ⬜ pending |
| 18-02-02 | 02 | 1 | RPT-02 | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "ytd preset"` | ❌ W0 | ⬜ pending |
| 18-02-03 | 02 | 1 | RPT-02 | Backend integration | `uv run python -m pytest tests/test_phase_18_e2e.py::TestDateFilter -x` | ❌ W0 | ⬜ pending |
| 18-03-01 | 03 | 2 | RPT-03 | Playwright E2E | `npx playwright test tests/phase-18-reports.spec.ts -k "heatmap grid"` | ❌ W0 | ⬜ pending |
| 18-03-02 | 03 | 2 | RPT-03 | Backend integration | `uv run python -m pytest tests/test_phase_18_e2e.py::TestHeatmap -x` | ❌ W0 | ⬜ pending |
| 18-03-03 | 03 | 2 | RPT-03 | Backend integration | `uv run python -m pytest tests/test_phase_18_e2e.py::TestHeatmapEmptyContractor -x` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `web/tests/phase-18-reports.spec.ts` — Playwright E2E stubs for RPT-01, RPT-02, RPT-03
- [ ] `backend/tests/test_phase_18_e2e.py` — backend integration tests for `/dashboard` date filtering and `/utilization-heatmap`

*Test infrastructure (Playwright, pytest) already exists from prior phases.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Chart animations render smoothly | RPT-01 | Animation frame rate not programmatically verifiable | Load /reports, observe bar/line/pie animation on first load |
| Heatmap color gradient visually distinguishable | RPT-03 | Color perception is visual | Inspect green→yellow→red cells with varying utilization values |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
