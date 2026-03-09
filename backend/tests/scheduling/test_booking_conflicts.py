"""Tests for GIST constraint and concurrent booking (SCHED-05).

Tests verify:
- Basic booking creation (201)
- Booking conflict detection (409)
- Adjacent bookings don't conflict (half-open interval)
- Soft-deleted bookings don't conflict
- Outside working hours rejection (422)
- Below minimum duration rejection (422)
- Concurrent booking: exactly one success with asyncio.gather (2 clients)
- Load test: exactly one success with ~50 concurrent clients
- Conflict check endpoint (read-only)
- Conflict detail includes booking_id, time_range, job_id
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_utc(y: int, mo: int, d: int, h: int, mi: int = 0) -> str:
    """Create an ISO 8601 UTC datetime string."""
    return datetime(y, mo, d, h, mi, tzinfo=UTC).isoformat()


# Monday 2026-03-09, within working hours (07:00-16:00 PST = 15:00-24:00 UTC)
# PST = UTC-8, so 09:00 PST = 17:00 UTC
BOOKING_START = make_utc(2026, 3, 9, 17, 0)  # 09:00 PST
BOOKING_END = make_utc(2026, 3, 9, 19, 0)    # 11:00 PST


# ---------------------------------------------------------------------------
# Basic booking tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_booking_creates_successfully(
    scheduling_client, seed_contractor_weekly_schedule
):
    """Simple booking within working hours: returns 201."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    job_id = seed_contractor_weekly_schedule["job_id"]
    resp = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": str(job_id),
            "start": BOOKING_START,
            "end": BOOKING_END,
        },
    )
    assert resp.status_code == 201, f"Expected 201, got {resp.status_code}: {resp.text}"
    data = resp.json()
    assert data["contractor_id"] == str(contractor_id)
    assert "time_range_start" in data
    assert "time_range_end" in data


@pytest.mark.asyncio
async def test_booking_conflict_returns_409(
    scheduling_client, seed_contractor_weekly_schedule
):
    """Book a slot, then book overlapping slot: second returns 409 with ConflictDetail."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    job_id = seed_contractor_weekly_schedule["job_id"]

    # First booking: 9am-11am PST
    resp1 = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": str(job_id),
            "start": BOOKING_START,
            "end": BOOKING_END,
        },
    )
    assert resp1.status_code == 201

    # Second booking: 10am-12pm PST (overlaps)
    resp2 = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": str(job_id),
            "start": make_utc(2026, 3, 9, 18, 0),  # 10:00 PST
            "end": make_utc(2026, 3, 9, 20, 0),    # 12:00 PST
        },
    )
    assert resp2.status_code == 409, f"Expected 409, got {resp2.status_code}: {resp2.text}"
    detail = resp2.json()["detail"]
    assert "conflicts" in detail
    assert len(detail["conflicts"]) >= 1


@pytest.mark.asyncio
async def test_booking_adjacent_no_conflict(
    scheduling_client, seed_contractor_weekly_schedule
):
    """Booking [9am, 10am) then [10am, 11am): both succeed — half-open interval, no overlap.

    Adjacent = end of first booking == start of second booking (no gap, no overlap).
    Both bookings are within the morning working block (7am-12pm PST = 15:00-20:00 UTC,
    but 14:00-19:00 UTC with PST = UTC-8). Using morning block to avoid lunch break.
    """
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    job_id = seed_contractor_weekly_schedule["job_id"]

    # Working hours: Mon 7am-12pm PST = 15:00-20:00 UTC (PST=UTC-8, so 7+8=15)
    # First: 9am-10am PST = 17:00-18:00 UTC
    resp1 = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": str(job_id),
            "start": make_utc(2026, 3, 9, 17, 0),  # 09:00 PST
            "end": make_utc(2026, 3, 9, 18, 0),    # 10:00 PST
        },
    )
    assert resp1.status_code == 201

    # Second: 10am-11am PST = 18:00-19:00 UTC — adjacent (not overlapping)
    resp2 = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": str(job_id),
            "start": make_utc(2026, 3, 9, 18, 0),  # 10:00 PST
            "end": make_utc(2026, 3, 9, 19, 0),    # 11:00 PST
        },
    )
    assert resp2.status_code == 201, f"Adjacent booking should succeed, got: {resp2.text}"


@pytest.mark.asyncio
async def test_soft_deleted_booking_no_conflict(
    scheduling_client, seed_contractor_weekly_schedule
):
    """Soft-delete a booking, then book same slot: succeeds (GIST WHERE deleted_at IS NULL)."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    job_id = seed_contractor_weekly_schedule["job_id"]

    # Create booking
    resp1 = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": str(job_id),
            "start": BOOKING_START,
            "end": BOOKING_END,
        },
    )
    assert resp1.status_code == 201
    booking_id = resp1.json()["id"]

    # Soft-delete it
    del_resp = await scheduling_client.delete(f"/api/v1/scheduling/bookings/{booking_id}")
    assert del_resp.status_code == 204

    # Book the same slot — should succeed now
    resp2 = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": str(job_id),
            "start": BOOKING_START,
            "end": BOOKING_END,
        },
    )
    assert resp2.status_code == 201, (
        f"Should succeed after soft-delete, got {resp2.status_code}: {resp2.text}"
    )


