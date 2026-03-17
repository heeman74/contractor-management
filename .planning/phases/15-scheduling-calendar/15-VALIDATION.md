---
phase: 15
slug: scheduling-calendar
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Playwright (installed, configured) |
| **Config file** | `web/playwright.config.ts` |
| **Quick run command** | `npx playwright test tests/schedule.spec.ts --project=chromium` |
| **Full suite command** | `npx playwright test --project=chromium` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npx playwright test tests/schedule.spec.ts --project=chromium`
- **After every plan wave:** Run `npx playwright test --project=chromium`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | SCHED-01 | E2E | `npx playwright test tests/schedule.spec.ts --project=chromium` | ❌ W0 | ⬜ pending |
| 15-01-02 | 01 | 1 | SCHED-01 | E2E | same | ❌ W0 | ⬜ pending |
| 15-01-03 | 01 | 1 | SCHED-01 | E2E | same | ❌ W0 | ⬜ pending |
| 15-02-01 | 02 | 2 | SCHED-02 | E2E | same | ❌ W0 | ⬜ pending |
| 15-02-02 | 02 | 2 | SCHED-02 | E2E | same | ❌ W0 | ⬜ pending |
| 15-02-03 | 02 | 2 | SCHED-02 | E2E | same | ❌ W0 | ⬜ pending |
| 15-03-01 | 03 | 2 | SCHED-03 | E2E | same | ❌ W0 | ⬜ pending |
| 15-03-02 | 03 | 2 | SCHED-03 | E2E | same | ❌ W0 | ⬜ pending |
| 15-03-03 | 03 | 2 | SCHED-03 | E2E | same | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `web/tests/schedule.spec.ts` — E2E stubs for SCHED-01, SCHED-02, SCHED-03 (stub with `test.skip()`)

*Playwright framework already installed and configured. No new framework setup needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Drag-and-drop feels snappy with 15-min snap | SCHED-02 | Visual/haptic feel cannot be automated | Drag a booking on the calendar, verify smooth 15-min snapping |
| Booking block overflow renders readably | SCHED-01 | Visual aesthetic judgment | Check short booking blocks with long titles |
| Touch drag-and-drop on tablet | SCHED-02 | Requires real touch device | Test on iPad/Android tablet |
| Current time red line updates live | SCHED-01 | Real-time visual update | Watch "now" line for 60+ seconds |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
