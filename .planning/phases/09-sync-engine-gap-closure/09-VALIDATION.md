---
phase: 9
slug: sync-engine-gap-closure
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-14
audited: 2026-03-14
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test + mocktail (Flutter), pytest + httpx (Backend) |
| **Config file** | `mobile/` and `backend/` directories |
| **Quick run command** | `cd mobile && flutter test test/e2e/phase_9_sync_gap_closure_e2e_test.dart` |
| **Backend run command** | `cd backend && uv run python -m pytest tests/integration/test_phase_9_sync_e2e.py -x -v` |
| **Full suite command** | `cd mobile && flutter test test/ && cd ../backend && uv run python -m pytest tests/` |
| **Estimated runtime** | ~10 seconds (Flutter) + ~8 seconds (Backend) |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/e2e/phase_9_sync_gap_closure_e2e_test.dart`
- **After every plan wave:** Run `flutter test test/ && uv run python -m pytest backend/tests/`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | INFRA-04 | E2E | `cd mobile && flutter test test/e2e/phase_9_sync_gap_closure_e2e_test.dart` | YES | green |
| 09-01-02 | 01 | 1 | INFRA-04 (per-entity error handling) | E2E | same | YES | green |
| 09-01-03 | 01 | 1 | INFRA-04 (cursor update) | E2E | same | YES | green |
| 09-01-04 | 01 | 1 | FIELD-02 (GPS + FK fields) | E2E | same | YES | green |
| 09-01-05 | 01 | 1 | FIELD-02 (int lat/lng edge case) | E2E | same | YES | green |
| 09-01-06 | 01 | 1 | SCHED-03 (booking cross-device) | E2E | same | YES | green |
| 09-01-07 | 01 | 1 | SCHED-03 (booking soft-delete tombstone) | E2E | same | YES | green |
| 09-01-08 | 01 | 1 | BIZ-01 (quote + line items sync) | E2E | same | YES | green |
| 09-01-09 | 01 | 1 | BIZ-03 (invoice + line items sync) | E2E | same | YES | green |
| 09-01-10 | 01 | 1 | BIZ-01 (flat quote_line_items) | E2E | same | YES | green |
| 09-01-11 | 01 | 1 | BIZ-03 (flat invoice_line_items) | E2E | same | YES | green |
| 09-01-12 | 01 | 1 | INFRA-04 (attachment metadata) | E2E | same | YES | green |
| 09-02-01 | 02 | 2 | INFRA-04 (all 15 keys in response) | backend integration | `cd backend && uv run python -m pytest tests/integration/test_phase_9_sync_e2e.py -x -v` | YES | green |
| 09-02-02 | 02 | 2 | BIZ-01 (flat quote_line_items array) | backend integration | same | YES | green |
| 09-02-03 | 02 | 2 | BIZ-03 (flat invoice_line_items array) | backend integration | same | YES | green |
| 09-02-04 | 02 | 2 | FIELD-02 (GPS fields in job response) | backend integration | same | YES | green |

*Status: pending -- green -- red -- flaky*

---

## Requirement Coverage Summary

| Requirement | Tests | Coverage |
|-------------|-------|----------|
| INFRA-04 | 09-01-01, 09-01-02, 09-01-03, 09-01-12, 09-02-01 | COVERED (pullDelta loop, error handling, cursor, attachment, backend keys) |
| SCHED-03 | 09-01-06, 09-01-07 | COVERED (booking cross-device propagation + soft-delete tombstone) |
| FIELD-02 | 09-01-04, 09-01-05, 09-02-04 | COVERED (GPS/FK field mapping, int-vs-double edge case, backend response) |
| BIZ-01 | 09-01-08, 09-01-10, 09-02-02 | COVERED (quote sync, flat line items, backend flat array) |
| BIZ-03 | 09-01-09, 09-01-11, 09-02-03 | COVERED (invoice sync, flat line items, backend flat array) |

---

## Wave 0 Requirements

- [x] `mobile/test/e2e/phase_9_sync_gap_closure_e2e_test.dart` -- 13 tests covering INFRA-04, FIELD-02, BIZ-01, BIZ-03, SCHED-03
- [x] `backend/tests/integration/test_phase_9_sync_e2e.py` -- 4 tests covering backend endpoint verification (15 keys, flat arrays, GPS fields)

*Existing `conftest.py` fixtures cover shared test infrastructure.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** APPROVED

---

## Nyquist Audit Trail

**Auditor:** gsd-nyquist-auditor
**Date:** 2026-03-14
**Phase requirements:** INFRA-04, SCHED-03, FIELD-02, BIZ-01, BIZ-03

### Test Execution Results

| Test Suite | File | Tests | Result | Runner |
|------------|------|-------|--------|--------|
| Flutter E2E | `mobile/test/e2e/phase_9_sync_gap_closure_e2e_test.dart` | 13 | ALL PASSED | `cd mobile && flutter test test/e2e/phase_9_sync_gap_closure_e2e_test.dart` |
| Backend Integration | `backend/tests/integration/test_phase_9_sync_e2e.py` | 4 | ALL PASSED | `cd backend && uv run python -m pytest tests/integration/test_phase_9_sync_e2e.py -x -v` |

### Flutter E2E Test Details (13 passing)

1. `pullDelta persists all 15 entity types into Drift tables` -- INFRA-04
2. `pullDelta maps gpsLatitude, gpsLongitude, gpsAddress, quoteId, invoiceId` -- FIELD-02
3. `gps_latitude as int (not double) is handled via is num check` -- FIELD-02
4. `invalid job entity skipped; companies and users still inserted; cursor updated` -- INFRA-04
5. `cursor is null before pull, set to server_timestamp after` -- INFRA-04
6. `cursor updates on second pull with new server_timestamp` -- INFRA-04
7. `booking from sync response is persisted with correct fields` -- SCHED-03
8. `soft-deleted booking tombstone is propagated` -- SCHED-03
9. `quote and quote_line_items are persisted with correct FKs` -- BIZ-01
10. `invoice and invoice_line_items are persisted with correct FKs` -- BIZ-03
11. `quote_line_items flat array populates quoteLineItems table` -- BIZ-01
12. `invoice_line_items flat array populates invoiceLineItems table` -- BIZ-03
13. `attachment metadata (type, remoteUrl, noteId) persisted correctly` -- INFRA-04

### Backend Integration Test Details (4 passing)

1. `test_sync_response_contains_all_entity_type_keys` -- INFRA-04
2. `test_sync_quote_line_items_are_flat_arrays` -- BIZ-01
3. `test_sync_invoice_line_items_are_flat_arrays` -- BIZ-03
4. `test_sync_jobs_include_gps_fields` -- FIELD-02

### Gap Analysis

No gaps found. All 5 requirements (INFRA-04, SCHED-03, FIELD-02, BIZ-01, BIZ-03) have multiple automated tests covering their behavioral contracts across both Flutter and backend layers.

### Compliance Determination

**nyquist_compliant: true** -- Every requirement has at least one automated behavioral test that was executed and passed during this audit.
