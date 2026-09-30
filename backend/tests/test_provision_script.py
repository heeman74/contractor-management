"""Integration tests for scripts/provision.py.

Exercises the real code path: the CLI handlers open their own session against the
test database and commit, then we verify the provisioned users can authenticate
through the live /api/v1/auth/login endpoint.
"""

import argparse

import pytest
from httpx import AsyncClient

from scripts.provision import add_user, create_company, set_password

pytestmark = pytest.mark.asyncio


def _ns(**kwargs) -> argparse.Namespace:
    return argparse.Namespace(**kwargs)


async def _login(client: AsyncClient, email: str, password: str):
    return await client.post("/api/v1/auth/login", json={"email": email, "password": password})


async def test_create_company_admin_can_login(async_client: AsyncClient):
    await create_company(
        _ns(
            name="Provision Co",
            admin_email="prov-admin@example.com",
            admin_first="Ada",
            admin_last="Admin",
            phone="+61 400 000 000",
            password="provpass123",
        )
    )

    resp = await _login(async_client, "prov-admin@example.com", "provpass123")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["roles"] == ["admin"]
    assert body["access_token"]


async def test_add_user_with_role_can_login(async_client: AsyncClient):
    await create_company(
        _ns(
            name="Provision Co",
            admin_email="prov-admin@example.com",
            admin_first=None,
            admin_last=None,
            phone=None,
            password="provpass123",
        )
    )
    await add_user(
        _ns(
            company="Provision Co",
            email="prov-contractor@example.com",
            role="contractor",
            first="Jo",
            last="Bloggs",
            phone=None,
            password="provpass123",
        )
    )

    resp = await _login(async_client, "prov-contractor@example.com", "provpass123")
    assert resp.status_code == 200, resp.text
    assert resp.json()["roles"] == ["contractor"]


async def test_set_password_resets_login(async_client: AsyncClient):
    await create_company(
        _ns(
            name="Provision Co",
            admin_email="prov-admin@example.com",
            admin_first=None,
            admin_last=None,
            phone=None,
            password="oldpass123",
        )
    )
    await set_password(_ns(email="prov-admin@example.com", password="newpass456"))

    old = await _login(async_client, "prov-admin@example.com", "oldpass123")
    assert old.status_code == 401
    new = await _login(async_client, "prov-admin@example.com", "newpass456")
    assert new.status_code == 200, new.text


async def test_add_user_to_missing_company_exits():
    with pytest.raises(SystemExit):
        await add_user(
            _ns(
                company="No Such Company",
                email="orphan@example.com",
                role="contractor",
                first=None,
                last=None,
                phone=None,
                password="provpass123",
            )
        )


# ---------------------------------------------------------------------------
# A provisioned customer has to be usable, not merely able to sign in.
#
# The role alone produced a user who could log in and was invisible to the
# business: the client roster and the quote client picker both read
# client_profiles, and a quote cannot be sent without a client. So a customer
# provisioned this way could never be quoted.
#
# The mirror of that gap is POST /crm/clients, which creates the CRM record with
# no password — on the roster, unable to sign in. Between them, neither path
# produced a customer who could do both.
# ---------------------------------------------------------------------------


async def test_provisioned_client_can_log_in_and_be_quoted(async_client: AsyncClient):
    await create_company(
        _ns(
            name="Customer Co",
            admin_email="cust-admin@example.com",
            admin_first=None,
            admin_last=None,
            phone=None,
            password="provpass123",
        )
    )
    await add_user(
        _ns(
            company="Customer Co",
            email="cust-client@example.com",
            role="client",
            first="Cara",
            last="Customer",
            phone=None,
            password="provpass123",
        )
    )

    # 1. They can sign in.
    login = await _login(async_client, "cust-client@example.com", "provpass123")
    assert login.status_code == 200, login.text
    assert login.json()["roles"] == ["client"]

    # 2. They are on the roster the quote client picker reads.
    admin = await _login(async_client, "cust-admin@example.com", "provpass123")
    headers = {"Authorization": f"Bearer {admin.json()['access_token']}"}
    roster = await async_client.get("/api/v1/crm/clients", headers=headers)
    assert roster.status_code == 200, roster.text
    emails = [client["email"] for client in roster.json()]
    assert "cust-client@example.com" in emails, (
        "a provisioned client that is not on the roster cannot be quoted"
    )

    # 3. A quote addressed to them can actually be sent.
    client_id = next(
        client["user_id"]
        for client in roster.json()
        if client["email"] == "cust-client@example.com"
    )
    created = await async_client.post(
        "/api/v1/quotes/",
        headers=headers,
        json={
            "title": "For the customer",
            "client_id": client_id,
            "line_items": [
                {
                    "item_type": "labor",
                    "description": "Work",
                    "quantity": "1.000",
                    "unit": "hour",
                    "unit_price": "100.00",
                    "sort_order": 0,
                }
            ],
        },
    )
    assert created.status_code == 201, created.text
    sent = await async_client.post(f"/api/v1/quotes/{created.json()['id']}/send", headers=headers)
    assert sent.status_code == 200, sent.text


async def test_non_client_roles_stay_off_the_client_roster(async_client: AsyncClient):
    """Only a client gets the CRM record — a contractor is not a customer."""
    await create_company(
        _ns(
            name="Roster Co",
            admin_email="roster-admin@example.com",
            admin_first=None,
            admin_last=None,
            phone=None,
            password="provpass123",
        )
    )
    await add_user(
        _ns(
            company="Roster Co",
            email="roster-contractor@example.com",
            role="contractor",
            first=None,
            last=None,
            phone=None,
            password="provpass123",
        )
    )

    admin = await _login(async_client, "roster-admin@example.com", "provpass123")
    roster = await async_client.get(
        "/api/v1/crm/clients",
        headers={"Authorization": f"Bearer {admin.json()['access_token']}"},
    )
    assert roster.status_code == 200, roster.text
    assert roster.json() == []