@pytest.mark.asyncio
async def test_booking_outside_working_hours_rejected(
    scheduling_client, seed_contractor_weekly_schedule
):
    """Book at 11pm PST (outside working hours): returns 422."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    job_id = seed_contractor_weekly_schedule["job_id"]

    # 11pm-midnight PST = 07:00-08:00 UTC next day (outside working hours 7am-4pm PST)
    resp = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": str(job_id),
            "start": make_utc(2026, 3, 10, 7, 0),  # 11pm PST Monday -> 7am UTC Tuesday
            "end": make_utc(2026, 3, 10, 8, 0),    # midnight PST Monday -> 8am UTC Tuesday
        },
    )
    assert resp.status_code == 422, f"Expected 422, got {resp.status_code}: {resp.text}"


@pytest.mark.asyncio
async def test_booking_below_minimum_duration_rejected(
    scheduling_client, seed_contractor_weekly_schedule
):
    """Book a 15-minute slot (below 30-min minimum): returns 422."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    job_id = seed_contractor_weekly_schedule["job_id"]

    resp = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": str(job_id),
            "start": make_utc(2026, 3, 9, 17, 0),   # 09:00 PST
            "end": make_utc(2026, 3, 9, 17, 15),    # 09:15 PST — 15 minutes
        },
    )
    assert resp.status_code == 422, f"Expected 422, got {resp.status_code}: {resp.text}"


# ---------------------------------------------------------------------------
# Concurrent booking tests — critical for SCHED-05 correctness guarantee
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_concurrent_booking_exactly_one_succeeds(
    seed_contractor_weekly_schedule
):
    """Critical: two concurrent booking attempts — exactly one 201, exactly one 409.

    Uses asyncio.gather with separate AsyncClient instances so each request
    gets its own DB session (separate connection, separate transaction).
    This is the minimum viable race condition test — proves the SELECT FOR UPDATE
    lock + GIST constraint work together.
    """
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    token = seed_contractor_weekly_schedule["admin_token"]
    job_id = seed_contractor_weekly_schedule["job_id"]

    booking_payload = {
        "contractor_id": str(contractor_id),
        "job_id": str(job_id),
        "start": BOOKING_START,
        "end": BOOKING_END,
    }

    async def attempt_booking():
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
            headers={"Authorization": f"Bearer {token}"},
        ) as client:
            return await client.post("/api/v1/scheduling/bookings", json=booking_payload)

    # Fire both requests concurrently
    results = await asyncio.gather(attempt_booking(), attempt_booking())
    status_codes = [r.status_code for r in results]

    successes = status_codes.count(201)
    conflicts = status_codes.count(409)
    errors = sum(1 for s in status_codes if s not in (201, 409))

    assert successes == 1, (
        f"Expected exactly 1 success, got {successes}. Status codes: {status_codes}"
    )
    assert conflicts == 1, (
        f"Expected exactly 1 conflict, got {conflicts}. Status codes: {status_codes}"
    )
    assert errors == 0, (
        f"Expected 0 server errors, got {errors}. Status codes: {status_codes}"
    )


