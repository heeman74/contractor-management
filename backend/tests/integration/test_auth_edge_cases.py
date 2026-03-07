"""Auth edge-case tests — token validation, logout, and security boundaries.

Tests exercise the auth endpoints' error handling and JWT validation:
- Invalid/expired/malformed tokens
- Missing claims in JWT
- Using wrong token type for wrong endpoint
- Logout behavior (revocation + best-effort)
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from httpx import AsyncClient

from app.core.security import create_test_token
from tests.conftest import register_user


# ---------------------------------------------------------------------------
# Login edge cases
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_login_nonexistent_email_returns_401(async_client: AsyncClient):
    """Login with an email that has no account returns 401."""
    resp = await async_client.post(
        "/api/v1/auth/login",
        json={"email": "nobody@example.com", "password": "SomePass123!"},
    )
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Refresh edge cases
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_refresh_with_malformed_jwt_returns_401(async_client: AsyncClient):
    """Refresh with a non-JWT string is rejected."""
    resp = await async_client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": "not-a-jwt-at-all"},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_refresh_with_access_token_instead_of_refresh_returns_401(
    async_client: AsyncClient,
):
    """Using an access token (type=access) for refresh is rejected."""
    data = await register_user(async_client, "user@test.com", "TestCo")
    access_token = data["access_token"]

    resp = await async_client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": access_token},
    )
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Protected endpoint token validation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_protected_endpoint_with_refresh_token_returns_401(
    async_client: AsyncClient,
):
    """Using a refresh token (type=refresh) on a protected endpoint returns 401."""
    data = await register_user(async_client, "user@test.com", "TestCo")
    refresh_token = data["refresh_token"]

    resp = await async_client.get(
        "/api/v1/users/",
        headers={"Authorization": f"Bearer {refresh_token}"},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_malformed_bearer_token_returns_401(async_client: AsyncClient):
    """A garbage Bearer token returns 401."""
    resp = await async_client.get(
        "/api/v1/users/",
        headers={"Authorization": "Bearer totally-not-a-jwt"},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_expired_jwt_returns_401(async_client: AsyncClient):
    """A JWT with exp in the past is rejected."""
    token = create_test_token({
        "sub": str(uuid4()),
        "company_id": str(uuid4()),
        "roles": ["admin"],
        "type": "access",
        "exp": datetime.now(UTC) - timedelta(hours=1),
    })
    resp = await async_client.get(
        "/api/v1/users/",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_jwt_missing_sub_claim_returns_401(async_client: AsyncClient):
    """A JWT without 'sub' claim is rejected."""
    token = create_test_token({
        "company_id": str(uuid4()),
        "roles": ["admin"],
        "type": "access",
        "exp": datetime.now(UTC) + timedelta(hours=1),
    })
    resp = await async_client.get(
        "/api/v1/users/",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_jwt_missing_company_id_claim_returns_401(async_client: AsyncClient):
    """A JWT without 'company_id' claim is rejected."""
    token = create_test_token({
        "sub": str(uuid4()),
        "roles": ["admin"],
        "type": "access",
        "exp": datetime.now(UTC) + timedelta(hours=1),
    })
    resp = await async_client.get(
        "/api/v1/users/",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Logout
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_logout_revokes_refresh_token_family(async_client: AsyncClient):
    """After logout, the refresh token can no longer be used."""
    data = await register_user(async_client, "user@test.com", "TestCo")
    access_token = data["access_token"]
    refresh_token = data["refresh_token"]

    # Logout
    resp = await async_client.post(
        "/api/v1/auth/logout",
        json={"refresh_token": refresh_token},
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert resp.status_code == 204

    # Subsequent refresh should fail
    resp = await async_client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_logout_with_invalid_refresh_token_still_succeeds(
    async_client: AsyncClient,
):
    """Logout with an unknown refresh token still returns 204 (best-effort)."""
    data = await register_user(async_client, "user@test.com", "TestCo")
    access_token = data["access_token"]

    resp = await async_client.post(
        "/api/v1/auth/logout",
        json={"refresh_token": "not-a-real-token"},
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert resp.status_code == 204


@pytest.mark.asyncio
async def test_logout_requires_access_token(async_client: AsyncClient):
    """Logout without a Bearer token returns 401."""
    resp = await async_client.post(
        "/api/v1/auth/logout",
        json={"refresh_token": "some-token"},
    )
    assert resp.status_code == 401
