---
phase: 03
slug: scheduling-engine
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-14
audited: 2026-03-14
---

# Phase 03 -- Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 7.x (backend) + Flutter test (mobile) |
| **Config file** | `backend/pyproject.toml` (pytest), `mobile/pubspec.yaml` (Flutter) |
| **Quick run command** | `cd backend && uv run python -m pytest tests/scheduling/ -v` |
| **Full suite command** | `cd backend && uv run python -m pytest && cd ../mobile && flutter test` |
| **Estimated runtime** | ~30 seconds (backend scheduling) + ~15 seconds (mobile e2e) |

---

## Sampling Rate

- **After every task commit:** Run `cd backend && uv run python -m pytest tests/scheduling/ -v`
- **After every plan wave:** Run full suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-T1 | 01 | 1 | SCHED-04, SCHED-05, SCHED-07 | integration | `cd backend && uv run alembic upgrade head` | yes | green |
| 03-01-T2 | 01 | 1 | SCHED-04, SCHED-05, SCHED-07 | unit | `cd backend && uv run python -c "from app.features.scheduling.models import Booking; print('OK')"` | yes | green |
| 03-02-T1 | 02 | 2 | SCHED-06 | unit | `cd backend && uv run python -m pytest tests/scheduling/test_travel_time.py -v` | yes | green |
| 03-02-T2 | 02 | 2 | SCHED-06 | unit | `cd backend && uv run python -c "from app.features.scheduling.geocoding import GeocodingProvider; print('OK')"` | yes | green |
| 03-03-T1 | 03 | 3 | SCHED-04, SCHED-05, SCHED-06, SCHED-07 | unit | `cd backend && uv run python -c "from app.features.scheduling.repository import SchedulingRepository; print('OK')"` | yes | green |
| 03-03-T2 | 03 | 3 | SCHED-04, SCHED-05, SCHED-06, SCHED-07 | integration | `cd backend && uv run python -m pytest tests/scheduling/test_availability.py -v` | yes | green |
| 03-04-T1 | 04 | 4 | SCHED-04, SCHED-05, SCHED-06, SCHED-07 | integration | `cd backend && uv run python -m pytest tests/scheduling/ -v` | yes | green |
| 03-04-T2 | 04 | 4 | SCHED-04, SCHED-05, SCHED-06, SCHED-07 | integration | `cd backend && uv run python -m pytest tests/scheduling/ -v` | yes | green |

*Status: pending -- green -- red -- flaky*

---

## Requirement Coverage Matrix

| Requirement | Description | Backend Tests | Mobile Tests | Coverage |
|-------------|-------------|---------------|--------------|----------|
| SCHED-04 | Availability computation (free windows minus bookings/travel/non-working hours) | `test_availability.py` (13 tests: no bookings, one booking, buffer, day off, custom override, min duration, company default, multi-contractor, gap reasons, DST boundary) | `phase_3_scheduling_e2e_test.dart`, `booking_dao_test.dart` | COVERED |
| SCHED-05 | Conflict detection / double-booking prevention (GIST + SELECT FOR UPDATE) | `test_booking_conflicts.py` (11 tests: create, conflict 409, adjacent no-conflict, soft-delete no-conflict, outside working hours 422, below min duration 422, 2-client race, 50-client load, conflict check read-only, conflict detail, full lifecycle) | `phase_3_scheduling_e2e_test.dart` | COVERED |
| SCHED-06 | Travel time awareness (ORS provider, PostgreSQL cache, safety margin) | `test_travel_time.py` (16 tests: cache store/retrieve, bidirectional, TTL expired fallback, coordinate rounding, ORS coordinate order, safety margin, availability with travel buffer, travel time unavailable default) | `phase_3_scheduling_e2e_test.dart` | COVERED |
| SCHED-07 | Multi-day booking (all-or-nothing, non-consecutive, suggest dates) | `test_multiday.py` (7 tests: all days created, all-or-nothing, non-consecutive, per-day times, reschedule single day, suggest consecutive, suggest non-consecutive fallback) | `phase_3_scheduling_e2e_test.dart` | COVERED |

---

## Key Behavioral Tests Per Requirement

### SCHED-04: Availability Computation

| Test | File | Behavior Verified |
|------|------|-------------------|
| test_free_windows_with_no_bookings | test_availability.py | Contractor with Mon-Fri 7am-4pm returns correct free windows |
| test_free_windows_with_one_booking | test_availability.py | Booking 9am-11am returns three windows [7-9, 11-12, 1-4] |
| test_free_windows_respects_buffer | test_availability.py | 15-min buffer shrinks adjacent windows |
| test_free_windows_on_day_off | test_availability.py | Date override is_unavailable returns empty |
| test_free_windows_below_min_duration_excluded | test_availability.py | Gap below 30min minimum excluded |
| test_contractor_inherits_company_default | test_availability.py | No personal schedule falls back to company default |
| test_free_windows_include_gap_reasons | test_availability.py | Blocked intervals include reasons |
| test_booking_dst_boundary | test_availability.py | Spring-forward DST stores correct UTC TSTZRANGE |

### SCHED-05: Conflict Detection

| Test | File | Behavior Verified |
|------|------|-------------------|
| test_concurrent_booking_exactly_one_succeeds | test_booking_conflicts.py | Two asyncio.gather requests: 1 success, 1 conflict |
| test_concurrent_booking_load | test_booking_conflicts.py | 50 concurrent clients: exactly 1 success, 49 conflicts, 0 errors |
| test_booking_conflict_returns_409 | test_booking_conflicts.py | Overlapping booking returns 409 with ConflictDetail |
| test_soft_deleted_booking_no_conflict | test_booking_conflicts.py | Soft-deleted booking does not block new booking |
| test_booking_adjacent_no_conflict | test_booking_conflicts.py | Half-open intervals [9,11) and [11,1) both succeed |

### SCHED-06: Travel Time Awareness

| Test | File | Behavior Verified |
|------|------|-------------------|
| test_travel_cache_bidirectional | test_travel_time.py | A->B and B->A return same cached value |
| test_travel_cache_ttl_expired_fallback | test_travel_time.py | Expired entry served as fallback on API failure |
| test_travel_cache_coordinate_rounding | test_travel_time.py | Coords differing by <0.001 share cache key |
| test_ors_provider_coordinate_order | test_travel_time.py | ORS request uses lng,lat (GeoJSON order) |
| test_safety_margin_applied | test_travel_time.py | 600s + 20% margin = 720s |
| test_availability_with_travel_buffer | test_travel_time.py | Free window reduced by travel time + buffer |

### SCHED-07: Multi-Day Booking

| Test | File | Behavior Verified |
|------|------|-------------------|
| test_multiday_booking_all_days_created | test_multiday.py | 3 consecutive days returns 3 bookings with day_index |
| test_multiday_all_or_nothing | test_multiday.py | Conflict on middle day rejects entire booking |
| test_multiday_non_consecutive_days | test_multiday.py | Mon + Wed booked, Tue remains free |
| test_suggest_dates_consecutive_preferred | test_multiday.py | Consecutive date sets returned first |

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| None | -- | All behaviors covered by automated tests | -- |

---

## Validation Sign-Off

- [x] All tasks have automated verify commands
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
| 2026-03-14 | gsd-nyquist-auditor | Initial VALIDATION.md creation from plans/summaries analysis | All 4 requirements (SCHED-04 through SCHED-07) COVERED with 47 backend tests + mobile E2E. nyquist_compliant: true. |
