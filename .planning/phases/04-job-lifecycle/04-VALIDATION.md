---
phase: 04
slug: job-lifecycle
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-08
audited: 2026-03-14
---

# Phase 04 -- Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Flutter test + pytest 7.x |
| **Config file** | `mobile/pubspec.yaml` (Flutter), `backend/pyproject.toml` (pytest) |
| **Quick run command** | `cd backend && uv run python -m pytest tests/unit/test_state_machine.py tests/integration/test_job_lifecycle.py tests/integration/test_client_crm.py tests/integration/test_job_requests.py -v` |
| **Full suite command** | `cd mobile && flutter test && cd ../backend && uv run python -m pytest` |
| **Estimated runtime** | ~45 seconds (Flutter) + ~30 seconds (pytest) |

---

## Sampling Rate

- **After every task commit:** Run relevant test subset
- **After every plan wave:** Run `cd mobile && flutter test && cd ../backend && uv run python -m pytest`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 75 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-T1 | 01 | 1 | SCHED-01, SCHED-02, CLNT-01, CLNT-04 | integration | `cd backend && uv run alembic upgrade head` | yes | green |
| 04-01-T2 | 01 | 1 | SCHED-01, SCHED-02, CLNT-01, CLNT-04 | unit | `cd backend && uv run python -c "from app.features.jobs.models import Job, ClientProfile, JobRequest, Rating; print('OK')"` | yes | green |
| 04-02-T1 | 02 | 2 | SCHED-01, SCHED-02 | unit | `cd backend && uv run python -c "from app.features.jobs.repository import JobRepository; print('OK')"` | yes | green |
| 04-02-T2 | 02 | 2 | SCHED-01, SCHED-02 | unit | `cd backend && uv run python -m pytest tests/unit/test_state_machine.py -v` | yes | green |
| 04-03-T1 | 03 | 2 | CLNT-01 | unit | `cd backend && uv run python -c "from app.features.jobs.crm_service import CrmService; print('OK')"` | yes | green |
| 04-03-T2 | 03 | 2 | CLNT-04 | unit | `cd backend && uv run python -c "from app.features.jobs.request_service import RequestService; from app.features.jobs.rating_service import RatingService; print('OK')"` | yes | green |
| 04-04-T1 | 04 | 3 | SCHED-01, SCHED-02, CLNT-01, CLNT-04 | integration | `cd backend && uv run python -m pytest tests/integration/test_job_lifecycle.py -v` | yes | green |
| 04-04-T2 | 04 | 3 | SCHED-01, SCHED-02, CLNT-01, CLNT-04 | integration | `cd backend && uv run python -m pytest tests/integration/ -v` | yes | green |
| 04-05-T1 | 05 | 1 | SCHED-01, CLNT-01 | unit | `cd mobile && flutter test test/unit/features/schedule/booking_dao_test.dart` | yes | green |
| 04-05-T2 | 05 | 1 | SCHED-01, CLNT-01, CLNT-04 | unit | N/A (data layer; tested via widget/e2e tests) | yes | green |
| 04-06-T1 | 06 | 2 | SCHED-01, SCHED-02 | widget | `cd mobile && flutter test test/widget/features/jobs/jobs_pipeline_screen_test.dart` | yes | green |
| 04-06-T2 | 06 | 2 | SCHED-01, SCHED-02 | widget | `cd mobile && flutter test test/widget/features/jobs/` | yes | green |
| 04-07-T1 | 07 | 2 | CLNT-01 | widget | `cd mobile && flutter test test/widget/features/jobs/client_crm_screen_test.dart test/widget/features/jobs/client_detail_screen_test.dart` | yes | green |
| 04-07-T2 | 07 | 2 | CLNT-04 | widget | `cd mobile && flutter test test/widget/features/jobs/request_review_screen_test.dart test/widget/features/client/job_request_form_screen_test.dart` | yes | green |
| 04-08-T1 | 08 | 4 | SCHED-01, SCHED-02 | unit+integration | `cd backend && uv run python -m pytest tests/unit/test_state_machine.py tests/integration/test_job_lifecycle.py -v` | yes | green |
| 04-08-T2 | 08 | 4 | CLNT-01, CLNT-04 | integration | `cd backend && uv run python -m pytest tests/integration/test_client_crm.py tests/integration/test_job_requests.py -v` | yes | green |
| 04-09-T1 | 09 | 1 | CLNT-04 | widget | `cd mobile && flutter test test/widget/features/client/job_request_form_screen_test.dart` | yes | green |
| 04-09-T2 | 09 | 1 | CLNT-04 | widget | `cd mobile && flutter test test/widget/features/client/client_portal_screen_test.dart` | yes | green |

