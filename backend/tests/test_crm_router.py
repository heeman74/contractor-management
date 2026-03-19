"""CRM router endpoint tests — Phase 17.

Unit-level router behavior tests against real test database.
Uses tenant_a_client fixture (admin JWT Bearer token pre-set).
"""

from __future__ import annotations

import uuid

import pytest
from httpx import AsyncClient

# Side-effect: register all mappers before tests run.
import app.features.scheduling.models  # noqa: F401

pytestmark = pytest.mark.anyio


async def test_list_clients(tenant_a_client: AsyncClient):
    """GET /api/v1/crm/clients returns 200 with paginated client list."""
    response = await tenant_a_client.get("/api/v1/crm/clients")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)


async def test_list_clients_search(tenant_a_client: AsyncClient):
    """GET /api/v1/crm/clients?search=name filters results."""
    response = await tenant_a_client.get("/api/v1/crm/clients?search=test_nonexistent")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    # Nonsense search returns empty list
    assert len(data) == 0


async def test_list_clients_pagination_params(tenant_a_client: AsyncClient):
    """GET /api/v1/crm/clients with pagination params returns correct structure."""
    response = await tenant_a_client.get("/api/v1/crm/clients?offset=0&limit=5")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) <= 5


async def test_client_detail_not_found(tenant_a_client: AsyncClient):
    """GET /api/v1/crm/clients/{unknown_id} returns 404."""
    fake_id = str(uuid.uuid4())
    response = await tenant_a_client.get(f"/api/v1/crm/clients/{fake_id}")
    assert response.status_code == 404


async def test_client_detail_invalid_uuid(tenant_a_client: AsyncClient):
    """GET /api/v1/crm/clients/{invalid} returns 422 for non-UUID path param."""
    response = await tenant_a_client.get("/api/v1/crm/clients/not-a-uuid")
    assert response.status_code == 422


async def test_client_list_response_schema(tenant_a_client: AsyncClient):
    """Client list items have expected schema fields when clients exist."""
    response = await tenant_a_client.get("/api/v1/crm/clients?limit=1")
    assert response.status_code == 200
    data = response.json()
    if len(data) > 0:
        item = data[0]
        # Verify required fields from ClientListResponse
        assert "user_id" in item
        assert "email" in item
        assert "jobs_count" in item
