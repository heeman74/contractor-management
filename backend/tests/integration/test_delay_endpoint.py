"""Integration tests for PATCH /jobs/{job_id}/delay endpoint.

Tests the full stack: HTTP request -> FastAPI router -> JobService.report_delay
-> PostgreSQL RLS. All tests use JWT Bearer token authentication per CLAUDE.md.

Endpoint: PATCH /api/v1/jobs/{job_id}/delay
Schema: DelayReportRequest {reason: str (min_length=1), new_eta: date, version: int}

Test coverage:
1. Happy path — scheduled job, valid delay report
2. Wrong status — cannot delay a completed job
3. Version conflict — stale version returns 409
4. Not found — random UUID returns 404
5. Multiple delays — both entries in status_history, latest ETA wins
6. In-progress status — delay is valid for in_progress too
7. Empty reason — min_length=1 validation returns 422

Fixtures from conftest.py:
- tenant_a_client: pre-authenticated async client for Tenant A
- seed_two_tenants: company IDs, user IDs, and tokens
- clean_tables (autouse): truncates all tables before each test
"""

from datetime import date, timedelta

import pytest

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------


async def create_job_at_status(client, target_status: str) -> dict:
    """Create a job and advance it to the given target status.

    Progression: quote -> scheduled -> in_progress -> complete -> invoiced
    Returns the final job JSON.
    """
    resp = await client.post(
        "/api/v1/jobs/",
        json={
            "description": "Test job for delay endpoint tests",
            "trade_type": "plumber",
            "priority": "medium",
        },
    )
    assert resp.status_code == 201, f"Job creation failed: {resp.text}"
    job = resp.json()

    progression = ["quote", "scheduled", "in_progress", "complete", "invoiced"]
    if target_status == "quote":
        return job

    start_idx = 0  # job starts at quote
    end_idx = progression.index(target_status)

    for i in range(start_idx, end_idx):
        to_status = progression[i + 1]
        resp = await client.patch(
            f"/api/v1/jobs/{job['id']}/transition",
            json={"new_status": to_status, "version": job["version"]},
        )
        assert resp.status_code == 200, f"Transition to {to_status} failed: {resp.text}"
        job = resp.json()

    return job


def future_date(days_ahead: int = 7) -> str:
    """Return an ISO date string [days_ahead] days from today."""
    return (date.today() + timedelta(days=days_ahead)).isoformat()


# ---------------------------------------------------------------------------
# Test 1: Happy path — scheduled job
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_report_delay_happy_path(tenant_a_client, seed_two_tenants):
    """PATCH /jobs/{id}/delay with valid data on a scheduled job returns 200.

    Verifies:
    - Response status is 200
    - scheduled_completion_date updated to new_eta
    - status_history has a new delay entry with type="delay" and reason
    - version incremented
    """
    job = await create_job_at_status(tenant_a_client, "scheduled")
    job_id = job["id"]
    new_eta = future_date(14)
    original_version = job["version"]
    original_history_len = len(job["status_history"])

    resp = await tenant_a_client.patch(
        f"/api/v1/jobs/{job_id}/delay",
        json={
            "reason": "Waiting for materials to arrive from supplier",
            "new_eta": new_eta,
            "version": original_version,
        },
    )
    assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
    body = resp.json()

    # Completion date updated
    assert body["scheduled_completion_date"] == new_eta

    # Version incremented
    assert body["version"] == original_version + 1

    # Delay entry appended to status_history
    assert len(body["status_history"]) == original_history_len + 1
    delay_entry = body["status_history"][-1]
    assert delay_entry.get("type") == "delay"
    assert delay_entry.get("reason") == "Waiting for materials to arrive from supplier"
    assert "new_eta" in delay_entry
    assert "timestamp" in delay_entry
    assert "user_id" in delay_entry


# ---------------------------------------------------------------------------
# Test 2: Wrong status — cannot delay a completed job
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_report_delay_wrong_status(tenant_a_client, seed_two_tenants):
    """PATCH /jobs/{id}/delay on a complete-status job returns 422.

    The delay endpoint only allows 'scheduled' and 'in_progress' jobs.
    Attempting to delay a completed job should return 422.
    """
    job = await create_job_at_status(tenant_a_client, "complete")
    job_id = job["id"]

    resp = await tenant_a_client.patch(
        f"/api/v1/jobs/{job_id}/delay",
        json={
            "reason": "Some delay reason",
            "new_eta": future_date(7),
            "version": job["version"],
        },
    )
    assert resp.status_code == 422, (
        f"Expected 422 for wrong status, got {resp.status_code}: {resp.text}"
    )
    body = resp.json()
    # Error message should mention status
    detail = str(body.get("detail", ""))
    assert (
        "complete" in detail.lower() or "scheduled" in detail.lower() or "status" in detail.lower()
    )


