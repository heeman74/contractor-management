"""Integration tests for Phase 6 field workflow endpoints.

Tests cover:
- POST /jobs/{job_id}/notes — create note
- GET /jobs/{job_id}/notes — list notes newest first
- POST /jobs/{job_id}/time-entries — clock in (create time entry)
- PATCH /jobs/{job_id}/time-entries/{id} — clock out
- PATCH /jobs/{job_id}/time-entries/{id}/adjust — admin adjustment
- GET /jobs/{job_id}/time-entries — list time entries
- POST /files/upload — file upload
- RLS cross-tenant isolation for notes and time entries

All tests use JWT Bearer token authentication via conftest.py fixtures.
The clean_tables fixture (autouse) truncates all tables before each test
including the Phase 6 tables: job_notes, time_entries, attachments.
"""

from __future__ import annotations

import io
from datetime import UTC, datetime

import pytest
from httpx import AsyncClient


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def create_test_job(client: AsyncClient, **overrides) -> dict:
    """Create a minimal job and return the JSON response."""
    payload = {
        "description": "Fix leaking boiler",
        "trade_type": "plumber",
        "priority": "medium",
    }
    payload.update(overrides)
    resp = await client.post("/api/v1/jobs/", json=payload)
    assert resp.status_code == 201, f"Job creation failed: {resp.text}"
    return resp.json()


async def create_test_note(client: AsyncClient, job_id: str, body: str = "Test note") -> dict:
    """Create a note and return the JSON response."""
    resp = await client.post(
        f"/api/v1/jobs/{job_id}/notes",
        json={"body": body},
    )
    assert resp.status_code == 201, f"Note creation failed: {resp.text}"
    return resp.json()


async def clock_in(client: AsyncClient, job_id: str) -> dict:
    """Clock in to a job and return the time entry JSON."""
    now = datetime.now(UTC).isoformat()
    resp = await client.post(
        f"/api/v1/jobs/{job_id}/time-entries",
        json={"clocked_in_at": now},
    )
    assert resp.status_code == 201, f"Clock-in failed: {resp.text}"
    return resp.json()


# ---------------------------------------------------------------------------
# Notes tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_note(tenant_a_client, seed_two_tenants):
    """POST /jobs/{job_id}/notes creates a note with 201 status."""
    job = await create_test_job(tenant_a_client)
    job_id = job["id"]

    resp = await tenant_a_client.post(
        f"/api/v1/jobs/{job_id}/notes",
        json={"body": "Inspected the boiler — rust on inlet pipe."},
    )

    assert resp.status_code == 201
    body = resp.json()
    assert body["body"] == "Inspected the boiler — rust on inlet pipe."
    assert body["job_id"] == job_id
    assert "id" in body
    assert "created_at" in body
    assert body["attachments"] == []


@pytest.mark.asyncio
async def test_list_notes_newest_first(tenant_a_client, seed_two_tenants):
    """GET /jobs/{job_id}/notes returns notes ordered newest first."""
    job = await create_test_job(tenant_a_client)
    job_id = job["id"]

    await create_test_note(tenant_a_client, job_id, body="First note")
    await create_test_note(tenant_a_client, job_id, body="Second note")
    await create_test_note(tenant_a_client, job_id, body="Third note")

    resp = await tenant_a_client.get(f"/api/v1/jobs/{job_id}/notes")
    assert resp.status_code == 200

    notes = resp.json()
    assert len(notes) == 3

    # Newest first — Third note should be at index 0
    assert notes[0]["body"] == "Third note"
    assert notes[1]["body"] == "Second note"
    assert notes[2]["body"] == "First note"


@pytest.mark.asyncio
async def test_create_note_exact_max_length_succeeds(tenant_a_client, seed_two_tenants):
    """POST /jobs/{job_id}/notes with exactly 2000 chars body succeeds (boundary value)."""
    job = await create_test_job(tenant_a_client)
    job_id = job["id"]

    resp = await tenant_a_client.post(
        f"/api/v1/jobs/{job_id}/notes",
        json={"body": "x" * 2000},
    )

    assert resp.status_code == 201


@pytest.mark.asyncio
async def test_create_note_body_too_long_returns_422(tenant_a_client, seed_two_tenants):
    """POST /jobs/{job_id}/notes with body > 2000 chars returns 422 validation error."""
    job = await create_test_job(tenant_a_client)
    job_id = job["id"]

    resp = await tenant_a_client.post(
        f"/api/v1/jobs/{job_id}/notes",
        json={"body": "x" * 2001},
    )

    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_create_note_on_missing_job_returns_404(tenant_a_client, seed_two_tenants):
    """POST /jobs/{job_id}/notes with non-existent job_id returns 404."""
    import uuid

    fake_id = str(uuid.uuid4())
    resp = await tenant_a_client.post(
        f"/api/v1/jobs/{fake_id}/notes",
        json={"body": "This job doesn't exist."},
    )

    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# Time entries tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_time_entry_clock_in(tenant_a_client, seed_two_tenants):
    """POST /jobs/{job_id}/time-entries creates an active time entry (201)."""
    job = await create_test_job(tenant_a_client)
    job_id = job["id"]

    now = datetime.now(UTC).isoformat()
    resp = await tenant_a_client.post(
        f"/api/v1/jobs/{job_id}/time-entries",
        json={"clocked_in_at": now},
    )

    assert resp.status_code == 201
    entry = resp.json()
    assert entry["job_id"] == job_id
    assert entry["session_status"] == "active"
    assert entry["clocked_out_at"] is None
    assert entry["duration_seconds"] is None
    assert "id" in entry
    assert "clocked_in_at" in entry


