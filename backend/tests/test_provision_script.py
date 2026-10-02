"""Integration tests for scripts/provision.py.

Exercises the real code path: the CLI handlers open their own session against the
test database and commit, then we verify the provisioned users can authenticate
through the live /api/v1/auth/login endpoint.
"""

import argparse

import pytest
from httpx import AsyncClient

from scripts.provision import (
    add_user,
    create_company,
    list_users,
    set_password,
    set_status,
)

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


# ---------------------------------------------------------------------------
# set-status
# ---------------------------------------------------------------------------

_QUOTE_BODY = {
    "title": "Script status test",
    "tax_rate": "0.00",
    "line_items": [
        {
            "item_type": "labor",
            "description": "Work",
            "quantity": "2.000",
            "unit": "hr",
            "unit_price": "50.00",
            "sort_order": 0,
            "field": "General",
        }
    ],
}


async def _sent_quote(client: AsyncClient) -> str:
    """A quote in 'sent', created through the API so every rule applied first."""
    me = (await client.get("/api/v1/auth/me")).json()
    create = await client.post("/api/v1/quotes/", json={**_QUOTE_BODY, "client_id": me["user_id"]})
    assert create.status_code == 201, create.text
    quote_id = create.json()["id"]

    send = await client.post(f"/api/v1/quotes/{quote_id}/send")
    assert send.status_code == 200, send.text
    return quote_id


async def test_set_status_puts_a_sent_quote_back_to_draft(
    tenant_a_client: AsyncClient,
):
    quote_id = await _sent_quote(tenant_a_client)

    await set_status(_ns(company="Tenant A Corp", table="quotes", id=quote_id, status="draft"))

    after = await tenant_a_client.get(f"/api/v1/quotes/{quote_id}")
    assert after.status_code == 200, after.text
    assert after.json()["status"] == "draft"


async def test_set_status_rejects_a_value_the_database_will_not_accept(
    tenant_a_client: AsyncClient,
):
    """The CHECK constraint is the one rule still standing, so report it."""
    quote_id = await _sent_quote(tenant_a_client)

    with pytest.raises(SystemExit) as exit_info:
        await set_status(_ns(company="Tenant A Corp", table="quotes", id=quote_id, status="bogus"))

    message = str(exit_info.value)
    assert "rejected by the database" in message
    assert "draft" in message, "the allowed values should be in the message"

    unchanged = await tenant_a_client.get(f"/api/v1/quotes/{quote_id}")
    assert unchanged.json()["status"] == "sent"


async def test_set_status_refuses_a_table_with_no_status_column(
    tenant_a_client: AsyncClient,
):
    quote_id = await _sent_quote(tenant_a_client)

    with pytest.raises(SystemExit) as exit_info:
        await set_status(_ns(company="Tenant A Corp", table="users", id=quote_id, status="draft"))

    message = str(exit_info.value)
    assert "no status column" in message
    assert "quotes" in message, "it should name the tables that do have one"


async def test_set_status_will_not_reach_another_companys_row(
    tenant_a_client: AsyncClient, tenant_b_client: AsyncClient
):
    """Row level security applies to the script too, so say so plainly."""
    quote_id = await _sent_quote(tenant_a_client)

    with pytest.raises(SystemExit) as exit_info:
        await set_status(_ns(company="Tenant B Corp", table="quotes", id=quote_id, status="draft"))

    assert "check --company" in str(exit_info.value)

    untouched = await tenant_a_client.get(f"/api/v1/quotes/{quote_id}")
    assert untouched.json()["status"] == "sent"


async def test_set_status_on_an_unknown_company_stops(tenant_a_client: AsyncClient):
    with pytest.raises(SystemExit) as exit_info:
        await set_status(
            _ns(
                company="No Such Company",
                table="quotes",
                id="00000000-0000-0000-0000-000000000000",
                status="draft",
            )
        )

    assert "no company matching" in str(exit_info.value)


async def test_list_users_shows_who_can_sign_in(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, capsys
):
    """Being locked out and unsure which address is the admin is a bad place to
    be when password reset needs email and email is not working."""
    await add_user(
        _ns(
            company="Tenant A Corp",
            email="crew@example.com",
            role="worker",
            first="Cass",
            last="Crew",
            phone=None,
            password="crewpass123",
        )
    )

    await list_users(_ns(company="Tenant A Corp"))

    printed = capsys.readouterr().out
    assert "admin@tenant-a.com" in printed
    assert "crew@example.com" in printed
    assert "worker" in printed
    assert "can sign in" in printed


async def test_list_users_names_an_account_that_can_never_sign_in(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, capsys
):
    """A user with no password hash fails every attempt as "invalid email or
    password" — identical to a wrong password, and retrying can never work."""
    from sqlalchemy import text

    from app.core.database import async_session_factory

    company_id = seed_two_tenants["tenant_a_id"]
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(
            text("UPDATE users SET password_hash = NULL WHERE email = 'admin@tenant-a.com'")
        )
        await session.commit()

    await list_users(_ns(company="Tenant A Corp"))

    assert "NO PASSWORD SET" in capsys.readouterr().out
