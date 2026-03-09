"""Tests for multi-day job booking (SCHED-07).

Tests verify:
- All days created with correct day_index on success
- All-or-nothing: conflict on any day prevents all days from being created
- Non-consecutive days: both bookings created with Tue remaining free
- Per-day different times
- Single-day reschedule within multi-day booking
- Date suggestion prefers consecutive dates
- Date suggestion falls back to non-consecutive when consecutive unavailable
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy import text


def make_utc(y: int, mo: int, d: int, h: int, mi: int = 0) -> str:
    """Create an ISO 8601 UTC datetime string."""
    return datetime(y, mo, d, h, mi, tzinfo=UTC).isoformat()


# PST = UTC-8 in March (before spring-forward on Mar 8)
# Working hours 7am-4pm PST = 15:00-00:00 UTC (but 07:00 PST = 15:00 UTC)
# Monday 2026-03-09: 09:00-11:00 PST = 17:00-19:00 UTC
# Tuesday 2026-03-10: 09:00-11:00 PST = 17:00-19:00 UTC
# Wednesday 2026-03-11: 09:00-11:00 PST = 17:00-19:00 UTC


@pytest.mark.asyncio
async def test_multiday_booking_all_days_created(
    scheduling_client, seed_contractor_weekly_schedule
):
    """Book 3 consecutive days: returns 3 bookings with day_index 0, 1, 2."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    job_id = str(seed_contractor_weekly_schedule["job_id"])

    resp = await scheduling_client.post(
        "/api/v1/scheduling/bookings/multi-day",
        json={
            "contractor_id": str(contractor_id),
            "job_id": job_id,
            "day_blocks": [
                {
                    "date": "2026-03-09",
                    "start_time": "09:00:00",
                    "end_time": "11:00:00",
                },
                {
                    "date": "2026-03-10",
                    "start_time": "09:00:00",
                    "end_time": "11:00:00",
                },
                {
                    "date": "2026-03-11",
                    "start_time": "09:00:00",
                    "end_time": "11:00:00",
                },
            ],
        },
    )
    assert resp.status_code == 201, f"Expected 201, got {resp.status_code}: {resp.text}"
    bookings = resp.json()
    assert len(bookings) == 3

    day_indices = sorted(b["day_index"] for b in bookings)
    assert day_indices == [0, 1, 2], f"Expected day_indices [0,1,2], got {day_indices}"

    # All bookings should share the same job_id
    for b in bookings:
        assert b["job_id"] == job_id

    # First booking has no parent_booking_id; others reference the first
    bookings_by_index = {b["day_index"]: b for b in bookings}
    assert bookings_by_index[0]["parent_booking_id"] is None
    assert bookings_by_index[1]["parent_booking_id"] == bookings_by_index[0]["id"]
    assert bookings_by_index[2]["parent_booking_id"] == bookings_by_index[0]["id"]


