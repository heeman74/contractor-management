"""User endpoint tests — CRUD operations, validation, and role management.

Tests exercise the /api/v1/users endpoints through the full ASGI stack
using JWT Bearer tokens from the seed_two_tenants fixture.
"""

from uuid import uuid4

import pytest
from httpx import AsyncClient


# ---------------------------------------------------------------------------
# Create user
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_user_returns_all_fields(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """POST /users with full payload returns 201 with all UserResponse fields."""
    payload = {
        "email": "new@tenant-a.com",
        "first_name": "Jane",
        "last_name": "Doe",
        "phone": "555-1234",
    }
    resp = await tenant_a_client.post("/api/v1/users/", json=payload)
    assert resp.status_code == 201
    body = resp.json()
    assert body["email"] == "new@tenant-a.com"
    assert body["first_name"] == "Jane"
    assert body["last_name"] == "Doe"
    assert body["phone"] == "555-1234"
    assert body["company_id"] == seed_two_tenants["tenant_a_id"]
    assert "id" in body
    assert "version" in body
    assert "created_at" in body
    assert "updated_at" in body


@pytest.mark.asyncio
async def test_create_user_minimal_fields(tenant_a_client: AsyncClient):
    """POST /users with email only returns 201, optional fields are null."""
    resp = await tenant_a_client.post(
        "/api/v1/users/", json={"email": "minimal@test.com"}
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["email"] == "minimal@test.com"
    assert body["first_name"] is None
    assert body["last_name"] is None
    assert body["phone"] is None


@pytest.mark.asyncio
async def test_create_user_invalid_email_returns_422(tenant_a_client: AsyncClient):
    """POST /users with invalid email format returns 422."""
    resp = await tenant_a_client.post(
        "/api/v1/users/", json={"email": "not-an-email"}
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_create_user_missing_email_returns_422(tenant_a_client: AsyncClient):
    """POST /users with empty body returns 422."""
    resp = await tenant_a_client.post("/api/v1/users/", json={})
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# List users
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_list_users_includes_admin_from_registration(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """GET /users includes the admin user created during registration."""
    resp = await tenant_a_client.get("/api/v1/users/")
    assert resp.status_code == 200
    users = resp.json()
    assert len(users) >= 1
    emails = [u["email"] for u in users]
    assert "admin@tenant-a.com" in emails


# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_assign_duplicate_role_behavior(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """Assigning the same role twice creates a second UserRole row (no unique constraint)."""
    user_id = seed_two_tenants["tenant_a_user_id"]

    # Assign contractor role twice
    resp1 = await tenant_a_client.post(
        f"/api/v1/users/{user_id}/roles",
        json={"user_id": user_id, "role": "contractor"},
    )
    assert resp1.status_code == 201

    resp2 = await tenant_a_client.post(
        f"/api/v1/users/{user_id}/roles",
        json={"user_id": user_id, "role": "contractor"},
    )
    assert resp2.status_code == 201

    # Both roles exist
    resp = await tenant_a_client.get(f"/api/v1/users/{user_id}/roles")
    roles = resp.json()
    contractor_roles = [r for r in roles if r["role"] == "contractor"]
    assert len(contractor_roles) == 2


@pytest.mark.asyncio
async def test_get_roles_for_user_with_no_extra_roles(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """GET /users/{id}/roles returns only the admin role from registration."""
    user_id = seed_two_tenants["tenant_a_user_id"]
    resp = await tenant_a_client.get(f"/api/v1/users/{user_id}/roles")
    assert resp.status_code == 200
    roles = resp.json()
    # The seed registers with admin role
    assert len(roles) >= 1
    assert any(r["role"] == "admin" for r in roles)


@pytest.mark.asyncio
async def test_user_response_includes_roles_field(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """UserResponse schema includes the roles list field."""
    resp = await tenant_a_client.get("/api/v1/users/")
    assert resp.status_code == 200
    users = resp.json()
    assert len(users) >= 1
    # Every user response should have a 'roles' key
    for user in users:
        assert "roles" in user
        assert isinstance(user["roles"], list)
