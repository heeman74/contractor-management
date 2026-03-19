"""Phase 17 CRM E2E integration tests — tests CRM router against real database.

Strategy:
- Uses tenant_a_client fixture (admin JWT Bearer token pre-set, see conftest.py).
- Creates real DB state via API calls (no direct DB injection).
- All tests are @pytest.mark.anyio async tests — NO @pytest.mark.skip stubs.
"""

from __future__ import annotations

import uuid

import pytest
from httpx import AsyncClient

# Side-effect: register all mappers before tests run.
import app.features.scheduling.models  # noqa: F401

pytestmark = pytest.mark.anyio


class TestCRMClientList:
    """CRM-01: Admin can view a searchable list of all clients."""

    async def test_list_clients_returns_200(self, tenant_a_client: AsyncClient):
        """GET /api/v1/crm/clients returns 200 with list."""
        response = await tenant_a_client.get("/api/v1/crm/clients")
        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list)

    async def test_list_clients_with_search(self, tenant_a_client: AsyncClient):
        """GET /api/v1/crm/clients?search=xyz filters results."""
        response = await tenant_a_client.get(
            "/api/v1/crm/clients?search=nonexistent_search_term_xyz"
        )
        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list)
        # Nonsense search term returns empty list
        assert len(data) == 0

    async def test_list_clients_pagination(self, tenant_a_client: AsyncClient):
        """GET /api/v1/crm/clients?offset=0&limit=10 respects pagination."""
        response = await tenant_a_client.get("/api/v1/crm/clients?offset=0&limit=10")
        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list)
        assert len(data) <= 10

    async def test_list_clients_requires_auth(self, async_client: AsyncClient):
        """GET /api/v1/crm/clients without token returns 401."""
        response = await async_client.get("/api/v1/crm/clients")
        assert response.status_code == 401


class TestCRMClientDetail:
    """CRM-02: Admin can view client detail with job history."""

    async def test_client_detail_not_found(self, tenant_a_client: AsyncClient):
        """GET /api/v1/crm/clients/{unknown_id} returns 404."""
        fake_id = str(uuid.uuid4())
        response = await tenant_a_client.get(f"/api/v1/crm/clients/{fake_id}")
        assert response.status_code == 404

    async def test_client_detail_requires_auth(self, async_client: AsyncClient):
        """GET /api/v1/crm/clients/{id} without token returns 401."""
        fake_id = str(uuid.uuid4())
        response = await async_client.get(f"/api/v1/crm/clients/{fake_id}")
        assert response.status_code == 401

    async def test_client_detail_response_shape(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """When a client profile exists, detail endpoint returns expected fields."""
        # Assign 'client' role to the tenant A admin user so a ClientProfile is created
        user_id = seed_two_tenants["tenant_a_user_id"]
        role_resp = await tenant_a_client.post(
            f"/api/v1/users/{user_id}/roles",
            json={"user_id": user_id, "role": "client"},
        )
        # 200/201 (assigned) or 409 (already has role) are both acceptable
        assert role_resp.status_code in (200, 201, 409)

        # ClientProfile is created lazily when the user first appears in the list
        list_response = await tenant_a_client.get("/api/v1/crm/clients?limit=5")
        assert list_response.status_code == 200
        clients = list_response.json()

        # If a client profile exists, verify the detail response shape
        if len(clients) > 0:
            client_user_id = clients[0]["user_id"]
            detail_response = await tenant_a_client.get(f"/api/v1/crm/clients/{client_user_id}")
            assert detail_response.status_code == 200
            detail = detail_response.json()
            # Verify expected fields exist
            assert "user_id" in detail
            assert "email" in detail
            assert "jobs" in detail
            assert isinstance(detail["jobs"], list)
