"""Integration tests: Multi-tenant data isolation via PostgreSQL RLS.

These tests prove that Row Level Security policies enforced by the JWT-based
tenant context prevent cross-tenant data access at the database level.

Test pattern:
  - Each client has a Bearer token with a different company_id claim.
  - get_current_user extracts company_id from JWT and sets the ContextVar.
  - The after_begin SQLAlchemy event executes SET LOCAL app.current_company_id.
  - PostgreSQL RLS policies on users/user_roles filter rows to the current tenant.
"""

import pytest


@pytest.mark.asyncio
async def test_tenant_a_cannot_read_tenant_b_users(
    tenant_a_client, tenant_b_client, seed_two_tenants
):
    """Tenant A creates a user; Tenant B cannot see that user."""
    resp = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "alice@tenant-a.com"},
    )
    assert resp.status_code == 201, f"Failed to create user: {resp.text}"
    user_a_id = resp.json()["id"]

    resp = await tenant_b_client.get("/api/v1/users/")
    assert resp.status_code == 200
    visible_ids = [u["id"] for u in resp.json()]
    assert user_a_id not in visible_ids, (
        f"ISOLATION FAILURE: Tenant B can see Tenant A's user {user_a_id}."
    )


@pytest.mark.asyncio
async def test_tenant_b_cannot_read_tenant_a_users(
    tenant_a_client, tenant_b_client, seed_two_tenants
):
    """Tenant B creates a user; Tenant A cannot see that user."""
    resp = await tenant_b_client.post(
        "/api/v1/users/",
        json={"email": "bob@tenant-b.com"},
    )
    assert resp.status_code == 201, f"Failed to create user: {resp.text}"
    user_b_id = resp.json()["id"]

    resp = await tenant_a_client.get("/api/v1/users/")
    assert resp.status_code == 200
    visible_ids = [u["id"] for u in resp.json()]
    assert user_b_id not in visible_ids, (
        f"ISOLATION FAILURE: Tenant A can see Tenant B's user {user_b_id}."
    )


@pytest.mark.asyncio
async def test_each_tenant_sees_only_own_users(
    tenant_a_client, tenant_b_client, seed_two_tenants
):
    """Each tenant sees ONLY their own users — no cross-tenant leakage."""
    await tenant_a_client.post("/api/v1/users/", json={"email": "a1@tenant-a.com"})
    await tenant_a_client.post("/api/v1/users/", json={"email": "a2@tenant-a.com"})
    await tenant_b_client.post("/api/v1/users/", json={"email": "b1@tenant-b.com"})

    a_users = (await tenant_a_client.get("/api/v1/users/")).json()
    a_emails = {u["email"] for u in a_users}

    # Tenant A sees own users plus the admin user created during registration
    assert "a1@tenant-a.com" in a_emails
    assert "a2@tenant-a.com" in a_emails
    assert "b1@tenant-b.com" not in a_emails

    b_users = (await tenant_b_client.get("/api/v1/users/")).json()
    b_emails = {u["email"] for u in b_users}

    assert "b1@tenant-b.com" in b_emails
    assert "a1@tenant-a.com" not in b_emails
    assert "a2@tenant-a.com" not in b_emails


@pytest.mark.asyncio
async def test_no_auth_returns_401(async_client, seed_two_tenants):
    """No Bearer token returns 401 — endpoints are protected."""
    resp = await async_client.get("/api/v1/users/")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_tenant_a_cannot_write_to_tenant_b_data(
    tenant_a_client, tenant_b_client, seed_two_tenants
):
    """Tenant A cannot write (assign roles) to Tenant B's users."""
    resp = await tenant_b_client.post(
        "/api/v1/users/", json={"email": "target@tenant-b.com"}
    )
    assert resp.status_code == 201
    tenant_b_user_id = resp.json()["id"]

    resp = await tenant_a_client.post(
        f"/api/v1/users/{tenant_b_user_id}/roles",
        json={"user_id": tenant_b_user_id, "role": "admin"},
    )
    assert resp.status_code == 404, (
        f"ISOLATION FAILURE: Tenant A was able to assign roles to Tenant B's user. "
        f"Got status {resp.status_code}: {resp.text}"
    )
