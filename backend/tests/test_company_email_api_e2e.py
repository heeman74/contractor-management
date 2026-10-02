"""Sending over HTTPS, for a host that blocks outgoing SMTP.

Measured on the deployed instance: smtp.gmail.com times out on both 587 and 465
with no answer at all. That is the platform discarding outbound mail, and no
port, provider or credential changes it — the only way out is a provider whose
API is an ordinary HTTPS request.

The key is a customer's credential, so the properties that matter are the same
as the SMTP password beside it: it never comes back, and it is not readable from
the database.
"""

from __future__ import annotations

import pytest
from cryptography.fernet import Fernet
from httpx import AsyncClient
from sqlalchemy import text

from app.core import email as email_module
from app.core import email_providers as providers_module
from app.core import secrets as secrets_module
from app.core.database import async_session_factory
from app.core.email import TRANSPORT_API
from app.core.email_providers import MailApiError
from app.core.secrets import decrypt_secret

_API_KEY = "re_a1b2c3d4e5f6g7h8"


@pytest.fixture(autouse=True)
def _encryption_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        secrets_module.settings,
        "credentials_encryption_key",
        Fernet.generate_key().decode(),
    )


async def _stored_key(company_id: str) -> str | None:
    async with async_session_factory() as session:
        row = (
            await session.execute(
                text("SELECT email_api_key_encrypted FROM companies WHERE id = CAST(:id AS uuid)"),
                {"id": company_id},
            )
        ).first()
    return row[0] if row else None


async def _configure(client: AsyncClient, company_id: str, **overrides) -> dict:
    payload = {
        "email_from_address": "quotes@acme.com",
        "email_api_provider": "resend",
        "email_api_key": _API_KEY,
        **overrides,
    }
    resp = await client.patch(f"/api/v1/companies/{company_id}", json=payload)
    assert resp.status_code == 200, resp.text
    return resp.json()


@pytest.mark.asyncio
async def test_the_key_is_stored_encrypted_and_never_returned(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]

    body = await _configure(tenant_a_client, company_id)

    assert body["email_api_provider"] == "resend"
    assert body["email_api_configured"] is True
    assert _API_KEY not in str(body)
    assert "email_api_key" not in body

    stored = await _stored_key(company_id)
    assert stored is not None
    assert _API_KEY not in stored
    assert decrypt_secret(stored) == _API_KEY


