"""Putting a sent quote back to draft.

Sending is one-way otherwise: a quote that went out too early, or went out with
the wrong number on it, had no way back. Reverting restores the pre-send state so
it can be corrected and sent again — which also makes the send path, email
included, repeatable against one quote.
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.core.email import sent_emails
from tests.quote_client_helpers import client_headers_for_quote, ensure_client

_QUOTE_BODY = {
    "title": "Panel upgrade",
    "tax_rate": "0.00",
    "line_items": [
        {
            "item_type": "labor",
            "description": "Install sub-panel",
            "quantity": "8.000",
            "unit": "hr",
            "unit_price": "75.00",
            "sort_order": 0,
            "field": "Electrical",
        }
    ],
}


@pytest.fixture(autouse=True)
def _clear_outbox():
    sent_emails.clear()
    yield
    sent_emails.clear()


async def _sent_quote(client: AsyncClient) -> dict:
    client_id = await ensure_client(client)
    create = await client.post("/api/v1/quotes/", json={**_QUOTE_BODY, "client_id": str(client_id)})
    assert create.status_code == 201, create.text
    quote_id = create.json()["id"]

    send = await client.post(f"/api/v1/quotes/{quote_id}/send")
    assert send.status_code == 200, send.text
    return send.json()


@pytest.mark.asyncio
async def test_a_sent_quote_goes_back_to_draft(tenant_a_client: AsyncClient):
    quote = await _sent_quote(tenant_a_client)
    assert quote["status"] == "sent"
    assert quote["sent_at"] is not None

    revert = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/revert-to-draft")
    assert revert.status_code == 200, revert.text

    body = revert.json()
    assert body["status"] == "draft"
    assert body["sent_at"] is None, "a draft has not been sent"
    assert body["viewed_at"] is None


@pytest.mark.asyncio
async def test_the_auto_stamped_expiry_is_cleared(tenant_a_client: AsyncClient):
    """Sending stamps 'valid today only' when no expiry was chosen.

    Keeping it would leave the next send carrying a date nobody picked — and once
    that date has passed the client cannot approve at all.
    """
    quote = await _sent_quote(tenant_a_client)
    assert quote["expiry_date"] is not None, "send stamps a default expiry"

    revert = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/revert-to-draft")
    assert revert.status_code == 200, revert.text
    assert revert.json()["expiry_date"] is None


@pytest.mark.asyncio
async def test_an_expiry_the_user_chose_survives(tenant_a_client: AsyncClient):
    client_id = await ensure_client(tenant_a_client)
    create = await tenant_a_client.post(
        "/api/v1/quotes/",
        json={
            **_QUOTE_BODY,
            "client_id": str(client_id),
            "expiry_date": "2099-12-31",
        },
    )
    assert create.status_code == 201, create.text
    quote_id = create.json()["id"]
    assert (await tenant_a_client.post(f"/api/v1/quotes/{quote_id}/send")).status_code == 200

    revert = await tenant_a_client.post(f"/api/v1/quotes/{quote_id}/revert-to-draft")
    assert revert.status_code == 200, revert.text
    assert revert.json()["expiry_date"] == "2099-12-31"


@pytest.mark.asyncio
async def test_reverting_lets_the_quote_be_sent_again(tenant_a_client: AsyncClient):
    """The point of the whole thing: the send path becomes repeatable."""
    quote = await _sent_quote(tenant_a_client)
    first_emails = len(sent_emails)
    assert first_emails == 1, sent_emails

    revert = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/revert-to-draft")
    assert revert.status_code == 200, revert.text

    resend = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert resend.status_code == 200, resend.text
    assert resend.json()["status"] == "sent"
    assert len(sent_emails) == 2, "re-sending emails the client again"


@pytest.mark.asyncio
async def test_a_draft_cannot_be_reverted(tenant_a_client: AsyncClient):
    client_id = await ensure_client(tenant_a_client)
    create = await tenant_a_client.post(
        "/api/v1/quotes/", json={**_QUOTE_BODY, "client_id": str(client_id)}
    )
    assert create.status_code == 201, create.text

    revert = await tenant_a_client.post(f"/api/v1/quotes/{create.json()['id']}/revert-to-draft")
    assert revert.status_code == 409, revert.text


@pytest.mark.asyncio
async def test_an_approved_quote_cannot_be_reverted(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """Approval has already created work; it is not a send that went out early."""
    quote = await _sent_quote(tenant_a_client)
    company_id = seed_two_tenants["tenant_a_id"]

    approve = await tenant_a_client.post(
        f"/api/v1/quotes/{quote['id']}/approve",
        headers=await client_headers_for_quote(tenant_a_client, quote["id"], company_id),
    )
    assert approve.status_code == 200, approve.text

    revert = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/revert-to-draft")
    assert revert.status_code == 409, revert.text


@pytest.mark.asyncio
async def test_another_tenant_cannot_revert_the_quote(
    tenant_a_client: AsyncClient, tenant_b_client: AsyncClient
):
    quote = await _sent_quote(tenant_a_client)

    revert = await tenant_b_client.post(f"/api/v1/quotes/{quote['id']}/revert-to-draft")
    assert revert.status_code == 404, revert.text
