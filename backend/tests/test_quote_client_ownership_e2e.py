"""A quote belongs to the client it is addressed to.

Row level security scopes a client to their company, not to their own quotes, so
every client-facing action took any client of the company. A second client could
open a quote priced for someone else, mark it viewed, and approve it — approval
being the one that creates the jobs and commits the work.

Verified against the running stack before the fix: client B approved a $5,000
quote addressed to client A and the status went to `approved`.
"""

import pytest
from httpx import AsyncClient

from scripts.provision import add_user, create_company
from tests.test_provision_script import _login, _ns

COMPANY = "Ownership Co"
ADMIN = "own-admin@example.com"
CLIENT_A = "own-client-a@example.com"
CLIENT_B = "own-client-b@example.com"
PASSWORD = "ownpass123"


async def _setup(async_client: AsyncClient) -> tuple[str, str, str, str]:
    """Admin token, client A token, client B token, and A's user id."""
    await create_company(
        _ns(
            name=COMPANY,
            admin_email=ADMIN,
            admin_first=None,
            admin_last=None,
            phone=None,
            password=PASSWORD,
        )
    )
    for email, last in ((CLIENT_A, "Alpha"), (CLIENT_B, "Bravo")):
        await add_user(
            _ns(
                company=COMPANY,
                email=email,
                role="client",
                first="Client",
                last=last,
                phone=None,
                password=PASSWORD,
            )
        )

    admin = await _login(async_client, ADMIN, PASSWORD)
    a = await _login(async_client, CLIENT_A, PASSWORD)
    b = await _login(async_client, CLIENT_B, PASSWORD)
    return (
        admin.json()["access_token"],
        a.json()["access_token"],
        b.json()["access_token"],
        a.json()["user_id"],
    )


async def _sent_quote_for(async_client: AsyncClient, admin_token: str, client_id: str) -> str:
    headers = {"Authorization": f"Bearer {admin_token}"}
    created = await async_client.post(
        "/api/v1/quotes/",
        headers=headers,
        json={
            "title": "Addressed",
            "client_id": client_id,
            "line_items": [
                {
                    "item_type": "labor",
                    "description": "Work",
                    "quantity": "1.000",
                    "unit": "hour",
                    "unit_price": "5000.00",
                    "sort_order": 0,
                }
            ],
        },
    )
    assert created.status_code == 201, created.text
    quote_id = created.json()["id"]
    sent = await async_client.post(f"/api/v1/quotes/{quote_id}/send", headers=headers)
    assert sent.status_code == 200, sent.text
    return quote_id


@pytest.mark.asyncio
async def test_another_client_cannot_approve_the_quote(async_client: AsyncClient):
    """The one that mattered: approval creates the jobs and commits the work."""
    admin_token, _, b_token, a_id = await _setup(async_client)
    quote_id = await _sent_quote_for(async_client, admin_token, a_id)

    resp = await async_client.post(
        f"/api/v1/quotes/{quote_id}/approve",
        headers={"Authorization": f"Bearer {b_token}"},
    )

    assert resp.status_code == 403, resp.text

    fetched = await async_client.get(
        f"/api/v1/quotes/{quote_id}",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert fetched.json()["status"] == "sent", "a refused approval must not change status"


@pytest.mark.asyncio
async def test_another_client_cannot_open_the_quote(async_client: AsyncClient):
    admin_token, _, b_token, a_id = await _setup(async_client)
    quote_id = await _sent_quote_for(async_client, admin_token, a_id)

    resp = await async_client.get(
        f"/api/v1/quotes/{quote_id}",
        headers={"Authorization": f"Bearer {b_token}"},
    )
    assert resp.status_code == 403, resp.text


@pytest.mark.asyncio
async def test_another_client_cannot_decline_the_quote(async_client: AsyncClient):
    admin_token, _, b_token, a_id = await _setup(async_client)
    quote_id = await _sent_quote_for(async_client, admin_token, a_id)

    resp = await async_client.post(
        f"/api/v1/quotes/{quote_id}/decline",
        headers={"Authorization": f"Bearer {b_token}"},
        json={"reason": "Not interested"},
    )
    assert resp.status_code == 403, resp.text


@pytest.mark.asyncio
async def test_the_addressed_client_can_still_view_and_approve(async_client: AsyncClient):
    """The gate must not block the client the quote is actually for."""
    admin_token, a_token, _, a_id = await _setup(async_client)
    quote_id = await _sent_quote_for(async_client, admin_token, a_id)
    headers = {"Authorization": f"Bearer {a_token}"}

    viewed = await async_client.get(f"/api/v1/quotes/{quote_id}", headers=headers)
    assert viewed.status_code == 200, viewed.text
    assert viewed.json()["status"] == "viewed", "opening it records the read receipt"

    approved = await async_client.post(f"/api/v1/quotes/{quote_id}/approve", headers=headers)
    assert approved.status_code == 200, approved.text
    assert approved.json()["status"] == "approved"