@pytest.mark.asyncio
async def test_clock_out_time_entry(tenant_a_client, seed_two_tenants):
    """PATCH /jobs/{job_id}/time-entries/{id} clocks out an active session."""
    job = await create_test_job(tenant_a_client)
    job_id = job["id"]

    # Clock in first
    entry = await clock_in(tenant_a_client, job_id)
    entry_id = entry["id"]

    # Clock out
    clocked_out = datetime.now(UTC).isoformat()
    resp = await tenant_a_client.patch(
        f"/api/v1/jobs/{job_id}/time-entries/{entry_id}",
        json={"clocked_out_at": clocked_out},
    )

    assert resp.status_code == 200
    updated = resp.json()
    assert updated["id"] == entry_id
    assert updated["session_status"] == "completed"
    assert updated["clocked_out_at"] is not None
    assert updated["duration_seconds"] is not None
    assert updated["duration_seconds"] >= 0


@pytest.mark.asyncio
async def test_auto_close_active_session_on_new_clock_in(tenant_a_client, seed_two_tenants):
    """POST new time entry auto-closes any previous active session for same contractor."""
    job1 = await create_test_job(tenant_a_client, description="Job 1")
    job2 = await create_test_job(tenant_a_client, description="Job 2")

    # Clock in to job 1
    entry1 = await clock_in(tenant_a_client, job1["id"])

    # Clock in to job 2 — should auto-close entry1
    now2 = datetime.now(UTC).isoformat()
    entry2_resp = await tenant_a_client.post(
        f"/api/v1/jobs/{job2['id']}/time-entries",
        json={"clocked_in_at": now2},
    )
    assert entry2_resp.status_code == 201

    # Verify entry1 was auto-closed
    entries1_resp = await tenant_a_client.get(f"/api/v1/jobs/{job1['id']}/time-entries")
    assert entries1_resp.status_code == 200
    entries1 = entries1_resp.json()
    assert len(entries1) == 1
    closed_entry = entries1[0]
    assert closed_entry["id"] == entry1["id"]
    assert closed_entry["session_status"] == "completed"
    assert closed_entry["clocked_out_at"] is not None


@pytest.mark.asyncio
async def test_adjust_time_entry(tenant_a_client, seed_two_tenants):
    """PATCH /jobs/{job_id}/time-entries/{id}/adjust updates times with audit trail."""
    job = await create_test_job(tenant_a_client)
    job_id = job["id"]

    # Create and close a time entry
    entry = await clock_in(tenant_a_client, job_id)
    entry_id = entry["id"]
    clocked_out_now = datetime.now(UTC).isoformat()
    await tenant_a_client.patch(
        f"/api/v1/jobs/{job_id}/time-entries/{entry_id}",
        json={"clocked_out_at": clocked_out_now},
    )

    # Adjust times
    new_clocked_in = "2025-01-15T09:00:00Z"
    new_clocked_out = "2025-01-15T11:00:00Z"
    resp = await tenant_a_client.patch(
        f"/api/v1/jobs/{job_id}/time-entries/{entry_id}/adjust",
        json={
            "clocked_in_at": new_clocked_in,
            "clocked_out_at": new_clocked_out,
            "reason": "Correcting incorrect start time",
        },
    )

    assert resp.status_code == 200
    adjusted = resp.json()
    assert adjusted["id"] == entry_id
    assert adjusted["session_status"] == "adjusted"
    assert adjusted["duration_seconds"] == 7200  # 2 hours
    # adjustment_log should be a JSON array with one entry
    assert adjusted["adjustment_log"] is not None


@pytest.mark.asyncio
async def test_list_time_entries_ordered_desc(tenant_a_client, seed_two_tenants):
    """GET /jobs/{job_id}/time-entries returns entries ordered by clocked_in_at DESC."""
    job = await create_test_job(tenant_a_client)
    job_id = job["id"]

    # Create first entry and close it
    entry1 = await clock_in(tenant_a_client, job_id)
    clocked_out_1 = datetime.now(UTC).isoformat()
    await tenant_a_client.patch(
        f"/api/v1/jobs/{job_id}/time-entries/{entry1['id']}",
        json={"clocked_out_at": clocked_out_1},
    )

    # Create second entry
    await clock_in(tenant_a_client, job_id)

    resp = await tenant_a_client.get(f"/api/v1/jobs/{job_id}/time-entries")
    assert resp.status_code == 200

    entries = resp.json()
    assert len(entries) == 2
    # Most recent (second) entry should appear first
    first_clocked_in = entries[0]["clocked_in_at"]
    second_clocked_in = entries[1]["clocked_in_at"]
    assert first_clocked_in >= second_clocked_in


