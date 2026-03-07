"""Security headers and HTTP edge-case tests.

Tests verify that the SecurityHeadersMiddleware adds the expected headers
and that the app handles malformed requests correctly.
"""

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_security_headers_present(async_client: AsyncClient):
    """All security headers are present on every response."""
    resp = await async_client.get("/health")
    assert resp.status_code == 200
    assert resp.headers["x-content-type-options"] == "nosniff"
    assert resp.headers["x-frame-options"] == "DENY"
    assert resp.headers["cache-control"] == "no-store"
    assert "strict-transport-security" in resp.headers


@pytest.mark.asyncio
async def test_invalid_json_body_returns_422(async_client: AsyncClient):
    """Sending malformed JSON returns 422."""
    resp = await async_client.post(
        "/api/v1/auth/login",
        content=b"{not valid json",
        headers={"Content-Type": "application/json"},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_unsupported_http_method_returns_405(async_client: AsyncClient):
    """PUT on a POST-only endpoint returns 405."""
    resp = await async_client.put(
        "/api/v1/auth/login",
        json={"email": "x@x.com", "password": "pass1234"},
    )
    assert resp.status_code == 405
