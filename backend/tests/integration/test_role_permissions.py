"""Integration tests for the editable per-company role permission matrix.

Covers seeding, editor authorization (owner/admin allow, others 403), live
enforcement after an edit, unknown-key rejection, owner-lock, reset, and
/me/permissions.
"""

from uuid import UUID, uuid4

import pytest

from app.core.permissions import DEFAULT_ROLE_PERMISSIONS, PERMISSION_KEYS
from app.core.security import create_access_token

_ALL_ROLES = set(DEFAULT_ROLE_PERMISSIONS)


async def _create_user(admin_client, email: str) -> str:
    resp = await admin_client.post("/api/v1/users/", json={"email": email})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


def _token(company_id: str, roles: list[str]) -> str:
    """Mint an access token for a synthetic user with the given roles."""
    return create_access_token(uuid4(), UUID(company_id), roles)


@pytest.mark.asyncio
async def test_new_company_seeded_with_default_matrix(tenant_a_client, seed_two_tenants):
    """A registered company exposes all eight default rows and the 21-key catalog."""
    resp = await tenant_a_client.get("/api/v1/roles/permissions")
    assert resp.status_code == 200, resp.text
    body = resp.json()

    assert {item["key"] for item in body["catalog"]} == set(PERMISSION_KEYS)
    assert set(body["roles"]) == _ALL_ROLES
    assert body["roles"]["owner"] == ["*"]
    assert "roles.permissions.manage" in body["roles"]["admin"]
    assert "company.settings.manage" not in body["roles"]["admin"]


@pytest.mark.asyncio
async def test_editor_forbidden_for_role_without_manage_permission(async_client, seed_two_tenants):
    """A contractor (no roles.permissions.manage) is 403 on read and write."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = {"Authorization": f"Bearer {_token(company_id, ['contractor'])}"}

    get_resp = await async_client.get("/api/v1/roles/permissions", headers=headers)
    assert get_resp.status_code == 403, get_resp.text

    put_resp = await async_client.put(
        "/api/v1/roles/project_manager/permissions",
        json={"permissions": ["jobs.view"]},
        headers=headers,
    )
    assert put_resp.status_code == 403, put_resp.text


@pytest.mark.asyncio
async def test_put_unknown_key_rejected(tenant_a_client, seed_two_tenants):
    """Keys outside the catalog are rejected with 422."""
    resp = await tenant_a_client.put(
        "/api/v1/roles/project_manager/permissions",
        json={"permissions": ["jobs.view", "not.a.real.key"]},
    )
    assert resp.status_code == 422, resp.text


@pytest.mark.asyncio
async def test_put_owner_is_locked(tenant_a_client, seed_two_tenants):
    """The owner role cannot be edited."""
    resp = await tenant_a_client.put(
        "/api/v1/roles/owner/permissions",
        json={"permissions": ["jobs.view"]},
    )
    assert resp.status_code == 400, resp.text


@pytest.mark.asyncio
async def test_editing_a_role_changes_enforcement(async_client, tenant_a_client, seed_two_tenants):
    """Granting roles.assign to project_manager lets a PM user assign roles."""
    company_id = seed_two_tenants["tenant_a_id"]
    target_id = await _create_user(tenant_a_client, "enforcement-target@tenant-a.com")
    pm_headers = {"Authorization": f"Bearer {_token(company_id, ['project_manager'])}"}

    assign_payload = {"user_id": target_id, "role": "client"}

    # PM lacks roles.assign by default -> 403.
    before = await async_client.post(
        f"/api/v1/users/{target_id}/roles", json=assign_payload, headers=pm_headers
    )
    assert before.status_code == 403, before.text

    # Admin grants roles.assign to project_manager.
    granted = [*DEFAULT_ROLE_PERMISSIONS["project_manager"], "roles.assign"]
    put_resp = await tenant_a_client.put(
        "/api/v1/roles/project_manager/permissions",
        json={"permissions": granted},
    )
    assert put_resp.status_code == 200, put_resp.text

    # Same PM call now succeeds — enforcement reads the live matrix.
    after = await async_client.post(
        f"/api/v1/users/{target_id}/roles", json=assign_payload, headers=pm_headers
    )
    assert after.status_code == 201, after.text


@pytest.mark.asyncio
async def test_reset_restores_defaults(tenant_a_client, seed_two_tenants):
    """Reset returns a role to its default key set after an edit."""
    await tenant_a_client.put(
        "/api/v1/roles/project_manager/permissions",
        json={"permissions": ["jobs.view"]},
    )
    reset_resp = await tenant_a_client.post(
        "/api/v1/roles/permissions/reset", json={"role": "project_manager"}
    )
    assert reset_resp.status_code == 200, reset_resp.text
    roles = reset_resp.json()["roles"]
    assert set(roles["project_manager"]) == set(DEFAULT_ROLE_PERMISSIONS["project_manager"])


@pytest.mark.asyncio
async def test_me_permissions_returns_union_across_roles(async_client, seed_two_tenants):
    """A multi-role user's effective permissions are the union of their roles."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = {"Authorization": f"Bearer {_token(company_id, ['project_manager', 'gc'])}"}

    resp = await async_client.get("/api/v1/me/permissions", headers=headers)
    assert resp.status_code == 200, resp.text
    permissions = set(resp.json()["permissions"])

    assert "jobs.create" in permissions  # from project_manager
    assert "inspections.perform" in permissions  # from gc
    assert "company.settings.manage" not in permissions  # neither role grants it
