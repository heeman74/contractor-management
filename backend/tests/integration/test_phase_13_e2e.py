"""Phase 13 E2E Tests: Dual-auth (Bearer + Cookie) and client_type column.

Tests the backend changes required for web cookie-based auth alongside
existing mobile Bearer auth in get_current_user.

Coverage:
- Bearer token auth still works (regression check)
- Cookie-based access_token is accepted when no Bearer header present
- Bearer header takes priority when both present
- Missing both Bearer and cookie returns 401
- Invalid cookie token returns 401
- Login returns user_id, company_id, roles
- Refresh rotates tokens (old refresh token revoked)
- Logout revokes refresh token family
"""

import pytest
from httpx import AsyncClient

# ---------------------------------------------------------------------------
# Helper: register a fresh user and return tokens + ids
# ---------------------------------------------------------------------------


async def _register(client: AsyncClient, email: str, company: str) -> dict:
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": "TestPass123!", "company_name": company},
    )
    assert resp.status_code == 201, f"Register failed: {resp.text}"
    return resp.json()


# ---------------------------------------------------------------------------
# Task 1 Tests: Bearer regression
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_bearer_auth_still_works(async_client):
    """Bearer token auth (existing mobile flow) still works after dual-auth changes."""
    data = await _register(async_client, "bearer@phase13.com", "Bearer Corp")
    token = data["access_token"]

    # /api/v1/users/ is a protected endpoint requiring auth (lists users in tenant)
    resp = await async_client.get(
        "/api/v1/users/",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200, f"Bearer auth failed: {resp.text}"


@pytest.mark.asyncio
async def test_cookie_auth_accepted_without_bearer(async_client):
    """Cookie-based access_token is accepted when no Bearer header is present (web flow)."""
    data = await _register(async_client, "cookie@phase13.com", "Cookie Corp")
    token = data["access_token"]

    # Send token in Cookie header (no Bearer header)
    resp = await async_client.get(
        "/api/v1/users/",
        headers={"Cookie": f"access_token={token}"},
    )
    assert resp.status_code == 200, f"Cookie auth failed: {resp.text}"


@pytest.mark.asyncio
async def test_bearer_takes_priority_over_cookie(async_client):
    """Bearer header takes priority when both Bearer and cookie are present."""
    data_a = await _register(async_client, "bearer-prio@phase13.com", "Bearer Prio Corp")
    valid_token = data_a["access_token"]

    # Use a syntactically plausible but invalid (expired/fake) cookie token
    invalid_cookie_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.invalid.invalid"

    # Bearer is valid; cookie is invalid — request should succeed because Bearer wins
    resp = await async_client.get(
        "/api/v1/users/",
        headers={
            "Authorization": f"Bearer {valid_token}",
            "Cookie": f"access_token={invalid_cookie_token}",
        },
    )
    assert resp.status_code == 200, f"Bearer priority failed: {resp.text}"


@pytest.mark.asyncio
async def test_missing_both_bearer_and_cookie_returns_401(async_client):
    """Neither Bearer header nor cookie returns 401."""
    resp = await async_client.get("/api/v1/users/")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_invalid_cookie_token_returns_401(async_client):
    """Invalid/expired cookie token returns 401 when no Bearer header present."""
    invalid_token = "not.a.valid.jwt.token"

    resp = await async_client.get(
        "/api/v1/users/",
        headers={"Cookie": f"access_token={invalid_token}"},
    )
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Task 1 Tests: Login response shape
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_login_returns_user_id_company_id_roles(async_client):
    """Login endpoint returns TokenResponse with user_id, company_id, roles."""
    # Register first
    await _register(async_client, "login-shape@phase13.com", "Login Shape Corp")

    # Login
    resp = await async_client.post(
        "/api/v1/auth/login",
        json={"email": "login-shape@phase13.com", "password": "TestPass123!"},
    )
    assert resp.status_code == 200
    data = resp.json()

    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"
    assert "user_id" in data
    assert data["user_id"] is not None
    assert "company_id" in data
    assert data["company_id"] is not None
    assert "roles" in data
    assert isinstance(data["roles"], list)
    assert len(data["roles"]) > 0


# ---------------------------------------------------------------------------
# Task 1 Tests: Refresh token rotation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_refresh_rotates_tokens_and_revokes_old(async_client):
    """Refresh endpoint returns new access + refresh tokens; old refresh token is revoked."""
    data = await _register(async_client, "refresh-rotate@phase13.com", "Refresh Corp")
    old_refresh = data["refresh_token"]

    # Refresh using old token
    resp = await async_client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": old_refresh},
    )
    assert resp.status_code == 200
    new_data = resp.json()
    new_refresh = new_data["refresh_token"]
    assert new_refresh != old_refresh, "Refresh token should rotate to a new value"
    assert "access_token" in new_data

    # Using old refresh token again should fail (revoked on rotation)
    resp2 = await async_client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": old_refresh},
    )
    assert resp2.status_code in (401, 400), (
        f"Expected 401/400 for reused refresh token, got {resp2.status_code}: {resp2.text}"
    )


# ---------------------------------------------------------------------------
# Task 1 Tests: Logout revokes token family
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_logout_revokes_refresh_token_family(async_client):
    """Logout endpoint revokes the refresh token so subsequent refresh attempts fail."""
    data = await _register(async_client, "logout-family@phase13.com", "Logout Corp")
    access_token = data["access_token"]
    refresh_token = data["refresh_token"]

    # Logout
    resp = await async_client.post(
        "/api/v1/auth/logout",
        json={"refresh_token": refresh_token},
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert resp.status_code in (200, 204), f"Logout failed: {resp.text}"

    # Refresh should now fail — family is revoked
    resp2 = await async_client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    assert resp2.status_code in (401, 400), (
        f"Expected 401/400 after logout, got {resp2.status_code}: {resp2.text}"
    )
