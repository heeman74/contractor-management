"""Sending a quote reaches the client, as the company.

A send used to produce a push notification and nothing else: the status flipped,
the route answered 200, and nothing was ever addressed to anyone. The first fix
emailed through one instance-wide account, so every company's quotes came from
the operator's mailbox. The sender is now resolved per company.

Dev mode (no SMTP anywhere) collects messages in ``app.core.email.sent_emails``
rather than sending, so most of these assert on the message that would go out.
"""

from __future__ import annotations

import pytest
from cryptography.fernet import Fernet
from httpx import AsyncClient

from app.core import email as email_module
from app.core import secrets as secrets_module
from app.core.email import sent_emails
from tests.quote_client_helpers import ensure_client

_APP_PASSWORD = "abcd efgh ijkl mnop"

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
def _encryption_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        secrets_module.settings,
        "credentials_encryption_key",
        Fernet.generate_key().decode(),
    )


@pytest.fixture(autouse=True)
def _clear_outbox():
    sent_emails.clear()
    yield
    sent_emails.clear()


@pytest.fixture
def relay(monkeypatch: pytest.MonkeyPatch) -> dict:
    """An instance relay, and a record of what was handed to it."""
    handed: dict = {}
    monkeypatch.setattr(email_module.settings, "smtp_host", "smtp.relay.test")
    monkeypatch.setattr(email_module.settings, "smtp_from", "ContractorHub <ops@relay.test>")
    monkeypatch.setattr(
        email_module.EmailService,
        "_send_smtp",
        lambda self, to, subject, text_body, html_body: handed.update(
            {
                "to": to,
                "subject": subject,
                "text": text_body,
                "from": self._sender.from_header,
                "reply_to": self._sender.reply_to,
                "host": self._sender.transport.host,
                "password": self._sender.transport.password,
            }
        ),
    )
    return handed


async def _draft_quote_for(client: AsyncClient, client_id: str) -> dict:
    resp = await client.post("/api/v1/quotes/", json={**_QUOTE_BODY, "client_id": client_id})
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _configure_mailbox(client: AsyncClient, company_id: str) -> None:
    resp = await client.patch(
        f"/api/v1/companies/{company_id}",
        json={
            "email_from_address": "steve@acme.com",
            "smtp_host": "smtp.gmail.com",
            "smtp_user": "steve@acme.com",
            "smtp_password": _APP_PASSWORD,
        },
    )
    assert resp.status_code == 200, resp.text


@pytest.mark.asyncio
async def test_the_quote_goes_out_through_the_companys_own_mailbox(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, relay: dict
):
    """Their server, their address — not the operator's."""
    await _configure_mailbox(tenant_a_client, seed_two_tenants["tenant_a_id"])
    client_id = await ensure_client(tenant_a_client, email="recipient@example.com")
    quote = await _draft_quote_for(tenant_a_client, str(client_id))

    send = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert send.status_code == 200, send.text

    assert relay["host"] == "smtp.gmail.com", "their mailbox, not the relay"
    assert relay["password"] == _APP_PASSWORD
    assert relay["from"] == "Tenant A Corp <steve@acme.com>"
    assert relay["to"] == "recipient@example.com"
    assert f"#{quote['quote_number']}" in relay["subject"]
    assert "600.00" in relay["text"], relay["text"]
    assert f"/quotes/{quote['id']}" in relay["text"]


@pytest.mark.asyncio
async def test_without_a_mailbox_the_relay_carries_it_as_the_company(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, relay: dict
):
    """The envelope is the authenticated one; the company is the name and reply-to."""
    await tenant_a_client.patch(
        f"/api/v1/companies/{seed_two_tenants['tenant_a_id']}",
        json={"email_from_address": "quotes@acme.com"},
    )
    client_id = await ensure_client(tenant_a_client, email="recipient@example.com")
    quote = await _draft_quote_for(tenant_a_client, str(client_id))

    send = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert send.status_code == 200, send.text

    assert relay["host"] == "smtp.relay.test"
    assert relay["from"] == "Tenant A Corp <ops@relay.test>"
    assert relay["reply_to"] == "quotes@acme.com", "replies reach the contractor"


@pytest.mark.asyncio
async def test_the_recipient_is_the_quotes_client_not_the_sender(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, relay: dict
):
    await _configure_mailbox(tenant_a_client, seed_two_tenants["tenant_a_id"])
    client_id = await ensure_client(tenant_a_client, email="the.client@example.com")
    quote = await _draft_quote_for(tenant_a_client, str(client_id))

    send = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert send.status_code == 200, send.text

    assert relay["to"] == "the.client@example.com"


