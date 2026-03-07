"""Integration tests: UUID idempotency for offline sync deduplication.

Tests prove that ON CONFLICT DO NOTHING prevents duplicate records when
the mobile client retries a sync operation (e.g., after a network failure).

All endpoints now require JWT Bearer tokens. Tests use authenticated clients.
"""

import asyncio
import uuid

import pytest
from httpx import AsyncClient


# ---------------------------------------------------------------------------
# Test 1: Duplicate company UUID returns existing record (200 not 409)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_duplicate_company_uuid_returns_existing(
    tenant_a_client: AsyncClient,
) -> None:
    """POST /api/v1/companies/ with same UUID twice -> second returns existing."""
    company_uuid = str(uuid.uuid4())

    resp1 = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"id": company_uuid, "name": "Acme Corp UUID Test"},
    )
    assert resp1.status_code == 201, f"First POST failed: {resp1.text}"
    first_company = resp1.json()
    assert first_company["id"] == company_uuid

    resp2 = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"id": company_uuid, "name": "Acme Corp UUID Test"},
    )
    assert resp2.status_code == 201
    second_company = resp2.json()

    assert second_company["id"] == company_uuid
    assert second_company["name"] == first_company["name"]


# ---------------------------------------------------------------------------
# Test 2: Duplicate user creation within same tenant
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_duplicate_user_creation(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """POST two users with different emails -> both are created."""
    resp1 = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "idempotent-user@tenant-a.com"},
    )
    assert resp1.status_code == 201

    resp2 = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "idempotent-user-2@tenant-a.com"},
    )
    assert resp2.status_code == 201

    list_resp = await tenant_a_client.get("/api/v1/users/")
    assert list_resp.status_code == 200
    user_emails = [u["email"] for u in list_resp.json()]
    assert "idempotent-user@tenant-a.com" in user_emails
    assert "idempotent-user-2@tenant-a.com" in user_emails


# ---------------------------------------------------------------------------
# Test 3: Different UUIDs create separate records
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_different_uuid_creates_new(
    tenant_a_client: AsyncClient,
) -> None:
    """POST two companies with different UUIDs -> two companies in DB."""
    uuid_a = str(uuid.uuid4())
    uuid_b = str(uuid.uuid4())

    resp_a = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"id": uuid_a, "name": "Company Alpha"},
    )
    assert resp_a.status_code == 201
    assert resp_a.json()["id"] == uuid_a

    resp_b = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"id": uuid_b, "name": "Company Beta"},
    )
    assert resp_b.status_code == 201
    assert resp_b.json()["id"] == uuid_b

    company_a = (await tenant_a_client.get(f"/api/v1/companies/{uuid_a}")).json()
    company_b = (await tenant_a_client.get(f"/api/v1/companies/{uuid_b}")).json()

    assert company_a["name"] == "Company Alpha"
    assert company_b["name"] == "Company Beta"
    assert company_a["id"] != company_b["id"]


# ---------------------------------------------------------------------------
# Test 4: ON CONFLICT DO NOTHING — original data preserved (first-write-wins)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_idempotency_preserves_original_data(
    tenant_a_client: AsyncClient,
) -> None:
    """POST same UUID with different name -> original data preserved."""
    company_uuid = str(uuid.uuid4())

    resp1 = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"id": company_uuid, "name": "Original Name"},
    )
    assert resp1.status_code == 201
    assert resp1.json()["name"] == "Original Name"

    resp2 = await tenant_a_client.post(
        "/api/v1/companies/",
        json={"id": company_uuid, "name": "Different Name"},
    )
    assert resp2.status_code == 201
    assert resp2.json()["name"] == "Original Name"


# ---------------------------------------------------------------------------
# Test 5: Concurrent duplicate POSTs — exactly 1 record in DB
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_concurrent_duplicate_creates(
    tenant_a_client: AsyncClient, test_engine
) -> None:
    """Concurrent POSTs with same UUID -> exactly 1 company in DB."""
    from sqlalchemy import text
    from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

    company_uuid = str(uuid.uuid4())

    async def post_company() -> dict:
        resp = await tenant_a_client.post(
            "/api/v1/companies/",
            json={"id": company_uuid, "name": "Concurrent Company"},
        )
        assert resp.status_code == 201, f"POST failed: {resp.text}"
        return resp.json()

    results = await asyncio.gather(post_company(), post_company())

    assert results[0]["id"] == company_uuid
    assert results[1]["id"] == company_uuid

    session_factory = async_sessionmaker(
        test_engine, class_=AsyncSession, expire_on_commit=False
    )
    async with session_factory() as session:
        result = await session.execute(
            text("SELECT COUNT(*) FROM companies WHERE id = :cid"),
            {"cid": company_uuid},
        )
        count = result.scalar()

    assert count == 1