# ---------------------------------------------------------------------------
# File upload tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_upload_file(tenant_a_client, seed_two_tenants):
    """POST /api/v1/files/upload with valid file and auth returns 201 with remote_url."""
    job = await create_test_job(tenant_a_client)
    note = await create_test_note(tenant_a_client, job["id"])
    note_id = note["id"]

    # Create a minimal PNG-like byte stream
    file_content = b"\x89PNG\r\n\x1a\n" + b"\x00" * 100
    files = {
        "file": ("test_photo.png", io.BytesIO(file_content), "image/png"),
    }
    data = {
        "note_id": note_id,
        "attachment_type": "photo",
    }

    resp = await tenant_a_client.post(
        "/api/v1/files/upload",
        files=files,
        data=data,
    )

    assert resp.status_code == 201
    attachment = resp.json()
    assert attachment["note_id"] == note_id
    assert attachment["attachment_type"] == "photo"
    assert "remote_url" in attachment
    assert "/files/attachments/" in attachment["remote_url"]
    assert "id" in attachment


@pytest.mark.asyncio
async def test_upload_file_without_auth(async_client, seed_two_tenants):
    """POST /api/v1/files/upload without auth token returns 401."""
    # seed_two_tenants ensures migrations ran; async_client has no auth header
    job_id = "00000000-0000-0000-0000-000000000001"
    note_id = "00000000-0000-0000-0000-000000000002"

    files = {
        "file": ("test.png", io.BytesIO(b"fake"), "image/png"),
    }
    data = {
        "note_id": note_id,
        "attachment_type": "photo",
    }

    resp = await async_client.post(
        "/api/v1/files/upload",
        files=files,
        data=data,
    )

    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_upload_invalid_attachment_type(tenant_a_client, seed_two_tenants):
    """POST /api/v1/files/upload with invalid attachment_type returns 400."""
    job = await create_test_job(tenant_a_client)
    note = await create_test_note(tenant_a_client, job["id"])

    files = {
        "file": ("test.png", io.BytesIO(b"fake"), "image/png"),
    }
    data = {
        "note_id": note["id"],
        "attachment_type": "video",  # invalid
    }

    resp = await tenant_a_client.post(
        "/api/v1/files/upload",
        files=files,
        data=data,
    )

    assert resp.status_code == 400


# ---------------------------------------------------------------------------
# RLS isolation tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_rls_note_cross_tenant_isolation(
    tenant_a_client, tenant_b_client, seed_two_tenants
):
    """Notes created by Tenant A are NOT visible to Tenant B (RLS enforced)."""
    # Tenant A creates a job and note
    job_a = await create_test_job(tenant_a_client, description="Tenant A's job")
    note_a = await create_test_note(tenant_a_client, job_a["id"], body="A secret note")

    # Tenant B creates their own job
    job_b = await create_test_job(tenant_b_client, description="Tenant B's job")

    # Tenant B lists notes for their own job — should be empty
    resp_b = await tenant_b_client.get(f"/api/v1/jobs/{job_b['id']}/notes")
    assert resp_b.status_code == 200
    assert resp_b.json() == []

    # Tenant B tries to list Tenant A's job notes — 404 because job is not visible to B
    resp_cross = await tenant_b_client.get(f"/api/v1/jobs/{job_a['id']}/notes")
    # RLS hides the job entirely — expect empty list or 404
    # Either is acceptable: the note is NOT in the response
    if resp_cross.status_code == 200:
        notes = resp_cross.json()
        note_ids = [n["id"] for n in notes]
        assert note_a["id"] not in note_ids, "Tenant B must not see Tenant A's notes"
    else:
        assert resp_cross.status_code == 404


@pytest.mark.asyncio
async def test_rls_time_entry_cross_tenant_isolation(
    tenant_a_client, tenant_b_client, seed_two_tenants
):
    """Time entries created by Tenant A are NOT visible to Tenant B (RLS enforced)."""
    # Tenant A creates a job and clocks in
    job_a = await create_test_job(tenant_a_client, description="Tenant A's job")
    entry_a = await clock_in(tenant_a_client, job_a["id"])

    # Tenant B creates their own job
    job_b = await create_test_job(tenant_b_client, description="Tenant B's job")

    # Tenant B lists time entries for their own job — should be empty
    resp_b = await tenant_b_client.get(f"/api/v1/jobs/{job_b['id']}/time-entries")
    assert resp_b.status_code == 200
    assert resp_b.json() == []

    # Tenant B tries to access Tenant A's job time entries — should not see them
    resp_cross = await tenant_b_client.get(f"/api/v1/jobs/{job_a['id']}/time-entries")
    if resp_cross.status_code == 200:
        entries = resp_cross.json()
        entry_ids = [e["id"] for e in entries]
        assert entry_a["id"] not in entry_ids, "Tenant B must not see Tenant A's time entries"
    else:
        assert resp_cross.status_code == 404
