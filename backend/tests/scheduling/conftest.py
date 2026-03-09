"""Scheduling-specific test fixtures extending base conftest.

These fixtures build on the base conftest.py infrastructure (clean_tables autouse,
test_engine session fixture, async_client) to provide scheduling domain objects:
  - A company with scheduling_config (min_duration, buffer, travel_margin, default_working_hours)
  - A contractor user with timezone='America/Vancouver' and home location set
  - Weekly schedule blocks for the contractor (Mon-Fri: 7-12 + 13-16)
  - A job site with known coordinates
  - A booking factory for seeding bookings at specified times
  - A pre-authenticated HTTP client for the scheduling tenant

Design: fixtures register the company via /auth/register (creates company + user + admin role),
then create the contractor directly in DB so we can set contractor-specific fields (timezone, home_lat/lng).
JWT tokens are created via create_test_token (test-only helper) for the contractor user.

Note on SET LOCAL: PostgreSQL SET LOCAL does not accept bind parameters — the company_id
must be interpolated directly into the SQL string. This is safe here because company_id
values come from UUID generation (uuid.uuid4()), not user input.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, time

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from app.core.security import create_test_token
from app.features.scheduling.schemas import SchedulingConfig
from app.main import app

# ---------------------------------------------------------------------------
# Shared seed: company + scheduling config + admin user
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture
async def scheduling_tenant(async_client):
    """Create a company via /auth/register and return tenant context.

    Returns dict with:
    - company_id: UUID of the created company
    - admin_token: JWT access token for the admin user
    - admin_user_id: UUID of the admin user
    """
    resp = await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "sched-admin@example.com",
            "password": "TestPass123!",
            "company_name": "Scheduling Test Co",
        },
    )
    assert resp.status_code == 201, f"Registration failed: {resp.text}"
    data = resp.json()
    return {
        "company_id": uuid.UUID(data["company_id"]),
        "admin_token": data["access_token"],
        "admin_user_id": uuid.UUID(data["user_id"]),
    }


@pytest_asyncio.fixture
async def scheduling_company_with_config(test_engine, scheduling_tenant):
    """Update the company with full scheduling_config.

    Sets:
    - min_duration=30 minutes
    - buffer=15 minutes
    - travel_margin=20%
    - default_working_hours Mon-Fri (0-4): two blocks per day (7-12, 13-16)
    - default_travel_time_minutes=30

    Returns scheduling_tenant dict (unchanged — company_id is the same).
    """
    config = SchedulingConfig(
        default_min_job_duration_minutes=30,
        default_buffer_minutes=15,
        default_travel_time_minutes=30,
        travel_margin_percent=20.0,
        default_working_hours={
            "0": [{"start": "07:00", "end": "12:00"}, {"start": "13:00", "end": "16:00"}],
            "1": [{"start": "07:00", "end": "12:00"}, {"start": "13:00", "end": "16:00"}],
            "2": [{"start": "07:00", "end": "12:00"}, {"start": "13:00", "end": "16:00"}],
            "3": [{"start": "07:00", "end": "12:00"}, {"start": "13:00", "end": "16:00"}],
            "4": [{"start": "07:00", "end": "12:00"}, {"start": "13:00", "end": "16:00"}],
        },
    )
    async with test_engine.connect() as conn:
        await conn.execute(
            text("UPDATE companies SET scheduling_config = :config WHERE id = :company_id"),
            {
                "config": config.model_dump_json(),
                "company_id": str(scheduling_tenant["company_id"]),
            },
        )
        await conn.commit()
    return scheduling_tenant


@pytest_asyncio.fixture
async def seed_contractor(test_engine, scheduling_company_with_config):
    """Create a contractor user with contractor role, timezone, and home location.

    Returns dict with:
    - contractor_id: UUID of the contractor user
    - contractor_token: JWT access token for the contractor
    - company_id: UUID of the company
    - admin_token: JWT access token for the admin
    """
    company_id = scheduling_company_with_config["company_id"]
    contractor_id = uuid.uuid4()

    async with test_engine.connect() as conn:
        # SET LOCAL requires direct string interpolation — no bind params (PostgreSQL limitation)
        await conn.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        # Insert contractor user
        await conn.execute(
            text("""
                INSERT INTO users (
                    id, company_id, email, password_hash, first_name, last_name,
                    timezone, home_address, home_latitude, home_longitude,
                    version, created_at, updated_at
                ) VALUES (
                    :id, :company_id, :email, :password_hash, :first_name, :last_name,
                    :timezone, :home_address, :home_lat, :home_lng,
                    1, now(), now()
                )
            """),
            {
                "id": str(contractor_id),
                "company_id": str(company_id),
                "email": "contractor@example.com",
                "password_hash": "hashed",
                "first_name": "Bob",
                "last_name": "Builder",
                "timezone": "America/Vancouver",
                "home_address": "123 Main St, Vancouver, BC",
                "home_lat": 49.283,
                "home_lng": -123.117,
            },
        )
        # Assign contractor role
        role_id = uuid.uuid4()
        await conn.execute(
            text("""
                INSERT INTO user_roles (id, company_id, user_id, role, version, created_at, updated_at)
                VALUES (:id, :company_id, :user_id, 'contractor', 1, now(), now())
            """),
            {
                "id": str(role_id),
                "company_id": str(company_id),
                "user_id": str(contractor_id),
            },
        )
        # Create schedule lock anchor row (contractor_schedule_locks has no RLS policy)
        await conn.execute(
            text("""
                INSERT INTO contractor_schedule_locks (contractor_id, company_id)
                VALUES (:contractor_id, :company_id)
                ON CONFLICT DO NOTHING
            """),
            {"contractor_id": str(contractor_id), "company_id": str(company_id)},
        )
        # Create a stub job so scheduling tests can use job_id in booking API calls.
        # Migration 0008 added bookings_job_id_fkey — booking inserts require a real jobs row.
        test_job_id = await _create_job_row(conn, company_id)
        await conn.commit()

    # Create JWT for contractor (long-lived for tests)
    contractor_token = create_test_token({
        "sub": str(contractor_id),
        "company_id": str(company_id),
        "roles": ["contractor"],
        "type": "access",
        "exp": datetime(2099, 1, 1, tzinfo=UTC).timestamp(),
    })

    return {
        "contractor_id": contractor_id,
        "contractor_token": contractor_token,
        "company_id": company_id,
        "admin_token": scheduling_company_with_config["admin_token"],
        "job_id": test_job_id,
    }


@pytest_asyncio.fixture
async def seed_contractor_weekly_schedule(test_engine, seed_contractor):
    """Seed Mon-Fri weekly schedule blocks for the contractor.

    Each workday (0=Mon through 4=Fri) gets two blocks:
    - Block 0: 07:00-12:00 (morning)
    - Block 1: 13:00-16:00 (afternoon, after 1-hr lunch)

    Returns seed_contractor dict (unchanged).
    """
    contractor_id = seed_contractor["contractor_id"]
    company_id = seed_contractor["company_id"]

    async with test_engine.connect() as conn:
        # SET LOCAL requires direct string interpolation — no bind params (PostgreSQL limitation)
        await conn.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        for day_of_week in range(5):  # 0=Mon ... 4=Fri
            for block_index, (start_h, end_h) in enumerate([(7, 12), (13, 16)]):
                block_id = uuid.uuid4()
                await conn.execute(
                    text("""
                        INSERT INTO contractor_weekly_schedule
                            (id, company_id, contractor_id, day_of_week, block_index,
                             start_time, end_time, version, created_at, updated_at)
                        VALUES
                            (:id, :company_id, :contractor_id, :dow, :bidx,
                             :start_time, :end_time, 1, now(), now())
                    """),
                    {
                        "id": str(block_id),
                        "company_id": str(company_id),
                        "contractor_id": str(contractor_id),
                        "dow": day_of_week,
                        "bidx": block_index,
                        "start_time": time(start_h, 0),
                        "end_time": time(end_h, 0),
                    },
                )
        await conn.commit()

    return seed_contractor


@pytest_asyncio.fixture
async def seed_job_site(test_engine, seed_contractor):
    """Create a job site with known coordinates near downtown Vancouver.

    Returns dict with job_site_id and lat/lng.
    """
    job_site_id = uuid.uuid4()
    company_id = seed_contractor["company_id"]
    lat = 49.282
    lng = -123.120

    async with test_engine.connect() as conn:
        # SET LOCAL requires direct string interpolation — no bind params (PostgreSQL limitation)
        await conn.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await conn.execute(
            text("""
                INSERT INTO job_sites (id, company_id, address, latitude, longitude, version, created_at, updated_at)
                VALUES (:id, :company_id, :address, :lat, :lng, 1, now(), now())
            """),
            {
                "id": str(job_site_id),
                "company_id": str(company_id),
                "address": "456 Test Ave, Vancouver, BC",
                "lat": lat,
                "lng": lng,
            },
        )
        await conn.commit()

    return {
        "job_site_id": job_site_id,
        "latitude": lat,
        "longitude": lng,
        "contractor_id": seed_contractor["contractor_id"],
        "company_id": company_id,
    }


async def _create_job_row(conn, company_id: uuid.UUID) -> uuid.UUID:
    """Insert a minimal jobs row and return its id.

    The jobs table now requires a valid jobs.id FK on bookings (migration 0008).
    This helper creates a stub job for test fixtures so booking inserts satisfy
    the FK constraint. Uses TRUNCATE-safe defaults (status=quote, priority=medium).
    """
    job_id = uuid.uuid4()
    await conn.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
    await conn.execute(
        text("""
            INSERT INTO jobs (id, company_id, description, trade_type, version, created_at, updated_at)
            VALUES (:id, :company_id, :description, :trade_type, 1, now(), now())
        """),
        {
            "id": str(job_id),
            "company_id": str(company_id),
            "description": "Test job for scheduling fixtures",
            "trade_type": "general",
        },
    )
    return job_id


@pytest_asyncio.fixture
def booking_factory(test_engine, seed_contractor):
    """Factory fixture for creating bookings at specified UTC times.

    Usage:
        booking_id = await booking_factory(start=datetime(..., tzinfo=UTC), end=datetime(..., tzinfo=UTC))

    Note: Creates a real jobs row per booking to satisfy the bookings_job_id_fkey
    FK constraint added in migration 0008.
    """
    contractor_id = seed_contractor["contractor_id"]
    company_id = seed_contractor["company_id"]

    async def make_booking(start: datetime, end: datetime, job_site_id=None, notes=None):
        booking_id = uuid.uuid4()
        async with test_engine.connect() as conn:
            # SET LOCAL requires direct string interpolation — no bind params
            await conn.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
            # Create a stub job to satisfy bookings_job_id_fkey (migration 0008)
            job_id = await _create_job_row(conn, company_id)
            await conn.execute(
                text("""
                    INSERT INTO bookings
                        (id, company_id, contractor_id, job_id, job_site_id,
                         time_range, version, created_at, updated_at)
                    VALUES
                        (:id, :company_id, :contractor_id, :job_id, :job_site_id,
                         tstzrange(:start, :end, '[)'), 1, now(), now())
                """),
                {
                    "id": str(booking_id),
                    "company_id": str(company_id),
                    "contractor_id": str(contractor_id),
                    "job_id": str(job_id),
                    "job_site_id": str(job_site_id) if job_site_id else None,
                    "start": start.isoformat(),
                    "end": end.isoformat(),
                },
            )
            await conn.commit()
        return booking_id

    return make_booking


@pytest_asyncio.fixture
async def scheduling_client(seed_contractor):
    """Async HTTP client authenticated as the admin user for the scheduling tenant.

    Uses the admin JWT token which has access to all scheduling endpoints.
    The admin registers the company via /auth/register so company_id is embedded in the JWT.
    """
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"Authorization": f"Bearer {seed_contractor['admin_token']}"},
    ) as ac:
        yield ac


@pytest_asyncio.fixture
async def contractor_client(seed_contractor):
    """Async HTTP client authenticated as the contractor user."""
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"Authorization": f"Bearer {seed_contractor['contractor_token']}"},
    ) as ac:
        yield ac
