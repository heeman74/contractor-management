"""Editing the company profile.

Company details are printed on every quote, invoice and contract a client sees,
and the endpoint that changes them took any authenticated caller — a worker could
rename the company or rewrite its licence number. It is now gated on
company.settings.manage.

That key used to be owner-only, which made it unreachable: no code path assigns
the `owner` role, so nobody held it and the profile could not be edited at all.
It belongs to admin now, and 0045 grants it to companies that already existed.
"""

import pytest
from httpx import AsyncClient

from scripts.provision import add_user, create_company
from tests.test_provision_script import _login, _ns

COMPANY = "Profile Co"
ADMIN_EMAIL = "profile-admin@example.com"
WORKER_EMAIL = "profile-worker@example.com"
PASSWORD = "profilepass123"


async def _provision(async_client: AsyncClient) -> tuple[str, str, str]:
    await create_company(
        _ns(
            name=COMPANY,
            admin_email=ADMIN_EMAIL,
            admin_first=None,
            admin_last=None,
            phone=None,
            password=PASSWORD,
        )
    )
    await add_user(
        _ns(
            company=COMPANY,
            email=WORKER_EMAIL,
            role="worker",
            first=None,
            last=None,
            phone=None,
            password=PASSWORD,
        )
    )
    admin = await _login(async_client, ADMIN_EMAIL, PASSWORD)
    worker = await _login(async_client, WORKER_EMAIL, PASSWORD)
    assert admin.status_code == 200, admin.text
    assert worker.status_code == 200, worker.text
    return (
        admin.json()["company_id"],
        admin.json()["access_token"],
        worker.json()["access_token"],
    )


@pytest.mark.asyncio
async def test_admin_can_edit_every_profile_field(async_client: AsyncClient):
    company_id, admin_token, _ = await _provision(async_client)

    resp = await async_client.patch(
        f"/api/v1/companies/{company_id}",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "name": "Profile Co Renamed",
            "address": "12 Elm St",
            "phone": "555-0101",
            "license_number": "CSLB-99887",
            "business_number": "BN-4421",
            "trade_types": ["Plumbing", "Electrical"],
            "logo_url": "https://example.com/logo.png",
        },
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["name"] == "Profile Co Renamed"
    assert body["address"] == "12 Elm St"
    assert body["phone"] == "555-0101"
    assert body["license_number"] == "CSLB-99887"
    assert body["business_number"] == "BN-4421"
    assert body["trade_types"] == ["Plumbing", "Electrical"]


@pytest.mark.asyncio
async def test_a_worker_cannot_rewrite_the_company(async_client: AsyncClient):
    """The hole this closes: the endpoint took any authenticated caller, and a
    worker could rename the company that appears on client-facing documents."""
    company_id, _, worker_token = await _provision(async_client)

    resp = await async_client.patch(
        f"/api/v1/companies/{company_id}",
        headers={"Authorization": f"Bearer {worker_token}"},
        json={"name": "PWNED BY A WORKER"},
    )

    assert resp.status_code == 403, resp.text

    # And the name is untouched.
    admin = await _login(async_client, ADMIN_EMAIL, PASSWORD)
    fetched = await async_client.get(
        f"/api/v1/companies/{company_id}",
        headers={"Authorization": f"Bearer {admin.json()['access_token']}"},
    )
    assert fetched.json()["name"] == COMPANY


@pytest.mark.asyncio
async def test_editing_requires_authentication(async_client: AsyncClient):
    company_id, _, _ = await _provision(async_client)
    resp = await async_client.patch(f"/api/v1/companies/{company_id}", json={"name": "Anonymous"})
    assert resp.status_code in (401, 403), resp.text


def test_admin_holds_the_company_settings_key_by_default():
    """Owner-only made this key unreachable — nothing assigns the owner role."""
    from app.core.permissions import DEFAULT_ROLE_PERMISSIONS

    assert "company.settings.manage" in DEFAULT_ROLE_PERMISSIONS["admin"]
    # Billing is a different concern and stays with the owner.
    assert "company.billing.manage" not in DEFAULT_ROLE_PERMISSIONS["admin"]
