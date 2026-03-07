"""Sync endpoint edge-case tests — cursor validation and auth enforcement.

Tests exercise the GET /api/v1/sync endpoint's error handling for
malformed cursors, empty cursors, future cursors, and missing auth.
"""

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_sync_malformed_cursor_returns_422(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """GET /sync with an invalid date string returns 422."""
    resp = await tenant_a_client.get("/api/v1/sync", params={"cursor": "not-a-date"})
    assert resp.status_code == 422
    assert "Invalid cursor format" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_sync_empty_cursor_returns_full_data(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """GET /sync with empty cursor returns all records (full download)."""
    resp = await tenant_a_client.get("/api/v1/sync", params={"cursor": ""})
    assert resp.status_code == 200
    body = resp.json()
    # Should include the company and user from registration
    assert len(body["companies"]) >= 1
    assert len(body["users"]) >= 1


@pytest.mark.asyncio
async def test_sync_future_cursor_returns_empty(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """GET /sync with a future cursor returns empty lists."""
    resp = await tenant_a_client.get(
        "/api/v1/sync", params={"cursor": "2099-01-01T00:00:00+00:00"}
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["companies"] == []
    assert body["users"] == []
    assert body["user_roles"] == []


@pytest.mark.asyncio
async def test_sync_server_timestamp_roundtrip(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """server_timestamp from first sync can be used as cursor for next sync."""
    # First sync — get everything
    resp1 = await tenant_a_client.get("/api/v1/sync")
    assert resp1.status_code == 200
    server_ts = resp1.json()["server_timestamp"]
    assert server_ts  # non-empty

    # Second sync — use server_timestamp as cursor
    resp2 = await tenant_a_client.get(
        "/api/v1/sync", params={"cursor": server_ts}
    )
    assert resp2.status_code == 200
    # No changes since the first sync, so lists should be empty
    body2 = resp2.json()
    assert body2["companies"] == []
    assert body2["users"] == []
    assert body2["user_roles"] == []


@pytest.mark.asyncio
async def test_sync_without_auth_returns_401(async_client: AsyncClient):
    """GET /sync without Bearer token returns 401."""
    resp = await async_client.get("/api/v1/sync")
    assert resp.status_code == 401
