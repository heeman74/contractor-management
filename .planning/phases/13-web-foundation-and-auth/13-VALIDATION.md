---
phase: 13
slug: web-foundation-and-auth
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-15
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest (backend integration) + Playwright (web E2E) |
| **Config file** | `backend/pytest.ini` (existing) / `web/playwright.config.ts` (Wave 0) |
| **Quick run command (backend)** | `cd backend && uv run python -m pytest tests/integration/test_phase_13_e2e.py -x` |
| **Quick run command (web)** | `cd web && npx playwright test --project=chromium` |
| **Full suite command** | `cd backend && uv run python -m pytest && cd ../web && npx playwright test` |
| **Estimated runtime** | ~30 seconds (backend) + ~45 seconds (Playwright) |

---

## Sampling Rate

- **After every task commit:** Run `cd backend && uv run python -m pytest tests/integration/test_phase_13_e2e.py -x`
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 75 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 13-01-01 | 01 | 1 | AUTH-01 | integration | `uv run python -m pytest tests/integration/test_phase_13_e2e.py::test_login_success -x` | ❌ W0 | ⬜ pending |
| 13-01-02 | 01 | 1 | AUTH-03 | integration | `uv run python -m pytest tests/integration/test_phase_13_e2e.py::test_token_refresh -x` | ❌ W0 | ⬜ pending |
| 13-01-03 | 01 | 1 | AUTH-04 | integration | `uv run python -m pytest tests/integration/test_phase_13_e2e.py::test_logout -x` | ❌ W0 | ⬜ pending |
| 13-02-01 | 02 | 1 | — | smoke | `cd web && npm run build` | ❌ W0 | ⬜ pending |
| 13-03-01 | 03 | 2 | AUTH-01 | E2E | `npx playwright test --grep "login success"` | ❌ W0 | ⬜ pending |
| 13-03-02 | 03 | 2 | AUTH-02 | E2E | `npx playwright test --grep "session persists"` | ❌ W0 | ⬜ pending |
| 13-03-03 | 03 | 2 | AUTH-03 | E2E | `npx playwright test --grep "transparent refresh"` | ❌ W0 | ⬜ pending |
| 13-03-04 | 03 | 2 | AUTH-04 | E2E | `npx playwright test --grep "logout redirect"` | ❌ W0 | ⬜ pending |
| 13-04-01 | 04 | 2 | AUTH-05 | E2E | `npx playwright test --grep "sidebar visible"` | ❌ W0 | ⬜ pending |
| 13-04-02 | 04 | 2 | AUTH-05 | E2E | `npx playwright test --grep "sidebar collapse"` | ❌ W0 | ⬜ pending |
| 13-04-03 | 04 | 2 | AUTH-06 | E2E | `npx playwright test --grep "login error"` | ❌ W0 | ⬜ pending |
| 13-04-04 | 04 | 2 | AUTH-06 | E2E | `npx playwright test --grep "toast error"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `backend/tests/integration/test_phase_13_e2e.py` — stubs for AUTH-01 login, AUTH-03 refresh, AUTH-04 logout
- [ ] `web/playwright.config.ts` — Playwright config pointing to `http://localhost:3000`
- [ ] `web/tests/auth.spec.ts` — E2E tests for AUTH-01 through AUTH-04 login/session/logout flows
- [ ] `web/tests/layout.spec.ts` — E2E tests for AUTH-05 sidebar, AUTH-06 error handling
- [ ] Playwright install: `cd web && npx playwright install chromium`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Login page visual design (gradient, branding) | AUTH-01 | Aesthetic/visual check | Open /login, verify split-screen layout with blue gradient and branding |
| Skeleton screen shapes match content layout | AUTH-05 | Visual fidelity | Navigate between pages, verify skeleton shapes are correct |
| NProgress bar visibility during route transitions | AUTH-05 | Animation timing | Click sidebar links, verify thin top progress bar appears |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 75s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
