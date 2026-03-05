"""Integration tests: Delta sync endpoint for offline-first clients.

Tests prove the correctness of GET /api/v1/sync?cursor=<ISO8601>:

1. No cursor -> returns ALL entities for the tenant (first launch download)
2. Cursor at T1 -> returns only entities changed after T1 (delta pull)
3. Soft-deleted entities appear in response with deleted_at set (tombstones)
4. Tenant isolation: only the requesting tenant's RLS-scoped data returned
5. server_timestamp field present in ISO8601 format for use as next cursor
6. updated_at advances after update (PostgreSQL trigger works correctly)
7. user_roles appear in delta response

These tests use real PostgreSQL with RLS policies applied via Alembic.
conftest.py fixtures handle migration, table truncation, and tenant clients.

IMPORTANT: Requires PostgreSQL running with migration 0002 applied.
conftest.py runs alembic upgrade head in session setup.
"""

import asyncio
from datetime import datetime, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine


# ---------------------------------------------------------------------------
# Test 1: Full first sync — no cursor returns ALL entities
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_returns_all_on_first_sync(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """No cursor param -> returns ALL companies and users for the tenant.

    On first launch, the mobile client omits the cursor parameter. The server
    defaults to epoch 2000-01-01, effectively returning all records.

    PROOF: Full first-sync download works correctly.
    """
    # Create a company (tenant root — no X-Company-Id needed for companies)
    resp = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"name": "Acme Corp"},
    )
    assert resp.status_code == 201, f"Failed to create company: {resp.text}"

    # Create a user in tenant A
    resp = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "alice@acme.com"},
    )
    assert resp.status_code == 201, f"Failed to create user: {resp.text}"

    # Sync without cursor — should return all entities
    resp = await tenant_a_client.get("/api/v1/sync")
    assert resp.status_code == 200, f"Sync failed: {resp.text}"

    data = resp.json()
    assert "companies" in data
    assert "users" in data
    assert "user_roles" in data
    assert "server_timestamp" in data

    # At least 2 companies: the two tenant roots created by seed_two_tenants
    company_names = [c["name"] for c in data["companies"]]
    assert "Acme Corp" in company_names, (
        "Company created by Tenant A must appear in full sync response"
    )

    user_emails = [u["email"] for u in data["users"]]
    assert "alice@acme.com" in user_emails, (
        "User created by Tenant A must appear in full sync response"
    )


