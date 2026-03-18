---
phase: 16
slug: quotes-and-invoices
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Playwright 1.58.2 (web E2E) + pytest (backend integration) |
| **Config file** | `web/playwright.config.ts` + `backend/pyproject.toml` |
| **Quick run command** | `cd web && npm run test-e2e:chromium -- --grep "phase-16"` |
| **Full suite command** | `cd web && npm run test-e2e && cd ../backend && uv run python -m pytest` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd web && npm run test-e2e:chromium -- --grep "phase-16" --reporter=line`
- **After every plan wave:** Run `cd web && npm run test-e2e:chromium`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 1 | QUOTE-01, INV-01, INV-02 | Integration (pytest) | `uv run python -m pytest tests/test_phase_16_e2e.py -x` | Will be created (real tests, not stubs) | ⬜ pending |
| 16-02-01 | 02 | 2 | QUOTE-01 | E2E (Playwright) | `npm run test-e2e:chromium -- --grep "quotes list"` | ❌ W0 | ⬜ pending |
| 16-02-02 | 02 | 2 | QUOTE-03, QUOTE-04 | E2E (Playwright) | `npm run test-e2e:chromium -- --grep "quote detail"` | ❌ W0 | ⬜ pending |
| 16-03-01 | 03 | 2 | INV-01 | E2E (Playwright) | `npm run test-e2e:chromium -- --grep "invoices list"` | ❌ W0 | ⬜ pending |
| 16-03-02 | 03 | 2 | INV-02, INV-03 | E2E (Playwright) | `npm run test-e2e:chromium -- --grep "invoice detail"` | ❌ W0 | ⬜ pending |
| 16-04-01 | 04 | 3 | QUOTE-02 | E2E (Playwright) | `npm run test-e2e:chromium -- --grep "quote builder"` | ❌ W0 | ⬜ pending |
| 16-BE-01 | 01 | 1 | Backend | Integration (pytest) | `uv run python -m pytest tests/test_phase_16_e2e.py -x` | Will be created (real tests) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `web/tests/phase-16-quotes.spec.ts` — stubs for QUOTE-01 through QUOTE-04
- [ ] `web/tests/phase-16-invoices.spec.ts` — stubs for INV-01 through INV-03
- [ ] `backend/tests/test_phase_16_e2e.py` — real integration tests (NOT stubs) for list endpoints, amount_paid migration, payment recording

*Existing infrastructure covers test framework setup.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| PDF renders with correct layout/fonts | QUOTE-04, INV-03 | Visual verification of PDF output | Download PDF, verify layout matches design spec |
| Drag-reorder line items feels smooth | QUOTE-02 | Haptic/UX feel | Create quote, drag rows, verify smooth animation |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
