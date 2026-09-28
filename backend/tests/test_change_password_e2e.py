"""E2E tests for authenticated self-service password change (POST /auth/change-password)."""

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio

CURRENT = "TestPass123!"
NEW = "NewPass456!"


class TestChangePassword:
    async def test_change_then_login_with_new_password(
        self, tenant_a_client: AsyncClient, async_client: AsyncClient, seed_two_tenants: dict
    ):
        """Correct current password → 204; new password logs in, old one no longer does."""
        resp = await tenant_a_client.post(
            "/api/v1/auth/change-password",
            json={"current_password": CURRENT, "new_password": NEW},
        )
        assert resp.status_code == 204, resp.text

        ok = await async_client.post(
            "/api/v1/auth/login",
            json={"email": "admin@tenant-a.com", "password": NEW},
        )
        assert ok.status_code == 200

        stale = await async_client.post(
            "/api/v1/auth/login",
            json={"email": "admin@tenant-a.com", "password": CURRENT},
        )
        assert stale.status_code == 401

    async def test_wrong_current_password_rejected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """A wrong current password returns 400 and does not change anything."""
        resp = await tenant_a_client.post(
            "/api/v1/auth/change-password",
            json={"current_password": "WrongPass9!", "new_password": NEW},
        )
        assert resp.status_code == 400

    async def test_same_password_rejected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Reusing the current password as the new one returns 400."""
        resp = await tenant_a_client.post(
            "/api/v1/auth/change-password",
            json={"current_password": CURRENT, "new_password": CURRENT},
        )
        assert resp.status_code == 400

    async def test_short_new_password_unprocessable(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """A new password under the 8-char minimum is rejected with 422."""
        resp = await tenant_a_client.post(
            "/api/v1/auth/change-password",
            json={"current_password": CURRENT, "new_password": "short"},
        )
        assert resp.status_code == 422

    async def test_requires_auth(self, async_client: AsyncClient):
        """Unauthenticated change-password returns 401."""
        resp = await async_client.post(
            "/api/v1/auth/change-password",
            json={"current_password": CURRENT, "new_password": NEW},
        )
        assert resp.status_code == 401
