"""Integration tests: Delta sync endpoint for offline-first clients.

Tests prove the correctness of GET /api/v1/sync?cursor=<ISO8601>.
All endpoints require JWT Bearer tokens. Tests use authenticated fixtures.
"""

import asyncio
from datetime import datetime

import pytest
from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker


# ---------------------------------------------------------------------------
# Test 1: Full first sync — no cursor returns ALL entities
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_returns_all_on_first_sync(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """No cursor param -> returns ALL companies and users for the tenant."""
    resp = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"name": "Acme Corp"},
    )
    assert resp.status_code == 201

    resp = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "alice@acme.com"},
    )
    assert resp.status_code == 201

    resp = await tenant_a_client.get("/api/v1/sync")
    assert resp.status_code == 200

    data = resp.json()
    assert "companies" in data
    assert "users" in data
    assert "user_roles" in data
    assert "server_timestamp" in data

    company_names = [c["name"] for c in data["companies"]]
    assert "Acme Corp" in company_names

    user_emails = [u["email"] for u in data["users"]]
    assert "alice@acme.com" in user_emails


# ---------------------------------------------------------------------------
# Test 2: Cursor-based delta — only changed entities returned
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_returns_only_changed(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Create at T1. Wait. Create at T2. Sync cursor=T1 -> only T2 returned."""
    resp = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"name": "Old Company"},
    )
    assert resp.status_code == 201
    company_a_id = resp.json()["id"]

    resp = await tenant_a_client.get("/api/v1/sync")
    assert resp.status_code == 200
    cursor_t1 = resp.json()["server_timestamp"]

    await asyncio.sleep(0.01)

    resp = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"name": "New Company"},
    )
    assert resp.status_code == 201
    company_b_id = resp.json()["id"]

    resp = await tenant_a_client.get(f"/api/v1/sync?cursor={cursor_t1}")
    assert resp.status_code == 200

    company_ids = [c["id"] for c in resp.json()["companies"]]
    assert company_b_id in company_ids
    assert company_a_id not in company_ids


# ---------------------------------------------------------------------------
# Test 3: Tombstones — soft-deleted records appear with deleted_at set
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_includes_tombstones(
    tenant_a_client: AsyncClient, test_engine, seed_two_tenants: dict
) -> None:
    """Create a company. Soft-delete it. Sync -> deleted company in response."""
    resp = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"name": "To Be Deleted Corp"},
    )
    assert resp.status_code == 201
    company_id = resp.json()["id"]

    resp = await tenant_a_client.get("/api/v1/sync")
    assert resp.status_code == 200
    cursor_before_delete = resp.json()["server_timestamp"]

    await asyncio.sleep(0.01)

    # Soft-delete via direct DB update (no delete endpoint exists yet)
    session_factory = async_sessionmaker(
        test_engine, class_=AsyncSession, expire_on_commit=False
    )
    async with session_factory() as session:
        await session.execute(
            text("UPDATE companies SET deleted_at = NOW() WHERE id = :company_id"),
            {"company_id": company_id},
        )
        await session.commit()

    # Delta sync since before deletion — tombstone must appear
    resp = await tenant_a_client.get(
        f"/api/v1/sync?cursor={cursor_before_delete}"
    )
    assert resp.status_code == 200

    data = resp.json()
    deleted_companies = [c for c in data["companies"] if c["id"] == company_id]
    assert len(deleted_companies) == 1
    assert deleted_companies[0]["deleted_at"] is not None


# ---------------------------------------------------------------------------
# Test 4: Tenant isolation — RLS enforced on sync endpoint
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_respects_tenant_isolation(
    tenant_a_client: AsyncClient,
    tenant_b_client: AsyncClient,
    seed_two_tenants: dict,
) -> None:
    """Create users in both tenants. Sync as Tenant A -> only A's users."""
    resp = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "a-user@tenant-a.com"},
    )
    assert resp.status_code == 201
    user_a_id = resp.json()["id"]

    resp = await tenant_b_client.post(
        "/api/v1/users/",
        json={"email": "b-user@tenant-b.com"},
    )
    assert resp.status_code == 201
    user_b_id = resp.json()["id"]

    resp = await tenant_a_client.get("/api/v1/sync")
    assert resp.status_code == 200

    user_ids = [u["id"] for u in resp.json()["users"]]
    assert user_a_id in user_ids
    assert user_b_id not in user_ids


# ---------------------------------------------------------------------------
# Test 5: server_timestamp present in ISO8601 format
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_returns_server_timestamp(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Sync response contains server_timestamp in ISO8601 format."""
    resp = await tenant_a_client.get("/api/v1/sync")
    assert resp.status_code == 200

    data = resp.json()
    assert "server_timestamp" in data

    ts = data["server_timestamp"]
    parsed = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    assert parsed.tzinfo is not None


# ---------------------------------------------------------------------------
# Test 6: updated_at advances on update (PostgreSQL trigger verification)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_updated_at_advances_on_update(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Update a company -> updated_at advances -> appears in delta."""
    resp = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"name": "Original Name"},
    )
    assert resp.status_code == 201
    company = resp.json()
    company_id = company["id"]
    original_updated_at = company["updated_at"]

    await asyncio.sleep(0.01)

    resp = await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={"name": "Updated Name"},
    )
    assert resp.status_code == 200
    new_updated_at = resp.json()["updated_at"]

    assert new_updated_at != original_updated_at

    resp = await tenant_a_client.get(
        f"/api/v1/sync?cursor={original_updated_at}"
    )
    assert resp.status_code == 200
    company_ids = [c["id"] for c in resp.json()["companies"]]
    assert company_id in company_ids


# ---------------------------------------------------------------------------
# Test 7: user_roles included in delta response
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delta_sync_user_roles_included(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Create user with role. Sync -> user_roles in response."""
    resp = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "roleuser@tenant-a.com"},
    )
    assert resp.status_code == 201
    user_id = resp.json()["id"]

    resp = await tenant_a_client.post(
        f"/api/v1/users/{user_id}/roles",
        json={"user_id": user_id, "role": "admin"},
    )
    assert resp.status_code == 201
    role_id = resp.json()["id"]

    resp = await tenant_a_client.get("/api/v1/sync")
    assert resp.status_code == 200

    data = resp.json()
    role_ids = [r["id"] for r in data["user_roles"]]
    assert role_id in role_ids