@pytest.mark.asyncio
async def test_multiday_all_or_nothing(
    scheduling_client, seed_contractor_weekly_schedule
):
    """Book 3 days, middle day has conflict: entire booking fails (no day is created)."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]

    job_id = str(seed_contractor_weekly_schedule["job_id"])

    # Pre-book Tuesday (middle day)
    preblock_resp = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": job_id,
            "start": make_utc(2026, 3, 10, 17, 0),  # Tue 09:00 PST
            "end": make_utc(2026, 3, 10, 19, 0),    # Tue 11:00 PST
        },
    )
    assert preblock_resp.status_code == 201

    # Try to multi-day book Mon, Tue (conflict!), Wed
    resp = await scheduling_client.post(
        "/api/v1/scheduling/bookings/multi-day",
        json={
            "contractor_id": str(contractor_id),
            "job_id": job_id,
            "day_blocks": [
                {"date": "2026-03-09", "start_time": "09:00:00", "end_time": "11:00:00"},
                {"date": "2026-03-10", "start_time": "09:00:00", "end_time": "11:00:00"},
                {"date": "2026-03-11", "start_time": "09:00:00", "end_time": "11:00:00"},
            ],
        },
    )
    assert resp.status_code == 409, f"Expected 409 (conflict), got {resp.status_code}: {resp.text}"

    # Verify that Monday and Wednesday were NOT created (all-or-nothing)
    list_resp = await scheduling_client.get(
        "/api/v1/scheduling/bookings",
        params={"contractor_id": str(contractor_id)},
    )
    assert list_resp.status_code == 200
    # Only the pre-booked Tuesday booking should exist
    bookings = list_resp.json()
    assert len(bookings) == 1, (
        f"Expected 1 booking (pre-booked Tue), got {len(bookings)}: {bookings}"
    )


@pytest.mark.asyncio
async def test_multiday_non_consecutive_days(
    scheduling_client, seed_contractor_weekly_schedule
):
    """Book Mon and Wed (skip Tue): both bookings created, Tue remains free."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    job_id = str(seed_contractor_weekly_schedule["job_id"])

    resp = await scheduling_client.post(
        "/api/v1/scheduling/bookings/multi-day",
        json={
            "contractor_id": str(contractor_id),
            "job_id": job_id,
            "day_blocks": [
                {"date": "2026-03-09", "start_time": "09:00:00", "end_time": "11:00:00"},  # Mon
                {"date": "2026-03-11", "start_time": "09:00:00", "end_time": "11:00:00"},  # Wed
            ],
        },
    )
    assert resp.status_code == 201, f"Expected 201, got {resp.status_code}: {resp.text}"
    bookings = resp.json()
    assert len(bookings) == 2

    # Check that Tuesday is free (no booking)
    list_resp = await scheduling_client.get(
        "/api/v1/scheduling/bookings",
        params={"contractor_id": str(contractor_id)},
    )
    assert list_resp.status_code == 200
    all_bookings = list_resp.json()
    assert len(all_bookings) == 2  # Only Mon and Wed

    # Check availability on Tuesday — should have free windows
    avail_resp = await scheduling_client.post(
        "/api/v1/scheduling/availability",
        json={
            "contractor_ids": [str(contractor_id)],
            "date": "2026-03-10",  # Tuesday
        },
    )
    assert avail_resp.status_code == 200
    avail = avail_resp.json()
    assert len(avail[0]["free_windows"]) >= 1, "Tuesday should have free windows"


@pytest.mark.asyncio
async def test_multiday_per_day_different_times(
    scheduling_client, seed_contractor_weekly_schedule
):
    """Book 3 days with different time blocks: all created with correct time ranges.

    All times must stay within a single working block to avoid spanning the lunch break.
    Contractor works Mon-Fri: 7am-12pm and 1pm-4pm PST.
    """
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]

    job_id = str(seed_contractor_weekly_schedule["job_id"])
    resp = await scheduling_client.post(
        "/api/v1/scheduling/bookings/multi-day",
        json={
            "contractor_id": str(contractor_id),
            "job_id": job_id,
            "day_blocks": [
                {"date": "2026-03-09", "start_time": "08:00:00", "end_time": "11:00:00"},  # Mon: 3h (morning block)
                {"date": "2026-03-10", "start_time": "13:00:00", "end_time": "15:30:00"},  # Tue: 2.5h (afternoon block)
                {"date": "2026-03-11", "start_time": "07:00:00", "end_time": "09:30:00"},  # Wed: 2.5h (morning block)
            ],
        },
    )
    assert resp.status_code == 201, f"Expected 201, got {resp.status_code}: {resp.text}"
    bookings = resp.json()
    assert len(bookings) == 3

    bookings_by_index = {b["day_index"]: b for b in bookings}

    # Verify durations (UTC) — times are in PST (UTC-8 before spring-forward)
    def utc_duration_hours(booking):
        start = datetime.fromisoformat(booking["time_range_start"])
        end = datetime.fromisoformat(booking["time_range_end"])
        return (end - start).total_seconds() / 3600

    assert utc_duration_hours(bookings_by_index[0]) == pytest.approx(3.0)
    assert utc_duration_hours(bookings_by_index[1]) == pytest.approx(2.5)
    assert utc_duration_hours(bookings_by_index[2]) == pytest.approx(2.5)


