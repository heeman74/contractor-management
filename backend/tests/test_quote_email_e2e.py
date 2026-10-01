"""Sending a quote has to actually reach the client.

A send used to produce a push notification and nothing else: the status flipped
to sent, the route answered 200, and no email was ever addressed to anyone. From
the contractor's side that is indistinguishable from a delivered quote, which is
the one thing a quote send must not be ambiguous about.

Dev mode (no SMTP configured) collects messages in ``app.core.email.sent_emails``
rather than sending them, so these assert on the message that would go out.
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.core.email import sent_emails
from tests.quote_client_helpers import ensure_client

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


async def _draft_quote_for(client: AsyncClient, client_id: str) -> dict:
    resp = await client.post("/api/v1/quotes/", json={**_QUOTE_BODY, "client_id": client_id})
    assert resp.status_code == 201, resp.text
    return resp.json()


@pytest.fixture(autouse=True)
def _clear_outbox():
    sent_emails.clear()
    yield
    sent_emails.clear()


@pytest.mark.asyncio
async def test_sending_a_quote_emails_the_client(tenant_a_client: AsyncClient):
    client_id = await ensure_client(tenant_a_client, email="quote.recipient@example.com")
    quote = await _draft_quote_for(tenant_a_client, str(client_id))

    send = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert send.status_code == 200, send.text

    addressed = [m for m in sent_emails if m["to"] == "quote.recipient@example.com"]
    assert addressed, f"no email addressed to the client; outbox={sent_emails}"

    message = addressed[-1]
    assert f"#{quote['quote_number']}" in message["subject"], message["subject"]
    # The total and a link to act on it are the whole point of the message.
    assert "600.00" in message["text"], message["text"]
    assert f"/quotes/{quote['id']}" in message["text"]


@pytest.mark.asyncio
async def test_the_email_goes_to_the_quotes_own_client_not_the_sender(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """The recipient is the quote's client, never whoever pressed send."""
    client_id = await ensure_client(tenant_a_client, email="the.client@example.com")
    quote = await _draft_quote_for(tenant_a_client, str(client_id))

    send = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert send.status_code == 200, send.text

    recipients = {m["to"] for m in sent_emails}
    assert recipients == {"the.client@example.com"}, recipients


@pytest.mark.asyncio
async def test_a_quote_with_no_client_is_not_sent_at_all(tenant_a_client: AsyncClient):
    """Already enforced, and asserted here so the email path cannot relax it."""
    resp = await tenant_a_client.post("/api/v1/quotes/", json=_QUOTE_BODY)
    assert resp.status_code == 201, resp.text

    send = await tenant_a_client.post(f"/api/v1/quotes/{resp.json()['id']}/send")
    assert send.status_code == 400, send.text
    assert sent_emails == []


@pytest.mark.asyncio
async def test_send_fails_and_rolls_back_when_the_email_cannot_go_out(
    tenant_a_client: AsyncClient, monkeypatch: pytest.MonkeyPatch
):
    """A 200 must mean the client was emailed.

    The quote stays a draft when the mail fails, so it can be sent again rather
    than sitting in 'sent' having reached nobody.
    """
    from app.core.email import EmailService

    async def _explode(*_args, **_kwargs) -> None:
        raise OSError("smtp unreachable")

    monkeypatch.setattr(EmailService, "send_quote_to_client", _explode)

    client_id = await ensure_client(tenant_a_client, email="unreachable@example.com")
    quote = await _draft_quote_for(tenant_a_client, str(client_id))

    send = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert send.status_code == 502, send.text

    after = await tenant_a_client.get(f"/api/v1/quotes/{quote['id']}")
    assert after.status_code == 200, after.text
    assert after.json()["status"] == "draft", "a failed send must not leave it sent"


@pytest.mark.asyncio
async def test_rejected_mail_credentials_say_so_rather_than_suggest_a_retry(
    tenant_a_client: AsyncClient, monkeypatch: pytest.MonkeyPatch
):
    """Bad SMTP credentials are a configuration fault, not a transient one.

    Gmail answers 535 5.7.8 when handed an account password instead of an app
    password. Telling the user to try again would be telling them to do
    something that cannot work.
    """
    from smtplib import SMTPAuthenticationError

    from app.core.email import EmailService

    async def _reject(*_args, **_kwargs) -> None:
        raise SMTPAuthenticationError(535, b"5.7.8 Username and Password not accepted.")

    monkeypatch.setattr(EmailService, "send_quote_to_client", _reject)

    client_id = await ensure_client(tenant_a_client, email="rejected@example.com")
    quote = await _draft_quote_for(tenant_a_client, str(client_id))

    send = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert send.status_code == 502, send.text

    detail = send.json()["detail"]
    assert "rejected our sign-in" in detail, detail
    assert "retrying will not help" in detail, detail

    after = await tenant_a_client.get(f"/api/v1/quotes/{quote['id']}")
    assert after.json()["status"] == "draft"