@pytest.mark.asyncio
async def test_a_company_with_no_mail_configured_still_sends_the_quote(
    tenant_a_client: AsyncClient,
):
    """Nothing is delivered, and the send is not blocked.

    Refusing would stop a company that has not finished setting up from using
    the app at all. Tests run with no SMTP anywhere, which is that case.
    """
    client_id = await ensure_client(tenant_a_client, email="nobody@example.com")
    quote = await _draft_quote_for(tenant_a_client, str(client_id))

    send = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert send.status_code == 200, send.text
    assert send.json()["status"] == "sent"


@pytest.mark.asyncio
async def test_a_quote_with_no_client_is_not_sent_at_all(tenant_a_client: AsyncClient):
    resp = await tenant_a_client.post("/api/v1/quotes/", json=_QUOTE_BODY)
    assert resp.status_code == 201, resp.text

    send = await tenant_a_client.post(f"/api/v1/quotes/{resp.json()['id']}/send")
    assert send.status_code == 400, send.text


@pytest.mark.asyncio
async def test_a_rejected_sign_in_leaves_the_quote_a_draft(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    """A 200 has to mean the client was emailed, so a refusal fails the send."""
    from smtplib import SMTPAuthenticationError

    await _configure_mailbox(tenant_a_client, seed_two_tenants["tenant_a_id"])

    def _reject(self, to, subject, text_body, html_body):
        raise SMTPAuthenticationError(535, b"5.7.8 Username and Password not accepted.")

    monkeypatch.setattr(email_module.EmailService, "_send_smtp", _reject)

    client_id = await ensure_client(tenant_a_client, email="rejected@example.com")
    quote = await _draft_quote_for(tenant_a_client, str(client_id))

    send = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert send.status_code == 502, send.text
    detail = send.json()["detail"]
    assert "rejected this company's sign-in" in detail, detail
    assert "retrying will not help" in detail

    after = await tenant_a_client.get(f"/api/v1/quotes/{quote['id']}")
    assert after.json()["status"] == "draft", "a failed send must not leave it sent"


@pytest.mark.asyncio
async def test_an_unreachable_server_also_leaves_it_a_draft(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    await _configure_mailbox(tenant_a_client, seed_two_tenants["tenant_a_id"])

    def _explode(self, to, subject, text_body, html_body):
        raise OSError("connection refused")

    monkeypatch.setattr(email_module.EmailService, "_send_smtp", _explode)

    client_id = await ensure_client(tenant_a_client, email="unreachable@example.com")
    quote = await _draft_quote_for(tenant_a_client, str(client_id))

    send = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert send.status_code == 502, send.text

    after = await tenant_a_client.get(f"/api/v1/quotes/{quote['id']}")
    assert after.json()["status"] == "draft"


@pytest.mark.asyncio
async def test_a_rotated_key_is_reported_rather_than_read_as_a_mail_failure(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    await _configure_mailbox(tenant_a_client, seed_two_tenants["tenant_a_id"])
    monkeypatch.setattr(
        secrets_module.settings,
        "credentials_encryption_key",
        Fernet.generate_key().decode(),
    )

    client_id = await ensure_client(tenant_a_client, email="rotated@example.com")
    quote = await _draft_quote_for(tenant_a_client, str(client_id))

    send = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert send.status_code == 400, send.text
    assert "entered again" in send.json()["detail"]

    after = await tenant_a_client.get(f"/api/v1/quotes/{quote['id']}")
    assert after.json()["status"] == "draft"


@pytest.mark.asyncio
async def test_each_company_sends_from_its_own_mailbox(
    tenant_a_client: AsyncClient,
    tenant_b_client: AsyncClient,
    seed_two_tenants: dict,
    monkeypatch: pytest.MonkeyPatch,
):
    """The bug that started this: two companies must not share a sender."""
    senders: list[str] = []
    monkeypatch.setattr(email_module.settings, "smtp_host", "smtp.relay.test")
    monkeypatch.setattr(email_module.settings, "smtp_from", "ContractorHub <ops@relay.test>")
    monkeypatch.setattr(
        email_module.EmailService,
        "_send_smtp",
        lambda self, to, subject, text_body, html_body: senders.append(self._sender.from_header),
    )

    for client, company_key, address in (
        (tenant_a_client, "tenant_a_id", "a@acme.com"),
        (tenant_b_client, "tenant_b_id", "b@bravo.com"),
    ):
        await client.patch(
            f"/api/v1/companies/{seed_two_tenants[company_key]}",
            json={
                "email_from_address": address,
                "smtp_host": "smtp.gmail.com",
                "smtp_user": address,
                "smtp_password": _APP_PASSWORD,
            },
        )
        client_id = await ensure_client(client)
        quote = await _draft_quote_for(client, str(client_id))
        send = await client.post(f"/api/v1/quotes/{quote['id']}/send")
        assert send.status_code == 200, send.text

    assert senders == [
        "Tenant A Corp <a@acme.com>",
        "Tenant B Corp <b@bravo.com>",
    ], senders