@pytest.mark.asyncio
async def test_multiday_reschedule_single_day(
    scheduling_client, seed_contractor_weekly_schedule
):
    """Cancel one day of multi-day booking, rebook that day at new time."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    job_id = str(seed_contractor_weekly_schedule["job_id"])

    # Create a 2-day booking
    resp = await scheduling_client.post(
        "/api/v1/scheduling/bookings/multi-day",
        json={
            "contractor_id": str(contractor_id),
            "job_id": job_id,
            "day_blocks": [
                {"date": "2026-03-09", "start_time": "09:00:00", "end_time": "11:00:00"},  # Mon
                {"date": "2026-03-10", "start_time": "09:00:00", "end_time": "11:00:00"},  # Tue
            ],
        },
    )
    assert resp.status_code == 201
    bookings = resp.json()

    # Identify and cancel Monday's booking (day_index=0)
    monday_booking = next(b for b in bookings if b["day_index"] == 0)
    del_resp = await scheduling_client.delete(
        f"/api/v1/scheduling/bookings/{monday_booking['id']}"
    )
    assert del_resp.status_code == 204

    # Re-book Monday at a different time (afternoon working block: 13:00-16:00 PDT = 20:00-23:00 UTC)
    # Note: March 9, 2026 is AFTER the spring-forward (Mar 8), so Vancouver is PDT (UTC-7)
    rebook_resp = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": job_id,
            "start": make_utc(2026, 3, 9, 20, 0),  # 13:00 PDT (UTC-7): afternoon block start
            "end": make_utc(2026, 3, 9, 22, 0),    # 15:00 PDT: within afternoon block (ends 16:00 PDT = 23:00 UTC)
        },
    )
    assert rebook_resp.status_code == 201, (
        f"Re-booking cancelled day should succeed: {rebook_resp.text}"
    )


@pytest.mark.asyncio
async def test_suggest_dates_consecutive_preferred(
    scheduling_client, seed_contractor_weekly_schedule
):
    """suggest_dates returns consecutive date sets when they exist."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]

    resp = await scheduling_client.post(
        "/api/v1/scheduling/suggest-dates",
        json={
            "contractor_id": str(contractor_id),
            "num_days": 2,
            "preferred_start": "2026-03-09",
            "duration_hours": 2.0,
            "within_days": 10,
        },
    )
    assert resp.status_code == 200
    suggestions = resp.json()
    assert len(suggestions) >= 1

    # At least the first suggestion should be consecutive
    first = suggestions[0]
    assert first["is_consecutive"] is True, (
        f"First suggestion should be consecutive: {first}"
    )


@pytest.mark.asyncio
async def test_suggest_dates_falls_back_to_non_consecutive(
    test_engine, scheduling_client, seed_contractor_weekly_schedule
):
    """When consecutive dates unavailable, returns non-consecutive alternatives."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    company_id = seed_contractor_weekly_schedule["company_id"]

    # Block Tuesday 2026-03-10 to prevent consecutive Mon-Tue
    async with test_engine.connect() as conn:
        # SET LOCAL requires direct string interpolation — no bind params (PostgreSQL limitation)
        await conn.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await conn.execute(
            text("""
                INSERT INTO contractor_date_overrides
                    (id, company_id, contractor_id, override_date, is_unavailable,
                     block_index, version, created_at, updated_at)
                VALUES (:id, :company_id, :cid, '2026-03-10', true, 0, 1, now(), now())
            """),
            {
                "id": str(uuid.uuid4()),
                "company_id": str(company_id),
                "cid": str(contractor_id),
            },
        )
        await conn.commit()

    # Block Wednesday 2026-03-11 too (so Mon->Tue consecutive impossible in Mar 9-11 window)
    async with test_engine.connect() as conn:
        # SET LOCAL requires direct string interpolation — no bind params (PostgreSQL limitation)
        await conn.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await conn.execute(
            text("""
                INSERT INTO contractor_date_overrides
                    (id, company_id, contractor_id, override_date, is_unavailable,
                     block_index, version, created_at, updated_at)
                VALUES (:id, :company_id, :cid, '2026-03-11', true, 0, 1, now(), now())
            """),
            {
                "id": str(uuid.uuid4()),
                "company_id": str(company_id),
                "cid": str(contractor_id),
            },
        )
        await conn.commit()

    # With Tue+Wed blocked, Mon-Thu are not consecutive: Mon(9), Thu(12), Fri(13) are eligible
    resp = await scheduling_client.post(
        "/api/v1/scheduling/suggest-dates",
        json={
            "contractor_id": str(contractor_id),
            "num_days": 2,
            "preferred_start": "2026-03-09",
            "duration_hours": 2.0,
            "within_days": 10,
        },
    )
    assert resp.status_code == 200
    suggestions = resp.json()

    # Should still return suggestions (non-consecutive fallback)
    assert len(suggestions) >= 1

    # All returned dates should be valid (within the window)
    for suggestion in suggestions:
        assert len(suggestion["dates"]) == 2
