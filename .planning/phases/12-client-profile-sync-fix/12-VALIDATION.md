---
phase: 12
slug: client-profile-sync-fix
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-15
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Flutter test (flutter_test) + mocktail |
| **Config file** | mobile/pubspec.yaml (flutter_test in dev_dependencies) |
| **Quick run command** | `cd mobile && flutter test test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart` |
| **Full suite command** | `cd mobile && flutter test test/` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd mobile && flutter test test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart`
- **After every plan wave:** Run `cd mobile && flutter test test/`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 12-01-01 | 01 | 0 | CLNT-01 | E2E stub | `cd mobile && flutter test test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart` | ❌ W0 | ⬜ pending |
| 12-01-02 | 01 | 1 | CLNT-01 | E2E | `cd mobile && flutter test test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart` | ❌ W0 | ⬜ pending |
| 12-01-03 | 01 | 1 | CLNT-01 | E2E | `cd mobile && flutter test test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mobile/test/e2e/phase_12_client_profile_sync_fix_e2e_test.dart` — stubs for CLNT-01 sync push scenarios (CREATE and UPDATE)

*Existing infrastructure covers framework setup — mocktail and flutter_test already in project.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