@pytest.mark.asyncio
async def test_a_get_does_not_leak_the_key_either(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    await _configure(tenant_a_client, company_id)

    resp = await tenant_a_client.get(f"/api/v1/companies/{company_id}")
    assert _API_KEY not in resp.text
    assert resp.json()["email_api_configured"] is True


@pytest.mark.asyncio
async def test_an_unknown_provider_is_refused(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    resp = await tenant_a_client.patch(
        f"/api/v1/companies/{seed_two_tenants['tenant_a_id']}",
        json={"email_api_provider": "not-a-provider", "email_api_key": _API_KEY},
    )
    assert resp.status_code == 422, resp.text


@pytest.mark.asyncio
async def test_the_provider_is_preferred_over_smtp(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    """A company only configures this where SMTP cannot work."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _configure(
        tenant_a_client,
        company_id,
        smtp_host="smtp.gmail.com",
        smtp_user="steve@acme.com",
        smtp_password="app pass word here",
    )

    sent: dict = {}

    async def _capture(**kwargs):
        sent.update(kwargs)

    monkeypatch.setattr(email_module, "send_via_api", _capture)

    resp = await tenant_a_client.post(f"/api/v1/companies/{company_id}/email/test")
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["delivered"] is True
    assert body["transport"] == TRANSPORT_API
    assert "email provider" in body["detail"]
    assert sent["provider_name"] == "resend"
    assert sent["api_key"] == _API_KEY, "decrypted on the way to the provider"
    assert sent["sender"] == "Tenant A Corp <quotes@acme.com>"


@pytest.mark.asyncio
async def test_a_provider_refusal_is_reported_in_its_own_words(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    """ "The provider said no" is not actionable; the reason almost always is."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _configure(tenant_a_client, company_id)

    async def _refuse(**_kwargs):
        raise MailApiError("Resend refused the message (403): The acme.com domain is not verified.")

    monkeypatch.setattr(email_module, "send_via_api", _refuse)

    resp = await tenant_a_client.post(f"/api/v1/companies/{company_id}/email/test")
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["delivered"] is False
    assert "not verified" in body["detail"]


@pytest.mark.asyncio
async def test_clearing_the_provider_falls_back_without_losing_the_sender(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    await _configure(tenant_a_client, company_id)

    resp = await tenant_a_client.delete(f"/api/v1/companies/{company_id}/email/api")
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["email_api_configured"] is False
    assert body["email_api_provider"] is None
    assert body["email_from_address"] == "quotes@acme.com", "the sender survives"
    assert await _stored_key(company_id) is None


@pytest.mark.asyncio
async def test_status_reports_that_mail_can_be_sent_through_a_provider(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    """With no relay and no mailbox, a provider is the only thing that delivers."""
    monkeypatch.setattr(email_module.settings, "smtp_host", None)
    company_id = seed_two_tenants["tenant_a_id"]
    await _configure(tenant_a_client, company_id)

    resp = await tenant_a_client.get(f"/api/v1/companies/{company_id}/email/status")
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["api_configured"] is True
    assert body["can_send"] is True
    assert body["transport"] == TRANSPORT_API


@pytest.mark.asyncio
async def test_another_tenant_cannot_clear_the_provider(
    tenant_b_client: AsyncClient, seed_two_tenants: dict
):
    resp = await tenant_b_client.delete(
        f"/api/v1/companies/{seed_two_tenants['tenant_a_id']}/email/api"
    )
    assert resp.status_code == 404, resp.text


@pytest.mark.asyncio
async def test_each_provider_builds_the_body_it_documents(
    monkeypatch: pytest.MonkeyPatch,
):
    """Three providers differ only in the shape of one JSON body, so the shapes
    are what is worth pinning down."""
    captured: dict = {}

    class _Response:
        status_code = 200

        def json(self):
            return {}

    class _Client:
        def __init__(self, **_kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return False

        async def post(self, url, headers, json):
            captured.update({"url": url, "headers": headers, "json": json})
            return _Response()

    monkeypatch.setattr(providers_module.httpx, "AsyncClient", _Client)

    async def send(provider: str) -> dict:
        await providers_module.send_via_api(
            provider_name=provider,
            api_key="KEY",
            sender="Acme <quotes@acme.com>",
            to="client@example.com",
            subject="Quote #1",
            text_body="text",
            html_body="<p>html</p>",
        )
        return dict(captured)

    resend = await send("resend")
    assert resend["url"] == "https://api.resend.com/emails"
    assert resend["headers"]["Authorization"] == "Bearer KEY"
    assert resend["json"]["to"] == ["client@example.com"]

    sendgrid = await send("sendgrid")
    assert sendgrid["url"] == "https://api.sendgrid.com/v3/mail/send"
    assert sendgrid["json"]["from"] == {"email": "quotes@acme.com", "name": "Acme"}
    assert sendgrid["json"]["personalizations"][0]["to"][0]["email"] == ("client@example.com")

    postmark = await send("postmark")
    assert postmark["url"] == "https://api.postmarkapp.com/email"
    assert postmark["headers"]["X-Postmark-Server-Token"] == "KEY"
    assert postmark["json"]["From"] == "Acme <quotes@acme.com>"


@pytest.mark.asyncio
async def test_a_provider_this_app_does_not_know_is_named_as_such() -> None:
    with pytest.raises(MailApiError) as exc:
        await providers_module.send_via_api(
            provider_name="mystery",
            api_key="KEY",
            sender="a@b.com",
            to="c@d.com",
            subject="s",
            text_body="t",
            html_body="h",
        )

    assert "resend" in str(exc.value), "it should list what it does know"


@pytest.mark.asyncio
async def test_sending_a_quote_uses_the_provider(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    """The whole point: a quote reaches the client from a host that blocks SMTP."""
    from tests.quote_client_helpers import ensure_client

    company_id = seed_two_tenants["tenant_a_id"]
    await _configure(tenant_a_client, company_id)

    sent: dict = {}

    async def _capture(**kwargs):
        sent.update(kwargs)

    monkeypatch.setattr(email_module, "send_via_api", _capture)

    client_id = await ensure_client(tenant_a_client, email="recipient@example.com")
    create = await tenant_a_client.post(
        "/api/v1/quotes/",
        json={
            "title": "Panel upgrade",
            "tax_rate": "0.00",
            "client_id": str(client_id),
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
        },
    )
    assert create.status_code == 201, create.text

    send = await tenant_a_client.post(f"/api/v1/quotes/{create.json()['id']}/send")
    assert send.status_code == 200, send.text

    assert sent["to"] == "recipient@example.com"
    assert sent["provider_name"] == "resend"
    assert "600.00" in sent["text_body"]
