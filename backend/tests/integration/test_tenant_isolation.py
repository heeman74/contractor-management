"""Integration tests: Multi-tenant data isolation via PostgreSQL RLS.

These are the most critical tests in Phase 1. They prove that Row Level Security
policies enforced by the after_begin SET LOCAL mechanism prevent cross-tenant
data access at the database level.

Test pattern:
  - Each client has a different X-Company-Id header.
  - TenantMiddleware sets the ContextVar per async task.
  - The after_begin SQLAlchemy event executes SET LOCAL app.current_company_id.
  - PostgreSQL RLS policies on users/user_roles filter rows to the current tenant.

If any test here fails, Phase 1 is NOT complete — the RLS architecture is unsound.
"""

import pytest


@pytest.mark.asyncio
async def test_tenant_a_cannot_read_tenant_b_users(
    tenant_a_client, tenant_b_client, seed_two_tenants
):
    """Tenant A creates a user; Tenant B cannot see that user.

    PROOF: RLS on the users table prevents SELECT across tenant boundary.
    """
    # Tenant A creates a user
    resp = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "alice@tenant-a.com"},
    )
    assert resp.status_code == 201, f"Failed to create user: {resp.text}"
    user_a_id = resp.json()["id"]

    # Tenant B lists users — must NOT include Tenant A's user
    resp = await tenant_b_client.get("/api/v1/users/")
    assert resp.status_code == 200
    visible_ids = [u["id"] for u in resp.json()]
    assert user_a_id not in visible_ids, (
        f"ISOLATION FAILURE: Tenant B can see Tenant A's user {user_a_id}. "
        "RLS policy is not working correctly."
    )


@pytest.mark.asyncio
async def test_tenant_b_cannot_read_tenant_a_users(
    tenant_a_client, tenant_b_client, seed_two_tenants
):
    """Tenant B creates a user; Tenant A cannot see that user.

    Mirror of test_tenant_a_cannot_read_tenant_b_users — isolation is bidirectional.
    """
    # Tenant B creates a user
    resp = await tenant_b_client.post(
        "/api/v1/users/",
        json={"email": "bob@tenant-b.com"},
    )
    assert resp.status_code == 201, f"Failed to create user: {resp.text}"
    user_b_id = resp.json()["id"]

    # Tenant A lists users — must NOT include Tenant B's user
    resp = await tenant_a_client.get("/api/v1/users/")
    assert resp.status_code == 200
    visible_ids = [u["id"] for u in resp.json()]
    assert user_b_id not in visible_ids, (
        f"ISOLATION FAILURE: Tenant A can see Tenant B's user {user_b_id}. "
        "RLS policy is not working correctly."
    )


@pytest.mark.asyncio
async def test_each_tenant_sees_only_own_users(
    tenant_a_client, tenant_b_client, seed_two_tenants
):
    """Each tenant sees ONLY their own users — no cross-tenant leakage.

    Positive case: verifies correct data is visible, not just that wrong data is hidden.
    """
    # Tenant A creates two users
    await tenant_a_client.post("/api/v1/users/", json={"email": "a1@tenant-a.com"})
    await tenant_a_client.post("/api/v1/users/", json={"email": "a2@tenant-a.com"})

    # Tenant B creates one user
    await tenant_b_client.post("/api/v1/users/", json={"email": "b1@tenant-b.com"})

    # Verify Tenant A sees their users and NOT Tenant B's
    a_users = (await tenant_a_client.get("/api/v1/users/")).json()
    a_emails = {u["email"] for u in a_users}

    assert "a1@tenant-a.com" in a_emails, "Tenant A cannot see its own user a1"
    assert "a2@tenant-a.com" in a_emails, "Tenant A cannot see its own user a2"
    assert "b1@tenant-b.com" not in a_emails, (
        "ISOLATION FAILURE: Tenant A can see Tenant B's user b1"
    )

    # Verify Tenant B sees their user and NOT Tenant A's
    b_users = (await tenant_b_client.get("/api/v1/users/")).json()
    b_emails = {u["email"] for u in b_users}

    assert "b1@tenant-b.com" in b_emails, "Tenant B cannot see its own user b1"
    assert "a1@tenant-a.com" not in b_emails, (
        "ISOLATION FAILURE: Tenant B can see Tenant A's user a1"
    )
    assert "a2@tenant-a.com" not in b_emails, (
        "ISOLATION FAILURE: Tenant B can see Tenant A's user a2"
    )


@pytest.mark.asyncio
async def test_no_tenant_header_returns_empty(async_client, seed_two_tenants):
    """No X-Company-Id header returns empty user list — safe default.

    When no tenant is set, the RLS policy evaluates current_company_id as NULL,
    which matches no rows. This is the safe-by-default behavior.

    NOTE: The create_user endpoint requires X-Company-Id (returns 400 without it).
    This test only verifies the list endpoint behavior with no tenant context.
    """
    # Create users as Tenant A so there IS data in the DB
    tenant_a_id = seed_two_tenants["tenant_a_id"]
    from httpx import ASGITransport, AsyncClient
    from app.main import app

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"X-Company-Id": tenant_a_id},
    ) as tenant_a:
        await tenant_a.post("/api/v1/users/", json={"email": "visible@tenant-a.com"})

    # Now list without a tenant header — should return empty (RLS blocks all rows)
    resp = await async_client.get("/api/v1/users/")
    assert resp.status_code == 200
    assert len(resp.json()) == 0, (
        f"ISOLATION FAILURE: No-tenant request returned {len(resp.json())} users. "
        "RLS safe-default is broken — users visible without tenant context."
    )


@pytest.mark.asyncio
async def test_tenant_a_cannot_write_to_tenant_b_data(
    tenant_a_client, tenant_b_client, seed_two_tenants
):
    """Tenant A cannot write (assign roles) to Tenant B's users.

    PROOF: The service derives company_id from TenantMiddleware ContextVar,
    not from request body. Tenant A's requests always write to Tenant A.
    RLS on user_roles prevents Tenant A from reading Tenant B's users,
    so role assignment for a cross-tenant user_id returns 404.
    """
    # Tenant B creates a user
    resp = await tenant_b_client.post(
        "/api/v1/users/", json={"email": "target@tenant-b.com"}
    )
    assert resp.status_code == 201
    tenant_b_user_id = resp.json()["id"]

    # Tenant A attempts to assign a role to Tenant B's user — must fail
    resp = await tenant_a_client.post(
        f"/api/v1/users/{tenant_b_user_id}/roles",
        json={"user_id": tenant_b_user_id, "role": "admin"},
    )
    # Expect 404 — Tenant A's RLS context cannot see Tenant B's user
    assert resp.status_code == 404, (
        f"ISOLATION FAILURE: Tenant A was able to assign roles to Tenant B's user. "
        f"Got status {resp.status_code}: {resp.text}"
    )
