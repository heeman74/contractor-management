"""A company is only reachable by its own members.

`companies` is the tenant root and carries no row level security, so nothing in
the database stops a query for somebody else's row. The CRUD handlers this
router used to inherit fetched by id and trusted RLS to do the scoping, which
left every company readable and writable by any authenticated caller who had its
id. Proven against a running server before the fix: an admin of one company
renamed another's, and the owner saw the new name.

Another tenant's company reads as absent rather than forbidden — whether a given
id exists is not theirs to learn.
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_a_member_can_read_its_own_company(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    resp = await tenant_a_client.get(f"/api/v1/companies/{seed_two_tenants['tenant_a_id']}")

    assert resp.status_code == 200, resp.text
    assert resp.json()["name"] == "Tenant A Corp"


@pytest.mark.asyncio
async def test_a_member_can_update_its_own_company(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    resp = await tenant_a_client.patch(
        f"/api/v1/companies/{seed_two_tenants['tenant_a_id']}",
        json={"phone": "+61 400 111 222"},
    )

    assert resp.status_code == 200, resp.text
    assert resp.json()["phone"] == "+61 400 111 222"


@pytest.mark.asyncio
async def test_another_tenants_company_is_not_readable(
    tenant_b_client: AsyncClient, seed_two_tenants: dict
):
    resp = await tenant_b_client.get(f"/api/v1/companies/{seed_two_tenants['tenant_a_id']}")

    assert resp.status_code == 404, resp.text


@pytest.mark.asyncio
async def test_another_tenants_company_cannot_be_rewritten(
    tenant_a_client: AsyncClient, tenant_b_client: AsyncClient, seed_two_tenants: dict
):
    """The live reproduction: a rename across tenants, which used to return 200."""
    company_id = seed_two_tenants["tenant_a_id"]

    attack = await tenant_b_client.patch(
        f"/api/v1/companies/{company_id}",
        json={"name": "OWNED BY B", "license_number": "FAKE-1"},
    )
    assert attack.status_code == 404, attack.text

    owner_view = await tenant_a_client.get(f"/api/v1/companies/{company_id}")
    assert owner_view.json()["name"] == "Tenant A Corp", "the name must be untouched"
    assert owner_view.json()["license_number"] is None


@pytest.mark.asyncio
async def test_another_tenant_cannot_redirect_where_replies_go(
    tenant_a_client: AsyncClient, tenant_b_client: AsyncClient, seed_two_tenants: dict
):
    """The mail settings make the hole worse than a defacement.

    Reply-To on another company's quotes would route their clients' replies to
    whoever set it, and the SMTP fields would route the mail itself.
    """
    company_id = seed_two_tenants["tenant_a_id"]

    attack = await tenant_b_client.patch(
        f"/api/v1/companies/{company_id}",
        json={"email_from_address": "intercept@attacker-co.com"},
    )
    assert attack.status_code == 404, attack.text

    owner_view = await tenant_a_client.get(f"/api/v1/companies/{company_id}")
    assert owner_view.json()["email_from_address"] is None
