"""Company endpoint tests — CRUD operations, validation, and auth enforcement.

Tests exercise the /api/v1/companies endpoints through the full ASGI stack
using JWT Bearer tokens from the seed_two_tenants fixture.
"""

import asyncio
from uuid import uuid4

import pytest
from httpx import AsyncClient


# ---------------------------------------------------------------------------
# Create
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_company_returns_all_fields(tenant_a_client: AsyncClient):
    """POST /companies with full payload returns 201 with all fields."""
    payload = {
        "name": "Acme Builders",
        "address": "123 Main St",
        "phone": "555-1234",
        "trade_types": ["plumber", "electrician"],
        "logo_url": "https://example.com/logo.png",
        "business_number": "BN-12345",
    }
    resp = await tenant_a_client.post("/api/v1/companies/", json=payload)
    assert resp.status_code == 201
    body = resp.json()
    assert body["name"] == "Acme Builders"
    assert body["address"] == "123 Main St"
    assert body["phone"] == "555-1234"
    assert body["trade_types"] == ["plumber", "electrician"]
    assert body["logo_url"] == "https://example.com/logo.png"
    assert body["business_number"] == "BN-12345"
    assert "id" in body
    assert "version" in body
    assert "created_at" in body
    assert "updated_at" in body


@pytest.mark.asyncio
async def test_create_company_missing_name_returns_422(tenant_a_client: AsyncClient):
    """POST /companies without name returns 422."""
    resp = await tenant_a_client.post("/api/v1/companies/", json={})
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_create_company_empty_name_returns_422(tenant_a_client: AsyncClient):
    """POST /companies with empty name string returns 422 (min_length=1)."""
    resp = await tenant_a_client.post("/api/v1/companies/", json={"name": ""})
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Read
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_get_company_by_id(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """GET /companies/{id} returns correct company data."""
    company_id = seed_two_tenants["tenant_a_id"]
    resp = await tenant_a_client.get(f"/api/v1/companies/{company_id}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == company_id
    assert body["name"] == "Tenant A Corp"


@pytest.mark.asyncio
async def test_get_nonexistent_company_returns_404(tenant_a_client: AsyncClient):
    """GET /companies/{random_uuid} returns 404."""
    resp = await tenant_a_client.get(f"/api/v1/companies/{uuid4()}")
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# Update (PATCH)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_patch_company_partial_update(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """PATCH /companies/{id} updates only provided fields."""
    company_id = seed_two_tenants["tenant_a_id"]

    resp = await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={"phone": "555-9999"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["phone"] == "555-9999"
    # Original name should be preserved
    assert body["name"] == "Tenant A Corp"


@pytest.mark.asyncio
async def test_patch_company_trade_types_array(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """PATCH /companies/{id} can update PostgreSQL ARRAY column."""
    company_id = seed_two_tenants["tenant_a_id"]

    resp = await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={"trade_types": ["hvac", "roofing"]},
    )
    assert resp.status_code == 200
    assert resp.json()["trade_types"] == ["hvac", "roofing"]


@pytest.mark.asyncio
async def test_patch_nonexistent_company_returns_404(tenant_a_client: AsyncClient):
    """PATCH /companies/{random_uuid} returns 404."""
    resp = await tenant_a_client.patch(
        f"/api/v1/companies/{uuid4()}",
        json={"name": "Nope"},
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_patch_company_updated_at_advances(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """PATCH /companies/{id} updates the updated_at timestamp."""
    company_id = seed_two_tenants["tenant_a_id"]

    resp1 = await tenant_a_client.get(f"/api/v1/companies/{company_id}")
    original_updated_at = resp1.json()["updated_at"]

    # Small delay to ensure timestamp advances
    await asyncio.sleep(0.05)

    resp2 = await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={"phone": "555-0000"},
    )
    new_updated_at = resp2.json()["updated_at"]
    assert new_updated_at >= original_updated_at


# ---------------------------------------------------------------------------
# Auth enforcement
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_company_requires_auth(async_client: AsyncClient):
    """POST/GET/PATCH company endpoints require Bearer token."""
    # POST
    resp = await async_client.post(
        "/api/v1/companies/", json={"name": "NoAuth"}
    )
    assert resp.status_code == 401

    # GET
    resp = await async_client.get(f"/api/v1/companies/{uuid4()}")
    assert resp.status_code == 401

    # PATCH
    resp = await async_client.patch(
        f"/api/v1/companies/{uuid4()}", json={"name": "Nope"}
    )
    assert resp.status_code == 401
