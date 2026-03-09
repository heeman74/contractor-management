"""Integration tests for CRM operations via HTTP.

Tests the full stack: HTTP request -> FastAPI router -> CrmService / RatingService
-> CrmRepository -> PostgreSQL RLS.

Coverage:
- Client profile CRUD: create, update, list with search, job history
- Saved properties: add, remove, set default
- Ratings: create (valid and invalid cases), uniqueness per direction, average update

All tests use JWT Bearer token authentication per CLAUDE.md testing rules.
clean_tables autouse fixture provides test isolation.
"""

import uuid

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------


async def create_user(client: AsyncClient, email: str) -> dict:
    """Create a new user via the users endpoint and return JSON."""
    resp = await client.post("/api/v1/users/", json={"email": email})
    assert resp.status_code == 201, f"Failed to create user {email}: {resp.text}"
    return resp.json()


async def create_client_profile(
    client: AsyncClient, user_id: str, **overrides
) -> dict:
    """Create or update a client profile and return JSON."""
    payload = {
        "user_id": user_id,
        "billing_address": "123 Test Street, Melbourne VIC 3000",
        "tags": ["residential"],
        "admin_notes": "Preferred morning appointments",
    }
    payload.update(overrides)
    resp = await client.post(f"/api/v1/clients/{user_id}/profile", json=payload)
    assert resp.status_code == 201, f"Failed to create client profile: {resp.text}"
    return resp.json()


async def create_job_site_direct(test_engine, company_id: uuid.UUID) -> uuid.UUID:
    """Create a job site directly via raw SQL for use in property tests.

    No job_sites HTTP endpoint exists — mirrors the scheduling conftest pattern.
    """
    job_site_id = uuid.uuid4()
    async with test_engine.connect() as conn:
        await conn.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await conn.execute(
            text("""
                INSERT INTO job_sites (id, company_id, address, latitude, longitude,
                                       version, created_at, updated_at)
                VALUES (:id, :company_id, :address, :lat, :lng, 1, now(), now())
            """),
            {
                "id": str(job_site_id),
                "company_id": str(company_id),
                "address": "456 Property Avenue, Melbourne VIC 3000",
                "lat": -37.813,
                "lng": 144.963,
            },
        )
        await conn.commit()
    return job_site_id


async def create_job(client: AsyncClient, **overrides) -> dict:
    """Create a minimal test job."""
    payload = {
        "description": "Test job for CRM operations",
        "trade_type": "plumber",
        "priority": "medium",
    }
    payload.update(overrides)
    resp = await client.post("/api/v1/jobs/", json=payload)
    assert resp.status_code == 201, f"Failed to create job: {resp.text}"
    return resp.json()


async def advance_job_to_complete(client: AsyncClient, job: dict) -> dict:
    """Advance a job to 'complete' status through all required transitions."""
    job_id = job["id"]
    version = job["version"]

    transitions = ["scheduled", "in_progress", "complete"]
    for new_status in transitions:
        resp = await client.patch(
            f"/api/v1/jobs/{job_id}/transition",
            json={"new_status": new_status, "version": version},
        )
        assert resp.status_code == 200, (
            f"Transition to {new_status} failed: {resp.text}"
        )
        version = resp.json()["version"]

    return resp.json()