# ---------------------------------------------------------------------------
# Test 2: Cursor-based delta — only changed entities returned
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_returns_only_changed(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Create a company at T1. Wait. Create another at T2.
    Sync with cursor=T1 -> only T2 company returned.

    PROOF: Delta sync correctly filters by cursor timestamp.
    """
    # Create company at T1
    resp = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"name": "Old Company"},
    )
    assert resp.status_code == 201
    company_a_id = resp.json()["id"]

    # Get a cursor timestamp AFTER creating the first company
    # Use server_timestamp from a sync call as the cursor
    resp = await tenant_a_client.get("/api/v1/sync")
    assert resp.status_code == 200
    cursor_t1 = resp.json()["server_timestamp"]

    # Small delay to ensure the next company's created_at is after cursor_t1
    await asyncio.sleep(0.01)

    # Create second company at T2 (after cursor_t1)
    resp = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"name": "New Company"},
    )
    assert resp.status_code == 201
    company_b_id = resp.json()["id"]

    # Delta sync with cursor=T1 — must return only the new company
    resp = await tenant_a_client.get(f"/api/v1/sync?cursor={cursor_t1}")
    assert resp.status_code == 200

    data = resp.json()
    company_ids = [c["id"] for c in data["companies"]]

    assert company_b_id in company_ids, (
        "Company created after cursor must appear in delta response"
    )
    assert company_a_id not in company_ids, (
        "Company created before cursor must NOT appear in delta response"
    )


# ---------------------------------------------------------------------------
# Test 3: Tombstones — soft-deleted records appear with deleted_at set
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_includes_tombstones(
    async_client: AsyncClient, test_engine, seed_two_tenants: dict
) -> None:
    """Create a company. Soft-delete it. Sync -> deleted company in response.

    PROOF: Tombstones (deleted_at set) are propagated to offline clients via
    the delta sync endpoint, enabling local deletion of cached records.
    """
    from httpx import ASGITransport, AsyncClient as HttpxClient
    from app.main import app

    tenant_a_id = seed_two_tenants["tenant_a_id"]

    async with HttpxClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"X-Company-Id": tenant_a_id},
    ) as ta_client:
        # Create a company
        resp = await ta_client.post(
            "/api/v1/companies/",
            json={"name": "To Be Deleted Corp"},
        )
        assert resp.status_code == 201
        company_id = resp.json()["id"]

        # Capture cursor before soft-delete
        resp = await ta_client.get("/api/v1/sync")
        assert resp.status_code == 200
        cursor_before_delete = resp.json()["server_timestamp"]

    # Small delay to ensure deleted_at > cursor_before_delete
    await asyncio.sleep(0.01)

    # Soft-delete via direct DB update (no delete endpoint exists yet)
    session_factory = async_sessionmaker(
        test_engine, class_=AsyncSession, expire_on_commit=False
    )
    async with session_factory() as session:
        await session.execute(
            text(
                "UPDATE companies SET deleted_at = NOW() WHERE id = :company_id"
            ),
            {"company_id": company_id},
        )
        await session.commit()

    # Delta sync since before deletion — tombstone must appear
    async with HttpxClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"X-Company-Id": tenant_a_id},
    ) as ta_client:
        resp = await ta_client.get(
            f"/api/v1/sync?cursor={cursor_before_delete}"
        )
        assert resp.status_code == 200

    data = resp.json()
    deleted_companies = [c for c in data["companies"] if c["id"] == company_id]
    assert len(deleted_companies) == 1, (
        f"Soft-deleted company must appear in delta response as a tombstone. "
        f"Companies returned: {[c['id'] for c in data['companies']]}"
    )
    assert deleted_companies[0]["deleted_at"] is not None, (
        "Tombstone must have deleted_at set — mobile client uses this to "
        "delete the locally cached record"
    )


# ---------------------------------------------------------------------------
# Test 4: Tenant isolation — RLS enforced on sync endpoint
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_respects_tenant_isolation(
    tenant_a_client: AsyncClient,
    tenant_b_client: AsyncClient,
    seed_two_tenants: dict,
) -> None:
    """Create users in Tenant A and Tenant B. Sync as Tenant A -> only A's users.

    PROOF: RLS policies enforced at the DB level restrict sync results to the
    requesting tenant. Cross-tenant data leakage is impossible.
    """
    # Tenant A creates a user
    resp = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "a-user@tenant-a.com"},
    )
    assert resp.status_code == 201
    user_a_id = resp.json()["id"]

    # Tenant B creates a user
    resp = await tenant_b_client.post(
        "/api/v1/users/",
        json={"email": "b-user@tenant-b.com"},
    )
    assert resp.status_code == 201
    user_b_id = resp.json()["id"]

    # Tenant A syncs — must see only Tenant A's user
    resp = await tenant_a_client.get("/api/v1/sync")
    assert resp.status_code == 200

    user_ids = [u["id"] for u in resp.json()["users"]]
    assert user_a_id in user_ids, "Tenant A must see its own user in sync response"
    assert user_b_id not in user_ids, (
        "ISOLATION FAILURE: Tenant A can see Tenant B's user in sync response. "
        "RLS is not enforced on the sync endpoint."
    )


# ---------------------------------------------------------------------------
# Test 5: server_timestamp present in ISO8601 format
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_returns_server_timestamp(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Sync response contains server_timestamp in ISO8601 format.

    PROOF: Mobile clients can store server_timestamp as the cursor for the
    next sync. Without this field, incremental sync is impossible.
    """
    resp = await tenant_a_client.get("/api/v1/sync")
    assert resp.status_code == 200

    data = resp.json()
    assert "server_timestamp" in data, "server_timestamp field must be present"

    ts = data["server_timestamp"]
    assert isinstance(ts, str), "server_timestamp must be a string"

    # Must be parseable as ISO8601
    try:
        parsed = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        assert parsed.tzinfo is not None, "server_timestamp must be timezone-aware"
    except ValueError as e:
        pytest.fail(
            f"server_timestamp '{ts}' is not valid ISO8601: {e}"
        )


# ---------------------------------------------------------------------------
# Test 6: updated_at advances on update (PostgreSQL trigger verification)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_updated_at_advances_on_update(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Create company, note updated_at. Update it. Verify updated_at advanced.

    PROOF: The set_updated_at() PostgreSQL trigger fires on UPDATE, ensuring
    the delta sync cursor correctly captures updated records.
    """
    # Create company
    resp = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"name": "Original Name"},
    )
    assert resp.status_code == 201
    company = resp.json()
    company_id = company["id"]
    original_updated_at = company["updated_at"]

    # Small delay to ensure updated_at will differ
    await asyncio.sleep(0.01)

    # Update the company
    resp = await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={"name": "Updated Name"},
    )
    assert resp.status_code == 200
    updated_company = resp.json()
    new_updated_at = updated_company["updated_at"]

    # updated_at must have advanced
    assert new_updated_at != original_updated_at, (
        "updated_at must change on UPDATE — PostgreSQL trigger set_updated_at() "
        "is required for delta sync cursor to capture updated records"
    )
    assert datetime.fromisoformat(
        new_updated_at.replace("Z", "+00:00")
    ) > datetime.fromisoformat(original_updated_at.replace("Z", "+00:00")), (
        "new updated_at must be strictly after original updated_at"
    )

    # Sync with cursor = original_updated_at — must include the updated company
    resp = await tenant_a_client.get(
        f"/api/v1/sync?cursor={original_updated_at}"
    )
    assert resp.status_code == 200

    company_ids = [c["id"] for c in resp.json()["companies"]]
    assert company_id in company_ids, (
        "Updated company must appear in delta response when cursor is before update"
    )


# ---------------------------------------------------------------------------
# Test 7: user_roles included in delta response
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_user_roles_included(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Create user with role. Sync -> user_roles array populated in response.

    PROOF: User roles are included in the delta sync response, enabling
    the mobile client to sync permission data along with user profiles.
    """
    # Create a user
    resp = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "roleuser@tenant-a.com"},
    )
    assert resp.status_code == 201
    user_id = resp.json()["id"]

    # Assign an admin role
    resp = await tenant_a_client.post(
        f"/api/v1/users/{user_id}/roles",
        json={"user_id": user_id, "role": "admin"},
    )
    assert resp.status_code == 201
    role_id = resp.json()["id"]

    # Delta sync — user_roles must appear
    resp = await tenant_a_client.get("/api/v1/sync")
    assert resp.status_code == 200

    data = resp.json()
    assert "user_roles" in data, "sync response must contain user_roles array"

    role_ids = [r["id"] for r in data["user_roles"]]
    assert role_id in role_ids, (
        "Assigned user role must appear in delta sync response"
    )

    # Verify role data is correct
    matching_roles = [r for r in data["user_roles"] if r["id"] == role_id]
    assert matching_roles[0]["role"] == "admin"
    assert matching_roles[0]["user_id"] == user_id