# ---------------------------------------------------------------------------
# Test 3: Version conflict
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_report_delay_version_conflict(tenant_a_client, seed_two_tenants):
    """PATCH /jobs/{id}/delay with wrong version returns 409 Conflict.

    Client sends version=1 but current job version is 2+ (after transition).
    Server must reject with 409 to prevent data loss from stale clients.
    """
    job = await create_job_at_status(tenant_a_client, "scheduled")
    job_id = job["id"]
    current_version = job["version"]

    # Deliberately send a stale version (current - 1)
    stale_version = current_version - 1
    resp = await tenant_a_client.patch(
        f"/api/v1/jobs/{job_id}/delay",
        json={
            "reason": "Delay reason",
            "new_eta": future_date(7),
            "version": stale_version,
        },
    )
    assert resp.status_code == 409, (
        f"Expected 409 version conflict, got {resp.status_code}: {resp.text}"
    )


# ---------------------------------------------------------------------------
# Test 4: Not found — random UUID
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_report_delay_not_found(tenant_a_client, seed_two_tenants):
    """PATCH /jobs/{random_uuid}/delay returns 404 when job doesn't exist."""
    import uuid

    random_job_id = str(uuid.uuid4())
    resp = await tenant_a_client.patch(
        f"/api/v1/jobs/{random_job_id}/delay",
        json={
            "reason": "Delay reason",
            "new_eta": future_date(7),
            "version": 1,
        },
    )
    assert resp.status_code == 404, (
        f"Expected 404 for missing job, got {resp.status_code}: {resp.text}"
    )


# ---------------------------------------------------------------------------
# Test 5: Multiple delays — both appended, latest ETA wins
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_report_delay_multiple(tenant_a_client, seed_two_tenants):
    """PATCH delay twice: both entries in status_history, final ETA = second call.

    Verifies that delay entries accumulate in status_history and that
    scheduled_completion_date reflects the most recent ETA.
    """
    job = await create_job_at_status(tenant_a_client, "scheduled")
    job_id = job["id"]
    original_history_len = len(job["status_history"])

    # First delay report
    first_eta = future_date(7)
    resp1 = await tenant_a_client.patch(
        f"/api/v1/jobs/{job_id}/delay",
        json={
            "reason": "First delay: waiting for parts",
            "new_eta": first_eta,
            "version": job["version"],
        },
    )
    assert resp1.status_code == 200, f"First delay failed: {resp1.text}"
    job_after_first = resp1.json()

    assert job_after_first["scheduled_completion_date"] == first_eta
    assert len(job_after_first["status_history"]) == original_history_len + 1

    # Second delay report (using updated version from first response)
    second_eta = future_date(14)
    resp2 = await tenant_a_client.patch(
        f"/api/v1/jobs/{job_id}/delay",
        json={
            "reason": "Second delay: weather conditions",
            "new_eta": second_eta,
            "version": job_after_first["version"],
        },
    )
    assert resp2.status_code == 200, f"Second delay failed: {resp2.text}"
    job_after_second = resp2.json()

    # scheduled_completion_date = latest ETA
    assert job_after_second["scheduled_completion_date"] == second_eta

    # Two delay entries in history (both delays + original status entry)
    assert len(job_after_second["status_history"]) == original_history_len + 2

    delay_entries = [
        entry for entry in job_after_second["status_history"] if entry.get("type") == "delay"
    ]
    assert len(delay_entries) == 2
    reasons = [e["reason"] for e in delay_entries]
    assert "First delay: waiting for parts" in reasons
    assert "Second delay: weather conditions" in reasons


# ---------------------------------------------------------------------------
# Test 6: In-progress status — delay valid
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_report_delay_in_progress(tenant_a_client, seed_two_tenants):
    """PATCH /jobs/{id}/delay on an in_progress job returns 200.

    Delays are valid for both 'scheduled' and 'in_progress' statuses.
    """
    job = await create_job_at_status(tenant_a_client, "in_progress")
    job_id = job["id"]
    new_eta = future_date(10)
    original_version = job["version"]

    resp = await tenant_a_client.patch(
        f"/api/v1/jobs/{job_id}/delay",
        json={
            "reason": "Work is taking longer than estimated",
            "new_eta": new_eta,
            "version": original_version,
        },
    )
    assert resp.status_code == 200, (
        f"Expected 200 for in_progress delay, got {resp.status_code}: {resp.text}"
    )
    body = resp.json()
    assert body["scheduled_completion_date"] == new_eta
    assert body["version"] == original_version + 1

    delay_entry = body["status_history"][-1]
    assert delay_entry.get("type") == "delay"
    assert delay_entry.get("reason") == "Work is taking longer than estimated"


# ---------------------------------------------------------------------------
# Test 7: Empty reason — Pydantic min_length=1 validation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_report_delay_empty_reason(tenant_a_client, seed_two_tenants):
    """PATCH /jobs/{id}/delay with empty reason string returns 422.

    DelayReportRequest.reason has min_length=1 in Pydantic schema.
    An empty string must be rejected before reaching the service layer.
    """
    job = await create_job_at_status(tenant_a_client, "scheduled")
    job_id = job["id"]

    resp = await tenant_a_client.patch(
        f"/api/v1/jobs/{job_id}/delay",
        json={
            "reason": "",
            "new_eta": future_date(7),
            "version": job["version"],
        },
    )
    assert resp.status_code == 422, (
        f"Expected 422 for empty reason, got {resp.status_code}: {resp.text}"
    )