# ---------------------------------------------------------------------------
# Test 1: Create client profile
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_client_profile(tenant_a_client, seed_two_tenants):
    """POST /api/v1/clients/{user_id}/profile creates a client profile."""
    user = await create_user(tenant_a_client, "client.profile@example.com")
    user_id = user["id"]

    resp = await tenant_a_client.post(
        f"/api/v1/clients/{user_id}/profile",
        json={
            "user_id": user_id,
            "billing_address": "789 Billing Lane, Sydney NSW 2000",
            "tags": ["commercial", "priority"],
            "admin_notes": "Long-standing client — discount applies",
            "preferred_contact_method": "email",
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["user_id"] == user_id
    assert body["billing_address"] == "789 Billing Lane, Sydney NSW 2000"
    assert "commercial" in body["tags"]
    assert body["admin_notes"] == "Long-standing client — discount applies"
    assert body["preferred_contact_method"] == "email"
    assert "id" in body
    assert "company_id" in body


# ---------------------------------------------------------------------------
# Test 2: Update client profile
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_update_client_profile(tenant_a_client, seed_two_tenants):
    """POST again to update existing profile (upsert semantics)."""
    user = await create_user(tenant_a_client, "update.profile@example.com")
    user_id = user["id"]

    # Create initial profile
    await create_client_profile(tenant_a_client, user_id)

    # Update fields
    resp = await tenant_a_client.post(
        f"/api/v1/clients/{user_id}/profile",
        json={
            "user_id": user_id,
            "billing_address": "999 Updated Rd, Brisbane QLD 4000",
            "tags": ["vip", "residential"],
            "admin_notes": "Updated notes after review",
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["billing_address"] == "999 Updated Rd, Brisbane QLD 4000"
    assert "vip" in body["tags"]
    assert body["admin_notes"] == "Updated notes after review"


# ---------------------------------------------------------------------------
# Test 3: List clients with name search filter
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_list_clients_with_search(tenant_a_client, seed_two_tenants):
    """GET /api/v1/clients/?search=name returns filtered results."""
    # Create 3 users and profiles with different names
    user1 = await create_user(tenant_a_client, "alice.wonder@example.com")
    user2 = await create_user(tenant_a_client, "bob.builder@example.com")
    user3 = await create_user(tenant_a_client, "charlie.chaplin@example.com")

    for user in [user1, user2, user3]:
        await create_client_profile(tenant_a_client, user["id"])

    # Search by email substring — should only return alice
    resp = await tenant_a_client.get("/api/v1/clients/?search=alice")
    assert resp.status_code == 200
    body = resp.json()
    user_ids = [p["user_id"] for p in body]
    assert user1["id"] in user_ids
    assert user2["id"] not in user_ids
    assert user3["id"] not in user_ids


# ---------------------------------------------------------------------------
# Test 4: Client job history — GET client with associated jobs
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_client_job_history(tenant_a_client, seed_two_tenants):
    """GET /api/v1/clients/{user_id} returns profile (profile + jobs via service)."""
    user = await create_user(tenant_a_client, "client.history@example.com")
    user_id = user["id"]
    await create_client_profile(tenant_a_client, user_id)

    # Create 3 jobs for this client
    for i in range(3):
        await create_job(
            tenant_a_client,
            description=f"Job {i + 1} for history client",
            client_id=user_id,
        )

    # GET /clients/{user_id} returns profile — job history via service not exposed in response
    # The endpoint returns ClientProfileResponse; jobs are verified via list_jobs filter
    resp = await tenant_a_client.get(f"/api/v1/clients/{user_id}")
    assert resp.status_code == 200
    profile = resp.json()
    assert profile["user_id"] == user_id

    # Verify jobs are associated via list_jobs filter
    jobs_resp = await tenant_a_client.get(f"/api/v1/jobs/?client_id={user_id}")
    assert jobs_resp.status_code == 200
    jobs = jobs_resp.json()
    assert len(jobs) == 3


# ---------------------------------------------------------------------------
# Test 5: Add saved property
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_add_saved_property(tenant_a_client, test_engine, seed_two_tenants):
    """POST /api/v1/clients/{user_id}/properties adds a property association."""
    company_id = uuid.UUID(seed_two_tenants["tenant_a_id"])
    user = await create_user(tenant_a_client, "property.owner@example.com")
    user_id = user["id"]
    await create_client_profile(tenant_a_client, user_id)

    # Create a job site directly (no HTTP endpoint exists)
    job_site_id = await create_job_site_direct(test_engine, company_id)

    resp = await tenant_a_client.post(
        f"/api/v1/clients/{user_id}/properties",
        json={
            "client_id": user_id,
            "job_site_id": str(job_site_id),
            "nickname": "Home",
            "is_default": True,
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["client_id"] == user_id
    assert body["job_site_id"] == str(job_site_id)
    assert body["nickname"] == "Home"
    assert body["is_default"] is True


# ---------------------------------------------------------------------------
# Test 6: Remove saved property
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_remove_saved_property(tenant_a_client, test_engine, seed_two_tenants):
    """DELETE /api/v1/clients/properties/{id} returns 204 and removes property."""
    company_id = uuid.UUID(seed_two_tenants["tenant_a_id"])
    user = await create_user(tenant_a_client, "remove.property@example.com")
    user_id = user["id"]
    await create_client_profile(tenant_a_client, user_id)

    job_site_id = await create_job_site_direct(test_engine, company_id)

    # Add property
    add_resp = await tenant_a_client.post(
        f"/api/v1/clients/{user_id}/properties",
        json={
            "client_id": user_id,
            "job_site_id": str(job_site_id),
            "nickname": "Office",
            "is_default": False,
        },
    )
    assert add_resp.status_code == 201
    property_id = add_resp.json()["id"]

    # Remove property
    del_resp = await tenant_a_client.delete(
        f"/api/v1/clients/properties/{property_id}"
    )
    assert del_resp.status_code == 204

    # Verify it no longer appears in list
    list_resp = await tenant_a_client.get(
        f"/api/v1/clients/{user_id}/properties"
    )
    assert list_resp.status_code == 200
    remaining_ids = [p["id"] for p in list_resp.json()]
    assert property_id not in remaining_ids


# ---------------------------------------------------------------------------
# Test 7: Set default property — unsets previous default
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_set_default_property(tenant_a_client, test_engine, seed_two_tenants):
    """Adding property with is_default=True unsets existing default."""
    company_id = uuid.UUID(seed_two_tenants["tenant_a_id"])
    user = await create_user(tenant_a_client, "set.default@example.com")
    user_id = user["id"]
    await create_client_profile(tenant_a_client, user_id)

    site1_id = await create_job_site_direct(test_engine, company_id)
    site2_id = await create_job_site_direct(test_engine, company_id)

    # Add first as default
    add1_resp = await tenant_a_client.post(
        f"/api/v1/clients/{user_id}/properties",
        json={
            "client_id": user_id,
            "job_site_id": str(site1_id),
            "nickname": "Home",
            "is_default": True,
        },
    )
    assert add1_resp.status_code == 201
    prop1_id = add1_resp.json()["id"]

    # Add second as new default — should unset first
    add2_resp = await tenant_a_client.post(
        f"/api/v1/clients/{user_id}/properties",
        json={
            "client_id": user_id,
            "job_site_id": str(site2_id),
            "nickname": "Work",
            "is_default": True,
        },
    )
    assert add2_resp.status_code == 201

    # List properties and verify only the second is default
    list_resp = await tenant_a_client.get(
        f"/api/v1/clients/{user_id}/properties"
    )
    assert list_resp.status_code == 200
    properties = {p["id"]: p for p in list_resp.json()}

    assert properties[prop1_id]["is_default"] is False
    assert properties[add2_resp.json()["id"]]["is_default"] is True


# ---------------------------------------------------------------------------
# Test 8: Create rating for completed job
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_rating(tenant_a_client, seed_two_tenants):
    """POST /api/v1/jobs/{job_id}/ratings creates a rating for a complete job."""
    user = await create_user(tenant_a_client, "rating.client@example.com")
    user_id = user["id"]
    await create_client_profile(tenant_a_client, user_id)

    # Create job assigned to this client
    job = await create_job(tenant_a_client, client_id=user_id)

    # Advance to complete
    job = await advance_job_to_complete(tenant_a_client, job)
    assert job["status"] == "complete"

    # Create admin_to_client rating
    resp = await tenant_a_client.post(
        f"/api/v1/jobs/{job['id']}/ratings",
        json={
            "stars": 4,
            "review_text": "Excellent client — always on time and responsive",
            "direction": "admin_to_client",
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["stars"] == 4
    assert body["direction"] == "admin_to_client"
    assert body["ratee_id"] == user_id
    assert body["review_text"] == "Excellent client — always on time and responsive"


# ---------------------------------------------------------------------------
# Test 9: Rating rejected before job is complete
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_rating_rejected_before_complete(tenant_a_client, seed_two_tenants):
    """POST rating on a quote-status job returns 422 (not complete or invoiced)."""
    user = await create_user(tenant_a_client, "rating.too.early@example.com")
    user_id = user["id"]
    await create_client_profile(tenant_a_client, user_id)

    # Create job but don't advance it beyond 'quote'
    job = await create_job(tenant_a_client, client_id=user_id)
    assert job["status"] == "quote"

    resp = await tenant_a_client.post(
        f"/api/v1/jobs/{job['id']}/ratings",
        json={
            "stars": 5,
            "review_text": "Premature rating",
            "direction": "admin_to_client",
        },
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Test 10: Rating unique per direction — duplicate returns 409
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_rating_unique_per_direction(tenant_a_client, seed_two_tenants):
    """Submitting a second rating in the same direction returns 409 Conflict."""
    user = await create_user(tenant_a_client, "unique.rating@example.com")
    user_id = user["id"]
    await create_client_profile(tenant_a_client, user_id)

    job = await create_job(tenant_a_client, client_id=user_id)
    job = await advance_job_to_complete(tenant_a_client, job)

    # First rating — should succeed
    resp1 = await tenant_a_client.post(
        f"/api/v1/jobs/{job['id']}/ratings",
        json={
            "stars": 3,
            "review_text": "First rating",
            "direction": "admin_to_client",
        },
    )
    assert resp1.status_code == 201

    # Second rating in same direction — should return 409
    resp2 = await tenant_a_client.post(
        f"/api/v1/jobs/{job['id']}/ratings",
        json={
            "stars": 5,
            "review_text": "Duplicate rating attempt",
            "direction": "admin_to_client",
        },
    )
    assert resp2.status_code == 409


# ---------------------------------------------------------------------------
# Test 11: Average rating updated after multiple ratings
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_average_rating_updated(tenant_a_client, seed_two_tenants):
    """Creating 2 admin_to_client ratings updates the client profile average_rating."""
    user = await create_user(tenant_a_client, "average.rating@example.com")
    user_id = user["id"]
    await create_client_profile(tenant_a_client, user_id)

    # Create and complete 2 separate jobs for this client
    job1 = await create_job(tenant_a_client, client_id=user_id, description="Job 1 for rating")
    job1 = await advance_job_to_complete(tenant_a_client, job1)

    job2 = await create_job(tenant_a_client, client_id=user_id, description="Job 2 for rating")
    job2 = await advance_job_to_complete(tenant_a_client, job2)

    # Rate job 1: 4 stars
    await tenant_a_client.post(
        f"/api/v1/jobs/{job1['id']}/ratings",
        json={"stars": 4, "direction": "admin_to_client"},
    )

    # Rate job 2: 2 stars — average should be (4 + 2) / 2 = 3.00
    await tenant_a_client.post(
        f"/api/v1/jobs/{job2['id']}/ratings",
        json={"stars": 2, "direction": "admin_to_client"},
    )

    # Check average_rating on client profile
    profile_resp = await tenant_a_client.get(f"/api/v1/clients/{user_id}")
    assert profile_resp.status_code == 200
    profile = profile_resp.json()

    # average_rating should be 3.00 ((4 + 2) / 2)
    average = float(profile["average_rating"])
    assert abs(average - 3.0) < 0.01, (
        f"Expected average_rating ~3.00, got {average}"
    )
