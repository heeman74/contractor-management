---
phase: 17
slug: crm-clients-and-contractors
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 17 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Playwright (web E2E) + pytest 7.x (backend) |
| **Config file** | `web/playwright.config.ts` / `backend/pyproject.toml` |
| **Quick run command** | `cd web && npx playwright test --grep "phase-17"` |
| **Full suite command** | `cd web && npx playwright test && cd ../backend && uv run python -m pytest tests/` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd web && npx playwright test --grep "phase-17"`
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 17-01-01 | 01 | 1 | CRM-01 | E2E | `npx playwright test clients-list` | ❌ W0 | ⬜ pending |
| 17-02-01 | 02 | 2 | CRM-02 | E2E | `npx playwright test clients-detail` | ❌ W0 | ⬜ pending |
| 17-03-01 | 03 | 1 | CONTR-01 | E2E | `npx playwright test contractors-list` | ❌ W0 | ⬜ pending |
| 17-04-01 | 04 | 2 | CONTR-02 | E2E | `npx playwright test contractors-profile` | ❌ W0 | ⬜ pending |
| 17-05-01 | 05 | 3 | CONTR-03, CONTR-04 | E2E | `npx playwright test schedule-editor` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `web/e2e/phase-17-clients-list.spec.ts` — stubs for CRM-01
- [ ] `web/e2e/phase-17-clients-detail.spec.ts` — stubs for CRM-02
- [ ] `web/e2e/phase-17-contractors-list.spec.ts` — stubs for CONTR-01
- [ ] `web/e2e/phase-17-contractors-profile.spec.ts` — stubs for CONTR-02
- [ ] `web/e2e/phase-17-schedule-editor.spec.ts` — stubs for CONTR-03, CONTR-04
- [ ] `backend/tests/test_crm_router.py` — stubs for CRM router endpoints

*Existing infrastructure covers Playwright and pytest — no new framework install needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Schedule editor drag-to-paint feels responsive | CONTR-03 | Pointer interaction quality is subjective | Paint several time blocks, verify visual feedback is smooth |
| Availability badge colors are visually distinct | CONTR-01 | Color perception is visual-only | View contractor list with mixed availability states |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
