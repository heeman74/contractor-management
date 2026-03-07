"""Integration tests: Authentication — register, login, refresh, revocation, 401 enforcement."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
async def test_register_creates_company_user_tokens(async_client):
    """POST /auth/register creates company + user + admin role + tokens."""
    resp = await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "admin@newco.com",
            "password": "SecurePass1!",
            "company_name": "NewCo Inc",
        },
    )
    assert resp.status_code == 201
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"
    assert data["user_id"] is not None
    assert data["company_id"] is not None
    assert "admin" in data["roles"]


@pytest.mark.asyncio
async def test_login_returns_tokens(async_client):
    """POST /auth/login returns access + refresh tokens."""
    await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "login@test.com",
            "password": "SecurePass1!",
            "company_name": "Login Corp",
        },
    )

    resp = await async_client.post(
        "/api/v1/auth/login",
        json={"email": "login@test.com", "password": "SecurePass1!"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data


@pytest.mark.asyncio
async def test_login_wrong_password_returns_401(async_client):
    """Wrong password returns 401."""
    await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "wrong@test.com",
            "password": "SecurePass1!",
            "company_name": "Wrong Corp",
        },
    )

    resp = await async_client.post(
        "/api/v1/auth/login",
        json={"email": "wrong@test.com", "password": "WrongPassword!"},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_protected_endpoint_returns_401_without_token(async_client):
    """Protected endpoints return 401 without Bearer token."""
    resp = await async_client.get("/api/v1/users/")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_protected_endpoint_returns_200_with_token(async_client):
    """Protected endpoints return 200 with valid Bearer token."""
    reg = await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "auth@test.com",
            "password": "SecurePass1!",
            "company_name": "Auth Corp",
        },
    )
    token = reg.json()["access_token"]

    resp = await async_client.get(
        "/api/v1/users/",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_refresh_token_rotation(async_client):
    """Refresh returns new token pair; old refresh token is revoked."""
    reg = await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "refresh@test.com",
            "password": "SecurePass1!",
            "company_name": "Refresh Corp",
        },
    )
    refresh_token_1 = reg.json()["refresh_token"]

    # Refresh — get new pair
    resp = await async_client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": refresh_token_1},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    refresh_token_2 = data["refresh_token"]
    assert refresh_token_2 != refresh_token_1

    # Old refresh token should be revoked — reuse triggers family revocation
    resp = await async_client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": refresh_token_1},
    )
    assert resp.status_code == 401

    # New refresh token should also be revoked (family revocation)
    resp = await async_client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": refresh_token_2},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_tenant_from_jwt_overrides_header(async_client):
    """JWT company_id drives RLS, not X-Company-Id header."""
    # Register two tenants
    reg_a = await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "a@jwt-test.com",
            "password": "SecurePass1!",
            "company_name": "JWT Tenant A",
        },
    )
    token_a = reg_a.json()["access_token"]
    company_a_id = reg_a.json()["company_id"]

    reg_b = await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "b@jwt-test.com",
            "password": "SecurePass1!",
            "company_name": "JWT Tenant B",
        },
    )
    company_b_id = reg_b.json()["company_id"]

    # Create user as Tenant A
    resp = await async_client.post(
        "/api/v1/users/",
        json={"email": "user-a@jwt-test.com"},
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert resp.status_code == 201

    # Try to read Tenant A's users while sending wrong X-Company-Id header
    # JWT company_id should win
    resp = await async_client.get(
        "/api/v1/users/",
        headers={
            "Authorization": f"Bearer {token_a}",
            "X-Company-Id": company_b_id,
        },
    )
    assert resp.status_code == 200
    emails = [u["email"] for u in resp.json()]
    # JWT says Tenant A, so we should see Tenant A's users regardless of header
    assert "user-a@jwt-test.com" in emails


@pytest.mark.asyncio
async def test_register_duplicate_email_returns_409(async_client):
    """Registering with an existing email returns 409."""
    await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "dupe@test.com",
            "password": "SecurePass1!",
            "company_name": "Dupe Corp",
        },
    )

    resp = await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "dupe@test.com",
            "password": "SecurePass1!",
            "company_name": "Dupe Corp 2",
        },
    )
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_register_short_password_returns_422(async_client):
    """Password shorter than 8 chars returns 422."""
    resp = await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "short@test.com",
            "password": "short",
            "company_name": "Short Corp",
        },
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_health_check_no_auth_required(async_client):
    """Health check endpoint does not require authentication."""
    resp = await async_client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"
