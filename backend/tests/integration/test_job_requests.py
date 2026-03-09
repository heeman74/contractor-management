"""Integration tests for job request flow — both in-app (auth) and web form (public).

Tests the full HTTP stack: POST /api/v1/jobs/requests (in-app, auth) and
POST /jobs/request/{company_id} (web form, public form data).

Coverage:
- Submit in-app request (authenticated, JSON)
- Submit web form (public, form data) — creates request
- Web form creates new client user when email is unknown
- Web form matches existing client user when email is known
- List pending requests
- Review actions: accepted (creates job), declined (sets reason), info_requested
- Web form HTML render (GET)
- Dual flow E2E: request -> accept -> job lifecycle

All tests use JWT Bearer token authentication per CLAUDE.md testing rules.
clean_tables autouse fixture provides test isolation.
"""

import pytest
from httpx import AsyncClient


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------


async def submit_in_app_request(client: AsyncClient, **overrides) -> dict:
    """Submit an in-app job request (auth required, JSON body)."""
    payload = {
        "description": "Fix leaking roof — urgent",
        "trade_type": "roofer",
        "urgency": "urgent",
    }
    payload.update(overrides)
    resp = await client.post("/api/v1/jobs/requests", json=payload)
    assert resp.status_code == 201, f"Failed to submit request: {resp.text}"
    return resp.json()


