---
phase: 04
slug: job-lifecycle
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-08
---

# Phase 04 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Flutter test + pytest 7.x |
| **Config file** | `mobile/pubspec.yaml` (Flutter), `backend/pyproject.toml` (pytest) |
| **Quick run command** | `cd mobile && flutter test test/features/client/` |
| **Full suite command** | `cd mobile && flutter test && cd ../backend && uv run python -m pytest` |
| **Estimated runtime** | ~45 seconds (Flutter) + ~30 seconds (pytest) |

---

## Sampling Rate

- **After every task commit:** Run `cd mobile && flutter test test/features/client/`
- **After every plan wave:** Run `cd mobile && flutter test && cd ../backend && uv run python -m pytest`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 75 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01 | 09 | 1 | CLNT-04 | integration | `cd mobile && flutter test test/features/client/job_request_form_screen_test.dart` | ❌ W0 | ⬜ pending |
| 09-02 | 09 | 1 | CLNT-04 | integration | `cd mobile && flutter test test/features/client/job_request_form_screen_test.dart` | ❌ W0 | ⬜ pending |
| 09-03 | 09 | 1 | CLNT-04 | unit | `cd mobile && flutter test test/core/routing/app_router_test.dart` | ❌ W0 | ⬜ pending |
| 09-04 | 09 | 1 | CLNT-04 | widget | `cd mobile && flutter test test/features/client/client_portal_screen_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mobile/test/features/client/job_request_form_screen_test.dart` — tests for photo picker and form submission with photos
- [ ] `mobile/test/core/routing/app_router_test.dart` — route resolution tests for `/client/request`
- [ ] `mobile/test/features/client/client_portal_screen_test.dart` — navigation entry point test

*Existing test infrastructure covers backend requirements. Gap closure is purely Flutter mobile.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Photo picker launches on Android | CLNT-04 | Platform channel behavior unavailable in widget tests | Login as client → navigate to `/client/request` → tap "Add photos" → OS gallery picker opens |
| Full dual-flow E2E on device | CLNT-04 | Multi-session, multi-role flow requires real device | Client submits request with photo → admin reviews → accepts → job appears in pipeline |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 75s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
