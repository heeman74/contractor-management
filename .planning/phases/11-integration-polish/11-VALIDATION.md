---
phase: 11
slug: integration-polish
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-14
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test + mocktail |
| **Config file** | none — flutter test auto-discovers |
| **Quick run command** | `cd mobile && flutter test test/e2e/phase_11_integration_polish_e2e_test.dart` |
| **Full suite command** | `cd mobile && flutter test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd mobile && flutter test test/e2e/phase_11_integration_polish_e2e_test.dart`
- **After every plan wave:** Run `cd mobile && flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 0 | SCHED-06, SCHED-08 | E2E stubs | `cd mobile && flutter test test/e2e/phase_11_integration_polish_e2e_test.dart` | ❌ W0 | ⬜ pending |
| 11-02-01 | 02 | 1 | SCHED-06 | unit | `cd mobile && flutter test test/e2e/phase_11_integration_polish_e2e_test.dart -N int01_field_names` | ❌ W0 | ⬜ pending |
| 11-02-02 | 02 | 1 | SCHED-06 | widget/E2E | `cd mobile && flutter test test/e2e/phase_11_integration_polish_e2e_test.dart -N int02_travel` | ❌ W0 | ⬜ pending |
| 11-02-03 | 02 | 1 | SCHED-08 | unit | `cd mobile && flutter test test/e2e/phase_11_integration_polish_e2e_test.dart -N int03_display_names` | ❌ W0 | ⬜ pending |
| 11-02-04 | 02 | 1 | SCHED-06 | E2E | `cd mobile && flutter test test/e2e/phase_11_integration_polish_e2e_test.dart -N e2e_coordinate_flow` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mobile/test/e2e/phase_11_integration_polish_e2e_test.dart` — stubs for INT-01, INT-02, INT-03 E2E tests
- [ ] Shared test fixtures: mock sync data with `latitude`/`longitude`, mock BookingEntity pairs, mock UserEntity for name resolution

*No new framework installs needed — mocktail, flutter_test, Drift in-memory already present.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| TravelTimeBlock visual appearance between bookings | SCHED-06 | Visual rendering fidelity (colors, spacing, animation) | Open calendar day view with 2+ consecutive bookings → verify travel buffer block appears between them with correct styling |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
