---
status: complete
phase: 03-scheduling-engine
source: 03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-03-SUMMARY.md, 03-04-SUMMARY.md
started: 2026-03-06T12:00:00Z
updated: 2026-03-07T03:12:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Cold Start Smoke Test
expected: Kill any running server. Run `alembic upgrade head` then start the server with `uvicorn app.main:app`. Server boots without errors, migration 0007 (scheduling tables) applies cleanly, and hitting `/docs` shows the scheduling endpoints registered.
result: pass

### 2. Scheduling Test Suite Passes
expected: Run `uv run python -m pytest tests/scheduling/ -v` from the backend directory. All 47 tests pass — availability (13), booking conflicts (11), multi-day (7), and travel time (16).
result: pass

### 3. Existing Tests Still Pass
expected: Run `uv run python -m pytest --ignore=tests/scheduling/ -v` from the backend directory. All pre-existing tests (71+) continue to pass with the new scheduling tables and FK constraints.
result: pass

### 4. Availability Endpoint Returns Free Windows
expected: POST to `/scheduling/availability` with a contractor ID and date range. Response returns free windows with start/end times and reason_before labels. Empty schedule returns full working hours as free.
result: pass

### 5. Book a Slot Successfully
expected: POST to `/scheduling/bookings` with a contractor, job site, and time range within working hours. Returns 201 with booking details including the TSTZRANGE time_range.
result: pass

### 6. Conflict Detection Rejects Overlapping Booking
expected: After booking a slot, POST another booking for the same contractor overlapping the same time range. Returns 409 with ConflictDetail showing the conflicting booking.
result: pass

### 7. Multi-Day Booking All-or-Nothing
expected: POST to `/scheduling/bookings/multi-day` with multiple day blocks. If all days are free, all bookings are created (linked via parent_booking_id). If any day conflicts, the entire batch is rejected — no partial bookings.
result: pass

### 8. Suggest Dates Returns Valid Options
expected: POST to `/scheduling/suggest-dates` with contractor, duration, and preferred count. Returns date suggestions, prioritizing consecutive days first and falling back to non-consecutive combinations.
result: pass

### 9. Weekly Schedule CRUD
expected: PUT weekly schedule for a contractor (e.g., Mon-Fri 9am-5pm). GET returns the saved schedule. Availability endpoint reflects the new working hours.
result: pass

### 10. Date Override Blocks a Day
expected: POST a date override marking a specific date as unavailable. Availability query for that date returns no free windows. Attempting to book on that date returns 422 (outside working hours).
result: pass

### 11. Soft-Deleted Booking Frees the Slot
expected: DELETE a booking (soft-delete). The time slot becomes available again — availability endpoint shows it as free. A new booking in that slot succeeds.
result: pass

## Summary

total: 11
passed: 11
issues: 0
pending: 0
skipped: 0

## Gaps

[none yet]