*Status: pending -- green -- red -- flaky*

---

## Requirement Coverage Matrix

| Requirement | Description | Backend Tests | Mobile Tests | Coverage |
|-------------|-------------|---------------|--------------|----------|
| SCHED-01 | Job creation, CRUD, full-text search | `test_job_lifecycle.py` (15 tests: create, get, list, search, update, soft delete, contractor isolation, full lifecycle E2E) | `jobs_pipeline_screen_test.dart`, `job_detail_screen_test.dart`, `job_wizard_client_selector_test.dart`, `job_wizard_selector_populated_test.dart`, `contractor_jobs_screen_test.dart`, `contractor_job_card_test.dart`, `phase_4_client_to_admin_flow_e2e_test.dart` | COVERED |
| SCHED-02 | Job lifecycle state machine (6 states, role-based transitions, version locking) | `test_state_machine.py` (8 tests: admin forward, admin backward, contractor allowed, contractor restricted, client no transitions, cancelled terminal, admin cancel from any, is_backward helper), `test_job_lifecycle.py` (transition tests: forward, backward requires reason, invalid rejected, version mismatch 409, cancel frees bookings) | `job_detail_screen_test.dart`, `contractor_jobs_screen_test.dart`, `phase_4_client_to_admin_flow_e2e_test.dart` | COVERED |
| CLNT-01 | Client CRM (profiles, saved properties, job history, ratings) | `test_client_crm.py` (11 tests: profile create, update, list with search, job history, add/remove/default property, create rating, rating before complete rejected, unique rating per direction, average rating calculation) | `client_crm_screen_test.dart`, `client_detail_screen_test.dart`, `phase_4_client_to_admin_flow_e2e_test.dart` | COVERED |
| CLNT-04 | Client job requests (in-app, web form, admin review, accept-to-job conversion) | `test_job_requests.py` (10 tests: in-app submit, web form submit, web form creates new client, web form matches existing, list pending, accept creates job, decline with reason, request info, web form renders HTML, dual-flow E2E) | `request_review_screen_test.dart`, `request_review_photos_test.dart`, `job_request_form_screen_test.dart`, `client_portal_screen_test.dart`, `phase_4_client_to_admin_flow_e2e_test.dart` | COVERED |

---

## Key Behavioral Tests Per Requirement

### SCHED-01: Job Creation and CRUD

| Test | File | Behavior Verified |
|------|------|-------------------|
| test_create_job | test_job_lifecycle.py | POST /jobs/ returns 201 with status='quote' and initial status_history |
| test_list_jobs_with_filters | test_job_lifecycle.py | GET /jobs/?status=quote returns only matching jobs |
| test_search_jobs | test_job_lifecycle.py | Full-text search on description returns ranked results |
| test_soft_delete_job | test_job_lifecycle.py | DELETE sets deleted_at; subsequent GET returns 404 |
| test_contractor_sees_own_jobs_only | test_job_lifecycle.py | Contractor A sees only jobs with contractor_id=A |
| test_full_lifecycle_flow | test_job_lifecycle.py | E2E: create -> schedule -> in_progress -> complete -> invoiced |

### SCHED-02: Job Lifecycle State Machine

| Test | File | Behavior Verified |
|------|------|-------------------|
| test_all_valid_admin_forward_transitions | test_state_machine.py | Admin can do quote->scheduled->in_progress->complete->invoiced |
| test_all_valid_contractor_transitions | test_state_machine.py | Contractor can only scheduled->in_progress and in_progress->complete |
| test_client_cannot_perform_any_transition | test_state_machine.py | Client role has empty frozenset for all statuses |
| test_cancelled_is_terminal | test_state_machine.py | No transitions from cancelled for any role |
| test_transition_backward_requires_reason | test_job_lifecycle.py | Backward without reason returns 422 |
| test_transition_version_mismatch | test_job_lifecycle.py | Stale version returns 409 |
| test_cancel_job_frees_bookings | test_job_lifecycle.py | Cancel sets booking.deleted_at via bulk UPDATE |