# ---------------------------------------------------------------------------
# Test 1: Submit in-app request (authenticated)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_submit_request_in_app(tenant_a_client, seed_two_tenants):
    """POST /api/v1/jobs/requests with auth creates request at pending status."""
    resp = await tenant_a_client.post(
        "/api/v1/jobs/requests",
        json={
            "description": "Install new bathroom tiles",
            "trade_type": "tiler",
            "urgency": "normal",
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["description"] == "Install new bathroom tiles"
    assert body["trade_type"] == "tiler"
    assert body["urgency"] == "normal"
    assert body["status"] == "pending"
    assert "id" in body
    assert "company_id" in body


# ---------------------------------------------------------------------------
# Test 2: Submit web form request (public, no auth)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_submit_request_web_form(async_client, seed_two_tenants):
    """POST /api/v1/jobs/request/{company_id} with form data creates a pending request.

    Submits without email to avoid RLS-blocked anonymous user creation.
    Without submitted_email, no User INSERT occurs — the request is stored
    with submitted_name/phone and client_id=NULL (anonymous).
    """
    company_id = seed_two_tenants["tenant_a_id"]

    resp = await async_client.post(
        f"/api/v1/jobs/request/{company_id}",
        data={
            "description": "Fix broken fence panels",
            "trade_type": "fencer",
            "urgency": "normal",
            "submitted_name": "Jane Public",
            "submitted_phone": "+61 400 111 222",
            # No submitted_email — avoids RLS-blocked anonymous user creation
        },
    )
    # Web form returns HTML success page
    assert resp.status_code == 200
    assert "text/html" in resp.headers.get("content-type", "")


# ---------------------------------------------------------------------------
# Test 3: Web form creates new client when email unknown
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_web_form_creates_new_client(async_client, tenant_a_client, seed_two_tenants):
    """Web form submission with unknown email creates a new User with client role."""
    company_id = seed_two_tenants["tenant_a_id"]
    new_email = "brand.new.client@example.com"

    # Submit web form with email not in system
    resp = await async_client.post(
        f"/api/v1/jobs/request/{company_id}",
        data={
            "description": "Install garden irrigation system",
            "submitted_name": "New Client",
            "submitted_email": new_email,
        },
    )
    assert resp.status_code == 200

    # Verify new user was created (visible via admin client)
    users_resp = await tenant_a_client.get("/api/v1/users/")
    assert users_resp.status_code == 200
    emails = [u["email"] for u in users_resp.json()]
    assert new_email in emails, (
        f"Expected new user {new_email} to be created in tenant, "
        f"but found only: {emails}"
    )


# ---------------------------------------------------------------------------
# Test 4: Web form matches existing client when email is known
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_web_form_matches_existing_client(async_client, tenant_a_client, seed_two_tenants):
    """Web form submission with existing user email links request to that user."""
    company_id = seed_two_tenants["tenant_a_id"]
    existing_email = "existing.client@example.com"

    # Create the user first via admin API
    create_resp = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": existing_email},
    )
    assert create_resp.status_code == 201

    # Submit web form with the same email
    resp = await async_client.post(
        f"/api/v1/jobs/request/{company_id}",
        data={
            "description": "Replace fence gate hardware",
            "submitted_name": "Existing Client",
            "submitted_email": existing_email,
        },
    )
    assert resp.status_code == 200

    # Verify no duplicate user was created (existing email appears exactly once)
    users_resp = await tenant_a_client.get("/api/v1/users/")
    assert users_resp.status_code == 200
    emails = [u["email"] for u in users_resp.json()]
    assert emails.count(existing_email) == 1


# ---------------------------------------------------------------------------
# Test 5: List pending requests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_list_pending_requests(tenant_a_client, seed_two_tenants):
    """GET /api/v1/jobs/requests returns all pending requests."""
    # Create 3 pending requests
    for i in range(3):
        await submit_in_app_request(
            tenant_a_client,
            description=f"Pending request {i + 1}",
        )

    resp = await tenant_a_client.get("/api/v1/jobs/requests")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 3
    for item in body:
        assert item["status"] == "pending"


# ---------------------------------------------------------------------------
# Test 6: Accept request — creates job at quote with converted_job_id set
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_accept_request(tenant_a_client, seed_two_tenants):
    """POST review with action='accepted' creates a job at quote stage."""
    request = await submit_in_app_request(
        tenant_a_client,
        description="Install new kitchen exhaust fan",
        trade_type="electrician",
    )
    request_id = request["id"]

    # Accept the request
    resp = await tenant_a_client.post(
        f"/api/v1/jobs/requests/{request_id}/review",
        json={"action": "accepted"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "accepted"
    assert body["converted_job_id"] is not None

    # Verify the created job exists at quote stage
    job_resp = await tenant_a_client.get(
        f"/api/v1/jobs/{body['converted_job_id']}"
    )
    assert job_resp.status_code == 200
    job = job_resp.json()
    assert job["status"] == "quote"
    assert job["description"] == "Install new kitchen exhaust fan"


# ---------------------------------------------------------------------------
# Test 7: Decline request — stores decline_reason
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_decline_request(tenant_a_client, seed_two_tenants):
    """POST review with action='declined' sets request status and decline_reason."""
    request = await submit_in_app_request(
        tenant_a_client,
        description="Build a swimming pool",
    )
    request_id = request["id"]

    resp = await tenant_a_client.post(
        f"/api/v1/jobs/requests/{request_id}/review",
        json={
            "action": "declined",
            "decline_reason": "Outside service area",
            "decline_message": "We don't service your postcode at this time.",
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "declined"
    assert body["decline_reason"] == "Outside service area"
    assert body["decline_message"] == "We don't service your postcode at this time."
    assert body["converted_job_id"] is None


# ---------------------------------------------------------------------------
# Test 8: Info requested — sets status to info_requested
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_request_info(tenant_a_client, seed_two_tenants):
    """POST review with action='info_requested' updates status accordingly."""
    request = await submit_in_app_request(
        tenant_a_client,
        description="Repair cracked driveway",
    )
    request_id = request["id"]

    resp = await tenant_a_client.post(
        f"/api/v1/jobs/requests/{request_id}/review",
        json={"action": "info_requested"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "info_requested"


# ---------------------------------------------------------------------------
# Test 9: Web form renders HTML page
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_web_form_renders(async_client, seed_two_tenants):
    """GET /jobs/request/{company_id} returns 200 with HTML content."""
    company_id = seed_two_tenants["tenant_a_id"]

    resp = await async_client.get(f"/api/v1/jobs/request/{company_id}")
    assert resp.status_code == 200
    assert "text/html" in resp.headers.get("content-type", "")
    # Verify it's a real HTML page (not empty)
    assert len(resp.text) > 100


# ---------------------------------------------------------------------------
# Test 10: Dual flow E2E — request -> accept -> full job lifecycle
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_dual_flow_e2e(tenant_a_client, seed_two_tenants):
    """E2E: client submits request -> admin accepts -> job advances to invoiced.

    Verifies the dual-flow pipeline:
    1. Client submits a job request
    2. Admin accepts — job created at quote stage
    3. Admin advances job through full lifecycle: quote -> invoiced
    4. Final job.status = 'invoiced' with complete status_history
    """
    # Step 1: Submit job request (authenticated admin/client flow)
    request = await submit_in_app_request(
        tenant_a_client,
        description="Replace entire electrical panel",
        trade_type="electrician",
    )
    request_id = request["id"]
    assert request["status"] == "pending"

    # Step 2: Admin accepts — creates job at quote
    accept_resp = await tenant_a_client.post(
        f"/api/v1/jobs/requests/{request_id}/review",
        json={"action": "accepted"},
    )
    assert accept_resp.status_code == 200
    accepted = accept_resp.json()
    assert accepted["status"] == "accepted"
    job_id = accepted["converted_job_id"]
    assert job_id is not None

    # Step 3: Get the job and advance through lifecycle
    job_resp = await tenant_a_client.get(f"/api/v1/jobs/{job_id}")
    assert job_resp.status_code == 200
    job = job_resp.json()
    assert job["status"] == "quote"
    version = job["version"]

    # quote -> scheduled -> in_progress -> complete -> invoiced
    transitions = ["scheduled", "in_progress", "complete", "invoiced"]
    for new_status in transitions:
        resp = await tenant_a_client.patch(
            f"/api/v1/jobs/{job_id}/transition",
            json={"new_status": new_status, "version": version},
        )
        assert resp.status_code == 200, (
            f"Transition to {new_status} failed: {resp.text}"
        )
        job = resp.json()
        version = job["version"]

    # Step 4: Verify final state
    assert job["status"] == "invoiced"
    # status_history: initial + 4 transitions = 5 entries
    assert len(job["status_history"]) == 5, (
        f"Expected 5 history entries, got: {len(job['status_history'])}"
    )
    statuses = [e["status"] for e in job["status_history"]]
    assert statuses == ["quote", "scheduled", "in_progress", "complete", "invoiced"]