@pytest.mark.slow
@pytest.mark.asyncio
async def test_concurrent_booking_load(seed_contractor_weekly_schedule):
    """Load test: 50 concurrent booking attempts — exactly 1 success, 49 conflicts, 0 errors.

    Proves SELECT FOR UPDATE + GIST hold under sustained concurrent pressure.
    Each AsyncClient instance gets its own DB connection via the ASGI transport.

    Tagged @pytest.mark.slow so CI can filter with -m 'not slow' for fast runs.
    """
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    token = seed_contractor_weekly_schedule["admin_token"]
    job_id = seed_contractor_weekly_schedule["job_id"]
    num_clients = 50

    # Shared booking payload — all clients try to book the same slot
    booking_payload = {
        "contractor_id": str(contractor_id),
        "job_id": str(job_id),
        "start": make_utc(2026, 3, 9, 17, 0),   # 09:00 PST
        "end": make_utc(2026, 3, 9, 19, 0),     # 11:00 PST
    }

    async def attempt_booking():
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
            headers={"Authorization": f"Bearer {token}"},
        ) as client:
            return await client.post("/api/v1/scheduling/bookings", json=booking_payload)

    # Fire all 50 requests simultaneously
    tasks = [attempt_booking() for _ in range(num_clients)]
    results = await asyncio.gather(*tasks)
    status_codes = [r.status_code for r in results]

    successes = status_codes.count(201)
    conflicts = status_codes.count(409)
    errors = sum(1 for s in status_codes if s not in (201, 409))

    assert successes == 1, (
        f"Expected exactly 1 booking success under load, got {successes}. "
        f"Codes: {sorted(status_codes)}"
    )
    assert conflicts == num_clients - 1, (
        f"Expected {num_clients - 1} conflicts, got {conflicts}. "
        f"Codes: {sorted(status_codes)}"
    )
    assert errors == 0, (
        f"Expected 0 server errors (lock + GIST must handle all contention gracefully), "
        f"got {errors}. Error responses: "
        f"{[r.text for r in results if r.status_code not in (201, 409)]}"
    )


# ---------------------------------------------------------------------------
# Conflict check endpoint tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_conflict_check_endpoint_read_only(
    scheduling_client, seed_contractor_weekly_schedule
):
    """POST /conflicts returns conflicts without creating any booking."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    job_id = seed_contractor_weekly_schedule["job_id"]

    # First create a booking
    resp1 = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": str(job_id),
            "start": BOOKING_START,
            "end": BOOKING_END,
        },
    )
    assert resp1.status_code == 201

    # Check for conflicts (overlapping time range)
    resp2 = await scheduling_client.post(
        "/api/v1/scheduling/conflicts",
        json={
            "contractor_id": str(contractor_id),
            "start": make_utc(2026, 3, 9, 17, 30),  # 9:30 PST — inside booked slot
            "end": make_utc(2026, 3, 9, 18, 30),    # 10:30 PST
        },
    )
    assert resp2.status_code == 200
    conflicts = resp2.json()
    assert len(conflicts) >= 1

    # Verify no new bookings were created (count should still be 1)
    list_resp = await scheduling_client.get(
        "/api/v1/scheduling/bookings",
        params={"contractor_id": str(contractor_id)},
    )
    assert list_resp.status_code == 200
    assert len(list_resp.json()) == 1


@pytest.mark.asyncio
async def test_conflict_detail_includes_job_info(
    scheduling_client, seed_contractor_weekly_schedule
):
    """ConflictDetail response includes booking_id, time_range, job_id."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    job_id = seed_contractor_weekly_schedule["job_id"]

    # Create a booking
    resp1 = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": str(job_id),
            "start": BOOKING_START,
            "end": BOOKING_END,
        },
    )
    assert resp1.status_code == 201
    booking_id = resp1.json()["id"]

    # Trigger a conflict
    resp2 = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": str(job_id),
            "start": BOOKING_START,
            "end": BOOKING_END,
        },
    )
    assert resp2.status_code == 409
    detail = resp2.json()["detail"]
    conflict = detail["conflicts"][0]

    # Verify all required fields are present
    assert "booking_id" in conflict
    assert "time_range_start" in conflict
    assert "time_range_end" in conflict
    assert "job_id" in conflict

    # Verify values match
    assert conflict["booking_id"] == booking_id
    assert conflict["job_id"] == str(job_id)


@pytest.mark.asyncio
async def test_conflict_check_returns_empty_for_free_slot(
    scheduling_client, seed_contractor_weekly_schedule
):
    """POST /conflicts returns empty list when slot is free."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]

    resp = await scheduling_client.post(
        "/api/v1/scheduling/conflicts",
        json={
            "contractor_id": str(contractor_id),
            "start": BOOKING_START,
            "end": BOOKING_END,
        },
    )
    assert resp.status_code == 200
    assert resp.json() == []
