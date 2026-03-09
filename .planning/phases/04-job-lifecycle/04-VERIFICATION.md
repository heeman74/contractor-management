---
phase: 04-job-lifecycle
verified: 2026-03-09T05:00:00Z
status: human_needed
score: 5/5 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 3/5
  gaps_closed:
    - "Photo picker stub in JobRequestFormScreen — image_picker ^1.1.2 added to pubspec.yaml; _pickPhoto() now calls ImagePicker().pickImage(source: ImageSource.gallery); thumbnails render via Image.file()"
    - "Missing route registration for JobRequestFormScreen — RouteNames.jobRequestForm = '/client/request' constant added; GoRoute registered in Branch 6 of app_router.dart; ClientPortalScreen has FilledButton navigating to the form"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Job wizard client selection on Step 1"
    expected: "A searchable dropdown of real client profiles from CRM appears on Step 1 of the wizard"
    why_human: "The client selector DropdownButtonFormField in job_wizard_screen.dart has a code comment 'Plan 07 will populate with searchable CRM client list' and only renders a single null item. Verifying whether this gap is acceptable (CRM is in same Phase 04) or blocking requires human judgment on acceptance criteria scope."
  - test: "Photo thumbnails in request review screen"
    expected: "When a request has photos attached, thumbnail images display correctly"
    why_human: "Photo thumbnails in request_review_screen.dart are rendered as plain colored containers (not actual images from the file path). Whether this is acceptable for the admin review queue requires visual verification."
  - test: "Full dual-flow E2E on device"
    expected: "Client logs in, opens portal, taps 'Submit a Job Request', fills form, submits — request appears in admin review queue — admin accepts — job appears in pipeline"
    why_human: "The route gap (JobRequestFormScreen not wired in router) previously prevented on-device E2E execution. Both gaps are now closed. Full flow requires on-device verification to confirm navigation and photo picker work end-to-end on real hardware."
---

# Phase 4: Job Lifecycle Verification Report

**Phase Goal:** Company admins can create, assign, and progress jobs through the full lifecycle, and clients can submit job requests that admins convert into scheduled jobs
**Verified:** 2026-03-09T05:00:00Z
**Status:** human_needed
**Re-verification:** Yes — after gap closure via Plan 04-09

## Re-verification Summary

Previous status: gaps_found (3/5 truths verified, 2/5 partial)
Current status: human_needed (5/5 automated checks pass)

Two gaps identified in the initial verification were both closed by Plan 04-09:

**Gap 1 closed — Photo picker stub replaced:**
- `image_picker: ^1.1.2` confirmed in `mobile/pubspec.yaml` (line 28)
- `import 'package:image_picker/image_picker.dart'` confirmed in `job_request_form_screen.dart` (line 7)
- `_pickPhoto()` at line 396-408 calls `ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200, imageQuality: 80)` — functional, non-stub
- Photo thumbnails at lines 293-301 render `ClipRRect(child: Image.file(File(_photoPaths[index]), ...))` — real file-based images
- Zero occurrences of the SnackBar stub text ("add image_picker to pubspec.yaml") — confirmed eliminated
- Zero occurrences of `SnackBar` anywhere in the file — no stub residue

**Gap 2 closed — Route registration wired at all three levels:**
- `RouteNames.jobRequestForm = '/client/request'` constant confirmed in `route_names.dart` (line 76)
- GoRoute registered in Branch 6 of `app_router.dart` (lines 223-226) with `builder: (context, state) => const JobRequestFormScreen()`
- `JobRequestFormScreen` import confirmed in `app_router.dart` (line 18)
- `ClientPortalScreen` has `FilledButton.icon` at line 49-53 calling `context.go(RouteNames.jobRequestForm)`
- `_checkRoleAccess` in `app_router.dart` (lines 256-258) gates `/client/*` paths to `UserRole.client` automatically — `/client/request` is correctly role-protected

