"""Tests for availability computation (SCHED-04).

Tests verify:
- Free window calculation from working hours - bookings - buffers
- Date override (full-day off, custom hours)
- Minimum duration filtering
- Company default working hours fallback
- API endpoint returns multiple contractors
- Blocked interval reasons
- DST edge case: 2026 spring-forward transition in America/Vancouver
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import text

from app.features.scheduling.service import SchedulingService

# ---------------------------------------------------------------------------
# Unit tests for _compute_free_windows (pure logic, no DB)
# ---------------------------------------------------------------------------


def make_service():
    """Create a SchedulingService instance without a real DB for unit testing pure logic."""
    from unittest.mock import MagicMock

    mock_db = MagicMock()
    return SchedulingService(db=mock_db)


def make_dt(hour: int, minute: int = 0, day: int = 10, tz=UTC) -> datetime:
    """Helper: create a UTC datetime for 2026-03-day at hour:minute."""
    return datetime(2026, 3, day, hour, minute, tzinfo=tz)


class TestFreeWindowComputation:
    """Unit tests for _compute_free_windows (pure algorithmic logic)."""

    def test_free_windows_with_no_bookings(self):
        """Contractor with two working blocks and no bookings returns two free windows."""
        svc = make_service()
        working_blocks = [
            (make_dt(7), make_dt(12)),
            (make_dt(13), make_dt(16)),
        ]
        free_windows, blocked = svc._compute_free_windows(
            working_blocks=working_blocks,
            blocked_intervals=[],
            min_duration_minutes=30,
            buffer_minutes=0,
        )
        assert len(free_windows) == 2
        assert free_windows[0].start == make_dt(7)
        assert free_windows[0].end == make_dt(12)
        assert free_windows[1].start == make_dt(13)
        assert free_windows[1].end == make_dt(16)

    def test_free_windows_with_one_booking(self):
        """Booking 9am-11am splits the morning block into [7-9] and [11-12]."""
        svc = make_service()
        working_blocks = [
            (make_dt(7), make_dt(12)),
            (make_dt(13), make_dt(16)),
        ]
        blocked_intervals = [(make_dt(9), make_dt(11), "existing_job")]
        free_windows, blocked = svc._compute_free_windows(
            working_blocks=working_blocks,
            blocked_intervals=blocked_intervals,
            min_duration_minutes=30,
            buffer_minutes=0,
        )
        # Expected: [7-9], [11-12], [13-16]
        starts = [fw.start for fw in free_windows]
        assert make_dt(7) in starts
        assert make_dt(11) in starts
        assert make_dt(13) in starts
        assert len(free_windows) == 3

    def test_free_windows_respects_buffer(self):
        """15-min buffer shrinks adjacent free windows around a booking."""
        svc = make_service()
        working_blocks = [(make_dt(7), make_dt(12))]
        # Booking 9am-11am; 15min buffer -> blocked zone is 8:45-11:15
        blocked_intervals = [(make_dt(9), make_dt(11), "existing_job")]
        free_windows, blocked = svc._compute_free_windows(
            working_blocks=working_blocks,
            blocked_intervals=blocked_intervals,
            min_duration_minutes=30,
            buffer_minutes=15,
        )
        # Morning window [7, 8:45] = 105 min — one free window
        # [11:15, 12:00] = 45 min — another free window
        assert len(free_windows) == 2
        assert free_windows[0].end == make_dt(8, 45)
        assert free_windows[1].start == make_dt(11, 15)

    def test_free_windows_on_day_off_empty_working_blocks(self):
        """When working_blocks is empty, return empty free windows."""
        svc = make_service()
        free_windows, blocked = svc._compute_free_windows(
            working_blocks=[],
            blocked_intervals=[],
            min_duration_minutes=30,
            buffer_minutes=15,
        )
        assert free_windows == []
        assert blocked == []

    def test_free_windows_below_min_duration_excluded(self):
        """A free gap of 20 minutes is excluded when min_duration_minutes=30."""
        svc = make_service()
        # Working 7-12; booking 7:40-11:45 leaves: [7:00-7:40]=40min, [11:45-12:00]=15min
        working_blocks = [(make_dt(7), make_dt(12))]
        blocked_intervals = [(make_dt(7, 40), make_dt(11, 45), "existing_job")]
        free_windows, blocked = svc._compute_free_windows(
            working_blocks=working_blocks,
            blocked_intervals=blocked_intervals,
            min_duration_minutes=30,
            buffer_minutes=0,
        )
        # Only the 40-min morning slot survives; the 15-min tail is excluded
        assert len(free_windows) == 1
        assert free_windows[0].start == make_dt(7)
        assert free_windows[0].end == make_dt(7, 40)

    def test_free_windows_include_gap_reasons(self):
        """Blocked intervals include correct reason classification."""
        svc = make_service()
        working_blocks = [(make_dt(7), make_dt(12))]
        blocked_intervals = [
            (make_dt(9), make_dt(10), "existing_job"),
        ]
        free_windows, blocked = svc._compute_free_windows(
            working_blocks=working_blocks,
            blocked_intervals=blocked_intervals,
            min_duration_minutes=30,
            buffer_minutes=0,
        )
        # First free window starts at working hours start
        assert free_windows[0].reason_before == "outside_working_hours"
        # Blocked interval should have reason "existing_job"
        reasons = [b.reason for b in blocked]
        assert "existing_job" in reasons

    def test_free_windows_full_day_free(self):
        """Entire working block is free: single free window returned."""
        svc = make_service()
        working_blocks = [(make_dt(7), make_dt(16))]
        free_windows, blocked = svc._compute_free_windows(
            working_blocks=working_blocks,
            blocked_intervals=[],
            min_duration_minutes=30,
            buffer_minutes=0,
        )
        assert len(free_windows) == 1
        assert free_windows[0].start == make_dt(7)
        assert free_windows[0].end == make_dt(16)


# ---------------------------------------------------------------------------
# Integration tests — availability via real DB + HTTP
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_availability_api_returns_contractor(
    scheduling_client, seed_contractor_weekly_schedule
):
    """POST /availability returns availability for the contractor."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    # Use a Monday in 2026 (2026-03-09 is a Monday)
    resp = await scheduling_client.post(
        "/api/v1/scheduling/availability",
        json={
            "contractor_ids": [str(contractor_id)],
            "date": "2026-03-09",
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 1
    assert data[0]["contractor_id"] == str(contractor_id)
    assert len(data[0]["free_windows"]) >= 1  # Mon has working hours


@pytest.mark.asyncio
async def test_availability_api_returns_multiple_contractors(
    test_engine, scheduling_client, seed_contractor_weekly_schedule
):
    """POST /availability with two contractor_ids returns two AvailabilityResponse entries."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    company_id = seed_contractor_weekly_schedule["company_id"]

    # Create a second contractor
    contractor2_id = uuid.uuid4()
    async with test_engine.connect() as conn:
        # SET LOCAL requires direct string interpolation — no bind params (PostgreSQL limitation)
        await conn.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await conn.execute(
            text("""
                INSERT INTO users (id, company_id, email, password_hash, first_name, last_name,
                    timezone, version, created_at, updated_at)
                VALUES (:id, :company_id, :email, 'hashed', 'Alice', 'Smith',
                    'America/Vancouver', 1, now(), now())
            """),
            {
                "id": str(contractor2_id),
                "company_id": str(company_id),
                "email": "contractor2@example.com",
            },
        )
        # Add weekly schedule for contractor2 (Monday)
        sched_id = uuid.uuid4()
        await conn.execute(
            text("""
                INSERT INTO contractor_weekly_schedule
                    (id, company_id, contractor_id, day_of_week, block_index,
                     start_time, end_time, version, created_at, updated_at)
                VALUES (:id, :company_id, :cid, 0, 0, '07:00', '12:00', 1, now(), now())
            """),
            {
                "id": str(sched_id),
                "company_id": str(company_id),
                "cid": str(contractor2_id),
            },
        )
        await conn.commit()

    resp = await scheduling_client.post(
        "/api/v1/scheduling/availability",
        json={
            "contractor_ids": [str(contractor_id), str(contractor2_id)],
            "date": "2026-03-09",  # Monday
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 2
    ids_returned = {item["contractor_id"] for item in data}
    assert str(contractor_id) in ids_returned
    assert str(contractor2_id) in ids_returned


@pytest.mark.asyncio
async def test_free_windows_on_day_off(
    test_engine, scheduling_client, seed_contractor_weekly_schedule
):
    """Date override is_unavailable=True: returns empty free windows (time_off)."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    company_id = seed_contractor_weekly_schedule["company_id"]
    override_date = date(2026, 3, 9)  # Monday

    async with test_engine.connect() as conn:
        # SET LOCAL requires direct string interpolation — no bind params (PostgreSQL limitation)
        await conn.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await conn.execute(
            text("""
                INSERT INTO contractor_date_overrides
                    (id, company_id, contractor_id, override_date, is_unavailable,
                     block_index, version, created_at, updated_at)
                VALUES (:id, :company_id, :cid, :override_date, true,
                    0, 1, now(), now())
            """),
            {
                "id": str(uuid.uuid4()),
                "company_id": str(company_id),
                "cid": str(contractor_id),
                "override_date": override_date,  # asyncpg needs date object, not string
            },
        )
        await conn.commit()

    resp = await scheduling_client.post(
        "/api/v1/scheduling/availability",
        json={
            "contractor_ids": [str(contractor_id)],
            "date": override_date.isoformat(),
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 1
    assert data[0]["free_windows"] == []
    # Should have a blocked interval with reason "time_off"
    reasons = [b["reason"] for b in data[0]["blocked_intervals"]]
    assert "time_off" in reasons


@pytest.mark.asyncio
async def test_free_windows_with_custom_override_hours(
    test_engine, scheduling_client, seed_contractor_weekly_schedule
):
    """Date override with custom hours 10am-2pm: returns only that window."""
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    company_id = seed_contractor_weekly_schedule["company_id"]
    override_date = date(2026, 3, 9)  # Monday

    async with test_engine.connect() as conn:
        # SET LOCAL requires direct string interpolation — no bind params (PostgreSQL limitation)
        await conn.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await conn.execute(
            text("""
                INSERT INTO contractor_date_overrides
                    (id, company_id, contractor_id, override_date, is_unavailable,
                     block_index, start_time, end_time, version, created_at, updated_at)
                VALUES (:id, :company_id, :cid, :override_date, false,
                    0, '10:00', '14:00', 1, now(), now())
            """),
            {
                "id": str(uuid.uuid4()),
                "company_id": str(company_id),
                "cid": str(contractor_id),
                "override_date": override_date,  # asyncpg needs date object, not string
            },
        )
        await conn.commit()

    resp = await scheduling_client.post(
        "/api/v1/scheduling/availability",
        json={
            "contractor_ids": [str(contractor_id)],
            "date": override_date.isoformat(),
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert len(data[0]["free_windows"]) >= 1
    # The window should cover the override period (10am-2pm Pacific)
    # In UTC that's 18:00-22:00 (PST = UTC-8 in March before DST)
    # The free window should span roughly 4 hours
    first_window = data[0]["free_windows"][0]
    start_dt = datetime.fromisoformat(first_window["start"])
    end_dt = datetime.fromisoformat(first_window["end"])
    duration_hours = (end_dt - start_dt).total_seconds() / 3600
    assert duration_hours >= 3.5  # ~4 hours


@pytest.mark.asyncio
async def test_contractor_inherits_company_default_working_hours(
    scheduling_client, scheduling_company_with_config, seed_contractor
):
    """Contractor with no personal weekly schedule inherits company default_working_hours."""
    # seed_contractor has NO weekly schedule — relies on company defaults (set in scheduling_company_with_config)
    contractor_id = seed_contractor["contractor_id"]

    resp = await scheduling_client.post(
        "/api/v1/scheduling/availability",
        json={
            "contractor_ids": [str(contractor_id)],
            "date": "2026-03-09",  # Monday
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 1
    # Company defaults have Mon-Fri working hours, so should get free windows
    assert len(data[0]["free_windows"]) >= 1


@pytest.mark.asyncio
async def test_booking_dst_boundary(
    test_engine, scheduling_client, seed_contractor_weekly_schedule
):
    """DST edge case: 2026-03-08 spring-forward in America/Vancouver.

    2026-03-08 is the spring-forward day (clocks go from 2:00 AM -> 3:00 AM PST -> PDT).
    A booking from 1am to 4am Pacific time crosses the DST transition:
    - 01:00 PST = 09:00 UTC
    - 04:00 PDT = 11:00 UTC (PDT = UTC-7)
    The booking in UTC is 09:00-11:00 (2 hours), NOT 3 hours as naive local time suggests.

    The day has only 23 hours. We seed working hours for Sunday (day_of_week=6)
    and verify the booking stores the correct UTC TSTZRANGE.
    """
    contractor_id = seed_contractor_weekly_schedule["contractor_id"]
    company_id = seed_contractor_weekly_schedule["company_id"]

    # Seed Sunday working hours (6=Sunday) to include the spring-forward day
    async with test_engine.connect() as conn:
        # SET LOCAL requires direct string interpolation — no bind params (PostgreSQL limitation)
        await conn.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await conn.execute(
            text("""
                INSERT INTO contractor_weekly_schedule
                    (id, company_id, contractor_id, day_of_week, block_index,
                     start_time, end_time, version, created_at, updated_at)
                VALUES (:id, :company_id, :cid, 6, 0, '00:00', '23:59', 1, now(), now())
            """),
            {
                "id": str(uuid.uuid4()),
                "company_id": str(company_id),
                "cid": str(contractor_id),
            },
        )
        await conn.commit()

    # Spring-forward: 2026-03-08 Sunday
    # 1:00 AM Pacific Standard Time = 09:00 UTC
    # 4:00 AM Pacific Daylight Time (after spring-forward) = 11:00 UTC
    # Naive calculation would suggest 3 hours; actual UTC interval is 2 hours
    tz_pacific = ZoneInfo("America/Vancouver")

    # Create datetimes in Pacific time for the booking
    # 1:00 AM PST
    local_start = datetime(2026, 3, 8, 1, 0, tzinfo=tz_pacific)
    # 4:00 AM PDT (after spring-forward at 2 AM)
    local_end = datetime(2026, 3, 8, 4, 0, tzinfo=tz_pacific)

    utc_start = local_start.astimezone(UTC)
    utc_end = local_end.astimezone(UTC)

    # UTC interval should be 2 hours (the 2 AM - 3 AM hour doesn't exist in Pacific time)
    actual_duration_hours = (utc_end - utc_start).total_seconds() / 3600
    assert actual_duration_hours == 2.0, (
        f"Expected 2 hours UTC duration across spring-forward, got {actual_duration_hours}"
    )

    # Verify UTC times are correct
    assert utc_start == datetime(2026, 3, 8, 9, 0, tzinfo=UTC), (
        f"Expected 09:00 UTC but got {utc_start}"
    )
    assert utc_end == datetime(2026, 3, 8, 11, 0, tzinfo=UTC), (
        f"Expected 11:00 UTC but got {utc_end}"
    )

    # Create the booking via API (using UTC times)
    job_id = seed_contractor_weekly_schedule["job_id"]
    resp = await scheduling_client.post(
        "/api/v1/scheduling/bookings",
        json={
            "contractor_id": str(contractor_id),
            "job_id": str(job_id),
            "start": utc_start.isoformat(),
            "end": utc_end.isoformat(),
        },
    )
    assert resp.status_code == 201, f"Booking failed: {resp.text}"
    booking_data = resp.json()

    # Verify stored UTC times are correct (not naive local-time arithmetic)
    stored_start = datetime.fromisoformat(booking_data["time_range_start"])
    stored_end = datetime.fromisoformat(booking_data["time_range_end"])

    # Convert to UTC for comparison
    stored_start_utc = stored_start.astimezone(UTC)
    stored_end_utc = stored_end.astimezone(UTC)

    assert stored_start_utc == utc_start, f"Expected {utc_start} but got {stored_start_utc}"
    assert stored_end_utc == utc_end, f"Expected {utc_end} but got {stored_end_utc}"

    # Duration in stored data should be 2 hours
    stored_duration = (stored_end_utc - stored_start_utc).total_seconds() / 3600
    assert stored_duration == 2.0, f"Expected 2-hour duration in UTC, got {stored_duration}"

    # Now check availability on 2026-03-08 — the booking should appear as blocked
    avail_resp = await scheduling_client.post(
        "/api/v1/scheduling/availability",
        json={
            "contractor_ids": [str(contractor_id)],
            "date": "2026-03-08",
        },
    )
    assert avail_resp.status_code == 200
    avail_data = avail_resp.json()
    blocked_reasons = [b["reason"] for b in avail_data[0]["blocked_intervals"]]
    assert "existing_job" in blocked_reasons