### CLNT-01: Client CRM

| Test | File | Behavior Verified |
|------|------|-------------------|
| test_create_client_profile | test_client_crm.py | POST creates profile with CRM fields |
| test_list_clients_with_search | test_client_crm.py | Search by name substring returns filtered results |
| test_client_job_history | test_client_crm.py | GET client includes their job history |
| test_add_saved_property | test_client_crm.py | Property links client to job_site |
| test_set_default_property | test_client_crm.py | Second default unsets first |
| test_create_rating | test_client_crm.py | Rating with 4 stars created after job completion |
| test_rating_rejected_before_complete | test_client_crm.py | Rating on quote-stage job returns 422 |
| test_average_rating_updated | test_client_crm.py | Two ratings produce correct average |

### CLNT-04: Client Job Requests

| Test | File | Behavior Verified |
|------|------|-------------------|
| test_submit_request_in_app | test_job_requests.py | POST /jobs/requests returns 201 with status='pending' |
| test_web_form_creates_new_client | test_job_requests.py | Anonymous email creates new User with client role |
| test_accept_request | test_job_requests.py | Accept creates Job at quote with pre-filled data |
| test_decline_request | test_job_requests.py | Decline stores reason and message |
| test_dual_flow_e2e | test_job_requests.py | Client request -> admin accept -> full lifecycle |
| test_web_form_renders | test_job_requests.py | GET returns HTML form |

---

## Mobile Widget/E2E Test Coverage

| Test File | Requirement | Behaviors Verified |
|-----------|-------------|-------------------|
| jobs_pipeline_screen_test.dart | SCHED-01 | Kanban view renders, list view toggle, filter chips |
| job_detail_screen_test.dart | SCHED-01, SCHED-02 | Tabbed detail (Details/Schedule/History), status chip, transition action |
| job_wizard_client_selector_test.dart | SCHED-01 | Client selection step in wizard |
| job_wizard_selector_populated_test.dart | SCHED-01 | Pre-populated wizard fields |
| contractor_jobs_screen_test.dart | SCHED-01, SCHED-02 | Contractor job list, Start Job / Complete Job buttons |
| contractor_job_card_test.dart | SCHED-01 | Job card rendering with status/priority |
| client_crm_screen_test.dart | CLNT-01 | Searchable client list, expandable cards |
| client_detail_screen_test.dart | CLNT-01 | Client profile, properties, job history tabs |
| request_review_screen_test.dart | CLNT-04 | Accept/Decline/Request Info actions, API calls |
| request_review_photos_test.dart | CLNT-04 | Photo thumbnails in review cards |
| job_request_form_screen_test.dart | CLNT-04 | Form fields, photo picker, submission |
| client_portal_screen_test.dart | CLNT-04 | Navigation to job request form |
| phase_4_client_to_admin_flow_e2e_test.dart | ALL | Full dual-flow E2E: client request -> admin review -> job pipeline |

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Photo picker launches on Android | CLNT-04 | Platform channel behavior unavailable in widget tests | Login as client -> navigate to /client/request -> tap "Add photos" -> OS gallery picker opens |
| Full dual-flow E2E on device | CLNT-04 | Multi-session, multi-role flow requires real device | Client submits request with photo -> admin reviews -> accepts -> job appears in pipeline |

---

## Validation Sign-Off

- [x] All tasks have automated verify commands or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] All requirements have COVERED status in coverage matrix
- [x] No watch-mode flags
- [x] Feedback latency < 75s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** passed

---

## Audit Trail

| Date | Auditor | Action | Result |
|------|---------|--------|--------|
| 2026-03-08 | gsd:validate-phase | Initial VALIDATION.md creation (draft, pending) | nyquist_compliant: false. Wave 0 items identified for CLNT-04 (photo picker stub, missing route). |
| 2026-03-09 | 04-09 execution | Gap closure: image_picker added, GoRoute registered, portal button added | CLNT-04 gaps closed. |
| 2026-03-14 | gsd-nyquist-auditor | Full audit of plans 01-09, summaries, and existing test files | All 4 requirements (SCHED-01, SCHED-02, CLNT-01, CLNT-04) COVERED. 44 backend tests (8 unit + 15 lifecycle + 11 CRM + 10 requests) + 13 mobile widget/E2E test files. Updated status to nyquist_compliant: true. |
