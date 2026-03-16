---
phase: 14
slug: job-management
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Playwright 1.x (`@playwright/test`) |
| **Config file** | `web/playwright.config.ts` |
| **Quick run command** | `npm run test-e2e:chromium -- --grep "JOBS"` (from `web/`) |
| **Full suite command** | `npm run test-e2e` (from `web/`) |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `npm run test-e2e:chromium -- --grep "JOBS-0[1-4]"`
- **After every plan wave:** Run `npm run test-e2e`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 14-01-01 | 01 | 1 | JOBS-01 | E2E | `npm run test-e2e:chromium -- --grep "JOBS-01"` | ❌ W0 | ⬜ pending |
| 14-01-02 | 01 | 1 | JOBS-01 | E2E | `npm run test-e2e:chromium -- --grep "JOBS-01"` | ❌ W0 | ⬜ pending |
| 14-01-03 | 01 | 1 | JOBS-01 | E2E | `npm run test-e2e:chromium -- --grep "JOBS-01"` | ❌ W0 | ⬜ pending |
| 14-01-04 | 01 | 1 | JOBS-01 | E2E | `npm run test-e2e:chromium -- --grep "JOBS-01"` | ❌ W0 | ⬜ pending |
| 14-02-01 | 02 | 1 | JOBS-02 | E2E | `npm run test-e2e:chromium -- --grep "JOBS-02"` | ❌ W0 | ⬜ pending |
| 14-02-02 | 02 | 1 | JOBS-02 | E2E | `npm run test-e2e:chromium -- --grep "JOBS-02"` | ❌ W0 | ⬜ pending |
| 14-02-03 | 02 | 1 | JOBS-02 | E2E | `npm run test-e2e:chromium -- --grep "JOBS-02"` | ❌ W0 | ⬜ pending |
| 14-03-01 | 03 | 1 | JOBS-03 | E2E | `npm run test-e2e:chromium -- --grep "JOBS-03"` | ❌ W0 | ⬜ pending |
| 14-03-02 | 03 | 1 | JOBS-03 | E2E | `npm run test-e2e:chromium -- --grep "JOBS-03"` | ❌ W0 | ⬜ pending |
| 14-04-01 | 03 | 1 | JOBS-04 | E2E | `npm run test-e2e:chromium -- --grep "JOBS-04"` | ❌ W0 | ⬜ pending |
| 14-04-02 | 03 | 1 | JOBS-04 | E2E | `npm run test-e2e:chromium -- --grep "JOBS-04"` | ❌ W0 | ⬜ pending |
| 14-04-03 | 03 | 1 | JOBS-04 | E2E | `npm run test-e2e:chromium -- --grep "JOBS-04"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `web/tests/jobs.spec.ts` — E2E test stubs for JOBS-01 through JOBS-04 (12 test cases)
- [ ] `web/src/types/api.ts` — Update `Job` interface to match real `JobResponse` schema (remove `title`, add all actual fields)

*Existing infrastructure covers test runner and config.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Photo note lightbox renders correctly | JOBS-02 | Visual rendering quality | Open job with photo notes, click thumbnail, verify lightbox overlay |
| Responsive two-column layout collapses | JOBS-02 | Visual breakpoint behavior | Resize browser below 768px, verify sidebar stacks below main |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
