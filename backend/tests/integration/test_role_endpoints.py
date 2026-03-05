"""Integration tests: Role assignment and retrieval for all three role types.

Tests verify that the role assignment CRUD endpoints work correctly:
- All three role types (admin, contractor, client) can be assigned and retrieved.
- Invalid role types are rejected with HTTP 422 (Pydantic validation error).
- Role queries are tenant-scoped (RLS on user_roles table).
"""

import pytest


@pytest.mark.asyncio
async def test_assign_all_role_types(tenant_a_client, seed_two_tenants):
    """All three role types (admin, contractor, client) can be assigned to a user."""
    # Create a user
    create_resp = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "multi-role@tenant-a.com"},
    )
    assert create_resp.status_code == 201, f"Failed to create user: {create_resp.text}"
    user = create_resp.json()
    user_id = user["id"]

    # Assign each role type
    for role in ("admin", "contractor", "client"):
        resp = await tenant_a_client.post(
            f"/api/v1/users/{user_id}/roles",
            json={"user_id": user_id, "role": role},
        )
        assert resp.status_code == 201, (
            f"Failed to assign role '{role}': {resp.text}"
        )
        assigned = resp.json()
        assert assigned["role"] == role
        assert assigned["user_id"] == user_id

    # Retrieve all roles and verify all three are present
    roles_resp = await tenant_a_client.get(f"/api/v1/users/{user_id}/roles")
    assert roles_resp.status_code == 200
    assigned_roles = {r["role"] for r in roles_resp.json()}
    assert assigned_roles == {"admin", "contractor", "client"}, (
        f"Expected all three roles, got: {assigned_roles}"
    )


@pytest.mark.asyncio
async def test_invalid_role_rejected(tenant_a_client, seed_two_tenants):
    """An invalid role type is rejected with HTTP 422 (Pydantic validation error)."""
    # Create a user
    create_resp = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "bad-role@tenant-a.com"},
    )
    assert create_resp.status_code == 201
    user_id = create_resp.json()["id"]

    # Attempt to assign an invalid role
    resp = await tenant_a_client.post(
        f"/api/v1/users/{user_id}/roles",
        json={"user_id": user_id, "role": "superadmin"},
    )
    assert resp.status_code == 422, (
        f"Expected 422 for invalid role 'superadmin', got {resp.status_code}: {resp.text}"
    )


@pytest.mark.asyncio
async def test_assign_role_returns_correct_fields(tenant_a_client, seed_two_tenants):
    """Role assignment response includes all required fields."""
    create_resp = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "field-check@tenant-a.com"},
    )
    assert create_resp.status_code == 201
    user_id = create_resp.json()["id"]
    company_id = seed_two_tenants["tenant_a_id"]

    resp = await tenant_a_client.post(
        f"/api/v1/users/{user_id}/roles",
        json={"user_id": user_id, "role": "contractor"},
    )
    assert resp.status_code == 201
    role_data = resp.json()

    assert "id" in role_data
    assert role_data["user_id"] == user_id
    assert role_data["company_id"] == company_id
    assert role_data["role"] == "contractor"
    assert "created_at" in role_data


@pytest.mark.asyncio
async def test_assign_role_to_nonexistent_user_returns_404(
    tenant_a_client, seed_two_tenants
):
    """Assigning a role to a non-existent user returns HTTP 404."""
    import uuid

    fake_user_id = str(uuid.uuid4())
    resp = await tenant_a_client.post(
        f"/api/v1/users/{fake_user_id}/roles",
        json={"user_id": fake_user_id, "role": "admin"},
    )
    assert resp.status_code == 404, (
        f"Expected 404 for non-existent user, got {resp.status_code}: {resp.text}"
    )


@pytest.mark.asyncio
async def test_user_roles_are_tenant_scoped(
    tenant_a_client, tenant_b_client, seed_two_tenants
):
    """Roles assigned to Tenant A's users are not visible to Tenant B."""
    # Create user in Tenant A and assign admin role
    create_resp = await tenant_a_client.post(
        "/api/v1/users/",
        json={"email": "admin@tenant-a.com"},
    )
    assert create_resp.status_code == 201
    user_a_id = create_resp.json()["id"]

    role_resp = await tenant_a_client.post(
        f"/api/v1/users/{user_a_id}/roles",
        json={"user_id": user_a_id, "role": "admin"},
    )
    assert role_resp.status_code == 201

    # Tenant B tries to get roles for Tenant A's user — should get 404 (user not visible)
    resp = await tenant_b_client.get(f"/api/v1/users/{user_a_id}/roles")
    # Either 404 (user not found) or empty list (RLS hides the roles)
    # Both are acceptable isolation behaviors
    if resp.status_code == 200:
        assert len(resp.json()) == 0, (
            "ISOLATION FAILURE: Tenant B can see Tenant A's user roles"
        )
    else:
        assert resp.status_code == 404, (
            f"Unexpected status code {resp.status_code}: {resp.text}"
        )