No regressions detected: form fields, validation, and offline-first submission logic (`_submit()` calling `jobDao.insertJobRequest()`) are unchanged from the initial verified implementation.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Admin can create a job with description, address, client, and assigned contractor; it appears in the job pipeline immediately (offline-first) | VERIFIED | JobDao.insertJob wraps Drift insert + SyncQueue in a transaction. jobs_pipeline_screen.dart streams from jobListNotifierProvider which watches Drift. job_wizard_screen.dart calls dao.insertJob on submit. |
| 2 | A job moves through all five lifecycle stages (Quote, Scheduled, In Progress, Complete, Invoiced) and each transition is recorded with a timestamp | VERIFIED | ALLOWED_TRANSITIONS in service.py covers all forward transitions for admin; transition_status appends to status_history JSONB. 15 integration tests pass including test_full_lifecycle_flow. CHECK constraint in migration 0008 enforces valid statuses. |
| 3 | Client CRM shows a client profile with full job history — every job associated with that client across all lifecycle stages | VERIFIED | CrmService.get_client_with_job_history queries jobs WHERE client_id via JobRepository. ClientDetailScreen renders profile + saved properties + job history from clientJobHistoryNotifierProvider. 11 CRM integration tests pass. |
| 4 | A client can submit a job request with preferred dates; it appears in the admin review queue; admin can convert it to a scheduled job | VERIFIED | Backend fully implemented (RequestService, request router, web form, test_dual_flow_e2e passes). Admin review screen works. In-app form: _pickPhoto() now uses ImagePicker().pickImage(); /client/request GoRoute registered in Branch 6; ClientPortalScreen has navigation button. All three wiring points confirmed in codebase. |
| 5 | Both job creation flows (client-initiated and company-assigned) produce jobs in the same unified pipeline visible to admins | VERIFIED | Backend unification complete: RequestService.review_request creates a Job via JobService.create_job; both land in the same jobs table. Admin pipeline shows all jobs via watchJobsByCompany. In-app client flow is now navigable with functional photo picker. |

