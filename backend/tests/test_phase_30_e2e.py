"""Phase 30 E2E anchor — financial schema foundation and RBAC audit.

This file is the shared phase E2E scaffold: a reusable JWT-minting token
helper plus the RBAC integration tests that pass with only the
permissions.py catalog/derivation change (no migration, no new endpoints
needed for this plan). Later plans (02/03/04) add their own test functions
to this same file as the cost/budget schema and endpoints land.
"""

from uuid import UUID, uuid4

import pytest

from app.core.security import create_access_token

FINANCE_KEYS = {"finance.view", "finance.manage", "finance.rates.manage"}


def _token(company_id: str, roles: list[str]) -> str:
    """Mint an access token for a synthetic user with the given roles."""
    return create_access_token(uuid4(), UUID(company_id), roles)


@pytest.mark.asyncio
async def test_new_company_seeded_with_finance_defaults(async_client, seed_two_tenants):
    """A freshly seeded company grants finance.* to project_manager and owner, never admin."""
    company_id = seed_two_tenants["tenant_a_id"]

    pm_headers = {"Authorization": f"Bearer {_token(company_id, ['project_manager'])}"}
    pm_resp = await async_client.get("/api/v1/me/permissions", headers=pm_headers)
    assert pm_resp.status_code == 200, pm_resp.text
    assert set(pm_resp.json()["permissions"]) >= FINANCE_KEYS

    owner_headers = {"Authorization": f"Bearer {_token(company_id, ['owner'])}"}
    owner_resp = await async_client.get("/api/v1/me/permissions", headers=owner_headers)
    assert owner_resp.status_code == 200, owner_resp.text
    assert set(owner_resp.json()["permissions"]) >= FINANCE_KEYS

    admin_headers = {"Authorization": f"Bearer {_token(company_id, ['admin'])}"}
    admin_resp = await async_client.get("/api/v1/me/permissions", headers=admin_headers)
    assert admin_resp.status_code == 200, admin_resp.text
    assert FINANCE_KEYS.isdisjoint(set(admin_resp.json()["permissions"]))


@pytest.mark.asyncio
async def test_admin_never_gets_finance_via_defaults(async_client, seed_two_tenants):
    """FINSEC-03 integration counterpart to the unit test: admin's live effective
    permissions (via the API, reading the seeded per-company matrix) never contain
    a finance.* key.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    admin_headers = {"Authorization": f"Bearer {_token(company_id, ['admin'])}"}

    resp = await async_client.get("/api/v1/me/permissions", headers=admin_headers)
    assert resp.status_code == 200, resp.text
    assert FINANCE_KEYS.isdisjoint(set(resp.json()["permissions"]))


@pytest.mark.asyncio
async def test_owner_can_grant_finance_to_custom_role(
    async_client, tenant_a_client, seed_two_tenants
):
    """FINSEC-02: an owner can grant finance.view to a non-default role (gc) via
    the existing matrix endpoint, and it takes effect immediately for a gc user —
    without also granting finance.manage.
    """
    company_id = seed_two_tenants["tenant_a_id"]

    current = await tenant_a_client.get("/api/v1/roles/permissions")
    assert current.status_code == 200, current.text
    gc_permissions = list(current.json()["roles"]["gc"])
    assert "finance.view" not in gc_permissions

    updated = [*gc_permissions, "finance.view"]
    put_resp = await tenant_a_client.put(
        "/api/v1/roles/gc/permissions",
        json={"permissions": updated},
    )
    assert put_resp.status_code == 200, put_resp.text

    gc_headers = {"Authorization": f"Bearer {_token(company_id, ['gc'])}"}
    gc_resp = await async_client.get("/api/v1/me/permissions", headers=gc_headers)
    assert gc_resp.status_code == 200, gc_resp.text
    gc_effective = set(gc_resp.json()["permissions"])

    assert "finance.view" in gc_effective
    assert "finance.manage" not in gc_effective
