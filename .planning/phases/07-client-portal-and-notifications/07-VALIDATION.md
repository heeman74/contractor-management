---
phase: 7
slug: client-portal-and-notifications
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-12
audited: 2026-03-14
---

# Phase 7 -- Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest (backend) + flutter_test / mocktail (mobile) |
| **Config file** | `backend/pyproject.toml` (asyncio_mode=auto) |
| **Quick run command** | `cd backend && uv run python -m pytest tests/test_notification_service.py tests/test_phase_7_e2e.py -x -q` |
| **Full suite command** | `cd backend && uv run python -m pytest tests/ && cd ../mobile && flutter test` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd backend && uv run python -m pytest tests/ -x -q -m 'not slow'`
- **After every plan wave:** Run `cd backend && uv run python -m pytest tests/ && cd ../mobile && flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Requirement Coverage Map

| Req ID | Requirement | Test Files | Test Count | Coverage |
|--------|-------------|------------|------------|----------|
| CLNT-02 | Push notifications on job milestones | `test_notification_service.py` (7), `test_phase_7_e2e.py` (8: dispatch on 4 transitions + token CRUD) | 15 | COVERED |
| CLNT-03 | Client portal with job detail, progress stepper, photos, notes | `phase_7_client_portal_e2e_test.dart` (19: portal list + job detail), `client_portal_screen_test.dart` | 19+ | COVERED |
| CLNT-05 | Delay visibility + sync role filtering for client | `test_phase_7_e2e.py` (4: sync filtering), `phase_7_client_portal_e2e_test.dart` (5: delay banner/indicator) | 9 | COVERED |

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | CLNT-02, CLNT-05 | integration | `cd backend && uv run python -m pytest tests/test_phase_7_e2e.py -x` | YES | green |
| 07-01-02 | 01 | 1 | CLNT-02 | unit | `cd backend && uv run python -m pytest tests/test_notification_service.py -x` | YES | green |
| 07-02-01 | 02 | 1 | CLNT-03, CLNT-05 | E2E widget | `cd mobile && flutter test test/e2e/phase_7_client_portal_e2e_test.dart` | YES | green |
| 07-02-02 | 02 | 1 | CLNT-03 | widget | `cd mobile && flutter test test/widget/features/client/client_portal_screen_test.dart` | YES | green |
| 07-03-01 | 03 | 2 | CLNT-02 | manual | N/A (Firebase device test) | N/A | manual |
| 07-04-01 | 04 | 2 | CLNT-02 | integration | `cd backend && uv run python -m pytest tests/test_phase_7_e2e.py -x` | YES | green |
| 07-04-02 | 04 | 2 | CLNT-03, CLNT-05 | E2E widget | `cd mobile && flutter test test/e2e/phase_7_client_portal_e2e_test.dart` | YES | green |

*Status: pending -- green -- red -- flaky*

---

## Test File Inventory

| File | Type | Tests | Status |
|------|------|-------|--------|
| `backend/tests/test_notification_service.py` | unit | 7 | green (per 07-04-SUMMARY) |
| `backend/tests/test_phase_7_e2e.py` | integration | 13 | green (per 07-04-SUMMARY) |
| `mobile/test/e2e/phase_7_client_portal_e2e_test.dart` | E2E widget | 24 | green (per 07-04-SUMMARY) |
| `mobile/test/widget/features/client/client_portal_screen_test.dart` | widget | exists | green |

**Total automated tests:** 44+

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Push notification appears in OS tray | CLNT-02 | Requires real device + FCM backend | Send test notification via Firebase Console; verify tray display |
| Notification tap deep-links to job | CLNT-02 | Requires real device cold/warm start | Tap notification from tray; verify correct job detail screen opens |
| Photo pinch-to-zoom visual quality | CLNT-03 | Visual/haptic check | Open photo viewer; pinch-to-zoom; verify smooth rendering |

---

## Validation Sign-Off

- [x] All tasks have automated verify or manual-only justification
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 requirements satisfied (test files exist and pass)
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** APPROVED

---

## Audit Trail

### Nyquist Audit -- 2026-03-14

**Auditor:** gsd-nyquist-auditor (Opus 4.6)
**Scope:** Phase 7 requirements CLNT-02, CLNT-03, CLNT-05

**Findings:**

1. **CLNT-02 (Push Notifications):** COVERED. Backend notification dispatch tested on all 4 job milestone transitions (scheduled, in_progress, complete, delayed) plus no-client guard. Token CRUD fully tested (register, upsert, unregistered cleanup). 15 automated tests across `test_notification_service.py` and `test_phase_7_e2e.py`. FCM deep-link and tray display correctly classified as manual-only (requires real device + Firebase project).

2. **CLNT-03 (Client Portal):** COVERED. 24 Flutter E2E widget tests cover: portal list with active jobs, ETA display, delay warning icon, completed job dimming, pending requests section, declined reason display, progress stepper stages, cancelled banner, photo timeline (count badge, empty state, uploaded-only filter), notes tab activity log, details tab content. Additional widget test file exists for `ClientPortalScreen`.

3. **CLNT-05 (Delay Visibility + Sync Filtering):** COVERED. Backend sync delta filtering tested: client sees own jobs only, client sees own notes only, admin sees all jobs. Flutter E2E tests verify delay banner visibility (shown for active delayed jobs, hidden for complete), multiple delays expandable, delay warning icon on portal cards.

**Coverage assessment:** All 3 requirements have automated test coverage. No gaps identified.

**Verification map updated:** Task IDs realigned to match actual plan/summary structure. File existence confirmed for all test files. Status set to green based on 07-04-SUMMARY reporting 20 backend + 24 Flutter tests passing.

**Result:** nyquist_compliant = true