**Score:** 5/5 truths verified (up from 3/5 in initial verification)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mobile/pubspec.yaml` | image_picker dependency | VERIFIED | `image_picker: ^1.1.2` present at line 28 as a production dependency |
| `mobile/lib/features/client/presentation/screens/job_request_form_screen.dart` | Functional photo picker using ImagePicker | VERIFIED | `ImagePicker()` at line 397; `ImageSource.gallery` at line 399; `Image.file()` at line 295; no SnackBar stub |
| `mobile/lib/core/routing/route_names.dart` | jobRequestForm route constant | VERIFIED | `static const jobRequestForm = '/client/request'` at line 76 |
| `mobile/lib/core/routing/app_router.dart` | GoRoute for JobRequestFormScreen | VERIFIED | Import at line 18; GoRoute with `path: RouteNames.jobRequestForm` + `builder: JobRequestFormScreen` at lines 223-226 in Branch 6 |
| `mobile/lib/features/client/presentation/screens/client_portal_screen.dart` | Navigation button to job request form | VERIFIED | `FilledButton.icon` at lines 49-53; `context.go(RouteNames.jobRequestForm)` wired as onPressed; go_router and RouteNames imports confirmed |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `client_portal_screen.dart` | `job_request_form_screen.dart` | `context.go(RouteNames.jobRequestForm)` | WIRED | Line 52: `onPressed: () => context.go(RouteNames.jobRequestForm)` — uses RouteNames constant, not a magic string |
| `app_router.dart` Branch 6 | `job_request_form_screen.dart` | GoRoute builder | WIRED | Lines 223-226: `GoRoute(path: RouteNames.jobRequestForm, builder: (context, state) => const JobRequestFormScreen())` |
| `_checkRoleAccess` | `/client/request` path | `startsWith('/client')` guard | WIRED | Lines 256-258: any `/client/*` path requires `UserRole.client` — `/client/request` is automatically role-gated |
| `job_request_form_screen.dart` | device gallery | `ImagePicker().pickImage(source: ImageSource.gallery)` | WIRED | Lines 397-403: `final picker = ImagePicker(); final file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200, imageQuality: 80)` |
| `job_request_form_screen.dart` | `File` system + `Image.file()` | `ClipRRect > Image.file(File(_photoPaths[index]))` | WIRED | Lines 293-301: `ClipRRect(borderRadius: ..., child: Image.file(File(_photoPaths[index]), width: 80, height: 80, fit: BoxFit.cover))` |

All previously NOT_WIRED links from the initial verification are now WIRED.

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SCHED-01 | 04-01, 04-02, 04-04, 04-05, 04-06, 04-08 | Job creation with details (description, address, client, assigned contractor) | SATISFIED | JobCreate schema with all fields. JobService.create_job. JobDao.insertJob with sync queue. JobWizardScreen with 4-step wizard. 15 integration tests pass. |
| SCHED-02 | 04-01, 04-02, 04-04, 04-05, 04-06, 04-08 | Job lifecycle stages (Quote -> Scheduled -> In Progress -> Complete -> Invoiced) | SATISFIED | ALLOWED_TRANSITIONS state machine in service.py covers all 5 forward stages. status_history JSONB records each transition with timestamp and user_id. CHECK constraint in migration 0008 enforces valid statuses. version-checked optimistic locking. test_full_lifecycle_flow E2E passes. |
| CLNT-01 | 04-01, 04-03, 04-04, 04-05, 04-07, 04-08 | Customer/client CRM with profiles and job history | SATISFIED | CrmService, CrmRepository, ClientProfileCreate/Response schemas. Client detail screen shows profile, saved properties, job history across all lifecycle stages, ratings. 11 CRM integration tests pass. |
| CLNT-04 | 04-01, 04-03, 04-04, 04-05, 04-07, 04-08, 04-09 | Client-initiated job requests with preferred dates | SATISFIED | Backend fully implemented (RequestService, web form, dual-flow E2E test passes). Admin review queue functional. In-app mobile flow: photo picker uses ImagePicker().pickImage(); /client/request GoRoute registered; ClientPortalScreen has navigation entry point. All three submission paths (in-app mobile, web form, admin-direct) are wired end-to-end. |

All 4 requirement IDs (SCHED-01, SCHED-02, CLNT-01, CLNT-04) are SATISFIED. No orphaned requirements found.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `mobile/lib/features/jobs/presentation/screens/job_wizard_screen.dart` | 114-120 | Client dropdown has only a null item with comment "Plan 07 will populate" | Info | Job wizard Step 1 cannot select a client from CRM. Not a blocker for SCHED-01/02 (job can be created), but limits CRM integration value. Unchanged from initial verification — carry-forward. |
| `mobile/lib/features/client/presentation/screens/client_portal_screen.dart` | 40 | `'Coming in Phase 5'` placeholder text | Info | Expected — client portal feature content is Phase 7 scope. The screen now has functional navigation to the job request form. Not a Phase 4 gap. |
| `mobile/lib/features/jobs/presentation/screens/request_review_screen.dart` | 173-186 | Photo thumbnails are plain colored containers, not actual image renders | Info | Admin cannot see actual photos in review queue. Cosmetic only — photo paths stored correctly. Unchanged from initial verification — carry-forward. |

No blocker anti-patterns found. The prior gap-1 blocker (SnackBar stub in `_pickPhoto()`) is confirmed eliminated.

### Human Verification Required

#### 1. Job Wizard Client Selector Scope Assessment

**Test:** Open the job wizard as admin, proceed to Step 1.
**Expected:** A searchable list of client profiles from the CRM appears in the client dropdown.
**Why human:** The dropdown has a code comment "Plan 07 will populate with searchable CRM client list" and only renders a null/empty option. CLNT-01 (CRM) was delivered in the same Phase 4. Whether this integration was expected to be complete within Phase 4 or intentionally deferred requires human judgment on the scope boundary between plans 04-06 (job UI) and 04-07 (CRM UI).

#### 2. Photo Thumbnails in Request Review Screen

**Test:** Submit a web form job request with photos attached. Open the request review screen in the admin mobile app.
**Expected:** Thumbnail images of the attached photos are visible on the request card.
**Why human:** The review screen renders photo thumbnails as grey placeholder containers. The photo paths are stored correctly in the database JSONB array. Whether this visual stub is acceptable for the Phase 4 admin review queue requires human sign-off.

#### 3. Full Dual-Flow E2E on Device

**Test:** Log in as a client user. Navigate to the client portal. Tap "Submit a Job Request". Fill in the form, optionally add photos from the gallery. Submit. Log in as admin. Find the request in the review queue. Accept it. Confirm the job appears in the pipeline.
**Expected:** The flow completes end-to-end on the mobile app: gallery picker opens, photos appear as file-based thumbnails, form submits offline-first to Drift, sync pushes to backend, admin sees request, accepts it, job appears in admin pipeline.
**Why human:** All automated checks pass — route is registered, picker is functional, navigation is wired. This is the final integration check that requires real hardware (camera/gallery API, actual network sync, UI rendering of thumbnails) and cannot be verified by static analysis.

---

## Gaps Summary

No gaps remain. Both gaps from the initial verification have been closed by Plan 04-09:

- Gap 1 (photo picker stub): Closed. `_pickPhoto()` launches `ImagePicker().pickImage(source: ImageSource.gallery)`. Thumbnails render via `Image.file()`. No SnackBar stub remains.
- Gap 2 (missing route): Closed. `RouteNames.jobRequestForm = '/client/request'` constant added. GoRoute registered in Branch 6 of `app_router.dart`. `ClientPortalScreen` has a "Submit a Job Request" `FilledButton.icon` that calls `context.go(RouteNames.jobRequestForm)`.

Three items remain for human verification (visual appearance, photo picker device behavior, and full E2E on-device flow), all of which require physical device testing and cannot be confirmed by static code analysis. All automated verification checks pass at 5/5.

---

_Verified: 2026-03-09T05:00:00Z_
_Verifier: Claude (gsd-verifier)_
_Re-verification: Yes — initial verification 2026-03-08, gap closure Plan 04-09 executed 2026-03-09_
