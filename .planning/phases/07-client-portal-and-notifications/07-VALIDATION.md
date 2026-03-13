---
phase: 7
slug: client-portal-and-notifications
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-12
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest (backend) + flutter_test / mocktail (mobile) |
| **Config file** | `backend/pyproject.toml` (asyncio_mode=auto) |
| **Quick run command** | `cd backend && uv run python -m pytest tests/ -x -q` |
| **Full suite command** | `cd backend && uv run python -m pytest tests/ && cd ../mobile && flutter test` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd backend && uv run python -m pytest tests/ -x -q -m 'not slow'`
- **After every plan wave:** Run `cd backend && uv run python -m pytest tests/ && cd ../mobile && flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | CLNT-03 | E2E widget | `flutter test test/e2e/phase_7_client_portal_e2e_test.dart` | ❌ W0 | ⬜ pending |
| 07-02-01 | 02 | 1 | CLNT-03 | E2E widget | `flutter test test/e2e/phase_7_client_portal_e2e_test.dart` | ❌ W0 | ⬜ pending |
| 07-03-01 | 03 | 1 | CLNT-05 | E2E widget | `flutter test test/e2e/phase_7_client_portal_e2e_test.dart` | ❌ W0 | ⬜ pending |
| 07-04-01 | 04 | 2 | CLNT-02 | integration | `cd backend && uv run python -m pytest tests/test_phase_7_e2e.py -x` | ❌ W0 | ⬜ pending |
| 07-04-02 | 04 | 2 | CLNT-02 | unit | `flutter test test/features/notifications/fcm_token_test.dart` | ❌ W0 | ⬜ pending |
| 07-05-01 | 05 | 2 | CLNT-02, CLNT-03, CLNT-05 | E2E | `flutter test test/e2e/phase_7_client_portal_e2e_test.dart && cd backend && uv run python -m pytest tests/test_phase_7_e2e.py` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mobile/test/e2e/phase_7_client_portal_e2e_test.dart` — E2E stubs for CLNT-03, CLNT-05
- [ ] `backend/tests/test_phase_7_e2e.py` — integration test stubs for CLNT-02, CLNT-05 backend
- [ ] `backend/tests/test_notification_service.py` — unit test stubs for NotificationService
- [ ] Firebase project setup: `mobile/android/app/google-services.json` and `mobile/ios/Runner/GoogleService-Info.plist` (manual — download from Firebase Console)
- [ ] Backend env var: `GOOGLE_APPLICATION_CREDENTIALS` pointing to service account JSON
- [ ] `backend/firebase-service-account.json` added to `.gitignore`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Push notification appears in OS tray | CLNT-02 | Requires real device + FCM backend | Send test notification via Firebase Console; verify tray display |
| Notification tap deep-links to job | CLNT-02 | Requires real device cold/warm start | Tap notification from tray; verify correct job detail screen opens |
| Photo pinch-to-zoom visual quality | CLNT-03 | Visual/haptic check | Open photo viewer; pinch-to-zoom; verify smooth rendering |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
