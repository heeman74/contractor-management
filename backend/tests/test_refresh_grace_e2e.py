"""E2E tests for the refresh-token concurrent-refresh grace window.

A token rotated moments ago and reused (e.g. a second browser tab racing the
first) is a benign concurrent refresh, not theft, so it yields a fresh pair.
Reuse after the grace window — or of a logged-out / theft-revoked family — still
revokes the family and fails.
"""

import os

import pytest
from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.pool import NullPool

pytestmark = pytest.mark.asyncio

_TEST_DB_URL = "postgresql+asyncpg://appuser:apppassword@localhost:5432/contractorhub_test"


async def _register(client: AsyncClient, email: str) -> dict:
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": "SecurePass1!", "company_name": "Grace Co"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _age_revoked_tokens() -> None:
    """Push every revoked token's revoked_at past the grace window."""
    engine = create_async_engine(os.environ.get("DATABASE_URL", _TEST_DB_URL), poolclass=NullPool)
    async with engine.begin() as conn:
        await conn.execute(
            text(
                "UPDATE refresh_tokens SET revoked_at = now() - interval '1 hour' WHERE revoked = true"
            )
        )
    await engine.dispose()


class TestRefreshGrace:
    async def test_concurrent_refresh_within_grace_succeeds(self, async_client: AsyncClient):
        """Reusing a just-rotated token (second tab) returns a fresh, usable pair."""
        token_1 = (await _register(async_client, "grace1@example.com"))["refresh_token"]

        first = await async_client.post("/api/v1/auth/refresh", json={"refresh_token": token_1})
        assert first.status_code == 200
        token_2 = first.json()["refresh_token"]

        # Second tab races with the stale token_1 — tolerated within grace.
        second = await async_client.post("/api/v1/auth/refresh", json={"refresh_token": token_1})
        assert second.status_code == 200
        token_3 = second.json()["refresh_token"]
        assert token_3 != token_2

        # Both resulting tokens keep working.
        assert (
            await async_client.post("/api/v1/auth/refresh", json={"refresh_token": token_3})
        ).status_code == 200

    async def test_reuse_after_grace_revokes_family(self, async_client: AsyncClient):
        """Once the grace window passes, reusing a rotated token is treated as theft."""
        token_1 = (await _register(async_client, "grace2@example.com"))["refresh_token"]

        first = await async_client.post("/api/v1/auth/refresh", json={"refresh_token": token_1})
        assert first.status_code == 200
        token_2 = first.json()["refresh_token"]

        await _age_revoked_tokens()

        reuse = await async_client.post("/api/v1/auth/refresh", json={"refresh_token": token_1})
        assert reuse.status_code == 401

        # The family is revoked — the live token no longer refreshes either.
        after = await async_client.post("/api/v1/auth/refresh", json={"refresh_token": token_2})
        assert after.status_code == 401

    async def test_logout_not_resurrected_by_grace(self, async_client: AsyncClient):
        """A logged-out family cannot be refreshed, even immediately afterward."""
        data = await _register(async_client, "grace3@example.com")
        out = await async_client.post(
            "/api/v1/auth/logout",
            json={"refresh_token": data["refresh_token"]},
            headers={"Authorization": f"Bearer {data['access_token']}"},
        )
        assert out.status_code in (200, 204)

        resp = await async_client.post(
            "/api/v1/auth/refresh", json={"refresh_token": data["refresh_token"]}
        )
        assert resp.status_code == 401
