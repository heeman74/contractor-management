"""Company mail settings over the API.

The password is a customer's, not ours, so the properties that matter are about
what leaves the server and who can reach it: the credential never appears in a
response, another tenant cannot read or rewrite these settings, and a test send
goes only to the caller's own address.
"""

from __future__ import annotations

import pytest
from cryptography.fernet import Fernet
from httpx import AsyncClient
from sqlalchemy import text

from app.core import email as email_module
from app.core import secrets as secrets_module
from app.core.database import async_session_factory
from app.core.email import TRANSPORT_COMPANY, TRANSPORT_DEV, TRANSPORT_RELAY, sent_emails
from app.core.secrets import decrypt_secret

_APP_PASSWORD = "abcd efgh ijkl mnop"


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


async def _stored_password_column(company_id: str) -> str | None:
    """Read the raw column, to check what actually landed in the database."""
    async with async_session_factory() as session:
        row = (
            await session.execute(
                text("SELECT smtp_password_encrypted FROM companies WHERE id = CAST(:id AS uuid)"),
                {"id": company_id},
            )
        ).first()
    return row[0] if row else None


@pytest.mark.asyncio
async def test_the_sender_can_be_set_and_is_returned(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]

    resp = await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={
            "email_from_name": "Acme Electrical",
            "email_from_address": "quotes@acme.com",
        },
    )
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["email_from_name"] == "Acme Electrical"
    assert body["email_from_address"] == "quotes@acme.com"
    assert body["smtp_configured"] is False, "no mailbox of their own yet"


@pytest.mark.asyncio
async def test_the_password_is_stored_encrypted_and_never_returned(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]

    resp = await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={
            "smtp_host": "smtp.gmail.com",
            "smtp_port": 587,
            "smtp_user": "steve@acme.com",
            "smtp_password": _APP_PASSWORD,
        },
    )
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["smtp_configured"] is True
    assert _APP_PASSWORD not in resp.text, "the password must not come back"
    assert "smtp_password" not in body
    assert "smtp_password_encrypted" not in body

    stored = await _stored_password_column(company_id)
    assert stored is not None
    assert _APP_PASSWORD not in stored, "the column must not hold plaintext"
    assert decrypt_secret(stored) == _APP_PASSWORD


@pytest.mark.asyncio
async def test_a_get_never_leaks_the_password_either(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={
            "smtp_host": "smtp.gmail.com",
            "smtp_user": "steve@acme.com",
            "smtp_password": _APP_PASSWORD,
        },
    )

    resp = await tenant_a_client.get(f"/api/v1/companies/{company_id}")
    assert resp.status_code == 200, resp.text
    assert _APP_PASSWORD not in resp.text
    assert resp.json()["smtp_configured"] is True


@pytest.mark.asyncio
async def test_without_an_encryption_key_the_write_is_refused(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    """Refused, not stored in the clear."""
    monkeypatch.setattr(secrets_module.settings, "credentials_encryption_key", None)
    company_id = seed_two_tenants["tenant_a_id"]

    resp = await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={
            "smtp_host": "smtp.gmail.com",
            "smtp_user": "steve@acme.com",
            "smtp_password": _APP_PASSWORD,
        },
    )
    assert resp.status_code == 503, resp.text
    assert "CREDENTIALS_ENCRYPTION_KEY" in resp.json()["detail"]
    assert await _stored_password_column(company_id) is None


@pytest.mark.asyncio
async def test_clearing_the_mailbox_leaves_the_sender_in_place(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={
            "email_from_address": "quotes@acme.com",
            "smtp_host": "smtp.gmail.com",
            "smtp_user": "steve@acme.com",
            "smtp_password": _APP_PASSWORD,
        },
    )

    resp = await tenant_a_client.delete(f"/api/v1/companies/{company_id}/email/smtp")
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["smtp_configured"] is False
    assert body["smtp_host"] is None
    assert body["email_from_address"] == "quotes@acme.com", "the sender survives"
    assert await _stored_password_column(company_id) is None


@pytest.mark.asyncio
async def test_another_tenant_cannot_read_or_change_these_settings(
    tenant_a_client: AsyncClient, tenant_b_client: AsyncClient, seed_two_tenants: dict
):
    """Companies carry no row level security, so this is checked explicitly."""
    company_id = seed_two_tenants["tenant_a_id"]

    rewrite = await tenant_b_client.patch(
        f"/api/v1/companies/{company_id}", json={"email_from_address": "evil@b.com"}
    )
    assert rewrite.status_code in (403, 404), rewrite.text

    test_send = await tenant_b_client.post(f"/api/v1/companies/{company_id}/email/test")
    assert test_send.status_code == 404, test_send.text

    clear = await tenant_b_client.delete(f"/api/v1/companies/{company_id}/email/smtp")
    assert clear.status_code == 404, clear.text


@pytest.mark.asyncio
async def test_the_test_send_goes_to_the_caller_not_an_address_they_supply(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """Otherwise this is a relay for sending mail as a company to anyone."""
    company_id = seed_two_tenants["tenant_a_id"]

    resp = await tenant_a_client.post(
        f"/api/v1/companies/{company_id}/email/test",
        json={"to": "victim@example.com"},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["recipient"] == "admin@tenant-a.com"
    assert all(m["to"] != "victim@example.com" for m in sent_emails), sent_emails


@pytest.mark.asyncio
async def test_the_test_send_reports_that_nothing_was_delivered_without_a_server(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    """With no mail anywhere, the test reports it rather than claiming success."""
    monkeypatch.setattr(email_module.settings, "smtp_host", None)
    company_id = seed_two_tenants["tenant_a_id"]

    resp = await tenant_a_client.post(f"/api/v1/companies/{company_id}/email/test")
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["delivered"] is False
    assert body["transport"] == TRANSPORT_DEV
    assert "nothing was sent" in body["detail"]


@pytest.mark.asyncio
async def test_the_test_send_names_the_relay_when_that_is_what_carries_it(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    company_id = seed_two_tenants["tenant_a_id"]
    await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}", json={"email_from_address": "q@acme.com"}
    )

    sent: dict = {}
    monkeypatch.setattr(email_module.settings, "smtp_host", "smtp.relay.test")
    monkeypatch.setattr(
        email_module.EmailService,
        "_send_smtp",
        lambda self, to, subject, text_body, html_body: sent.update(
            {"to": to, "from": self._sender.from_header, "reply_to": self._sender.reply_to}
        ),
    )

    resp = await tenant_a_client.post(f"/api/v1/companies/{company_id}/email/test")
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["delivered"] is True
    assert body["transport"] == TRANSPORT_RELAY
    assert "reply-to" in body["detail"]
    assert sent["reply_to"] == "q@acme.com"
    assert "Tenant A Corp" in sent["from"]


@pytest.mark.asyncio
async def test_the_test_send_uses_the_companys_own_mailbox_when_set(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    company_id = seed_two_tenants["tenant_a_id"]
    await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={
            "email_from_address": "steve@acme.com",
            "smtp_host": "smtp.gmail.com",
            "smtp_user": "steve@acme.com",
            "smtp_password": _APP_PASSWORD,
        },
    )

    used: dict = {}
    monkeypatch.setattr(
        email_module.EmailService,
        "_send_smtp",
        lambda self, to, subject, text_body, html_body: used.update(
            {
                "host": self._sender.transport.host,
                "password": self._sender.transport.password,
                "from": self._sender.from_header,
            }
        ),
    )

    resp = await tenant_a_client.post(f"/api/v1/companies/{company_id}/email/test")
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["delivered"] is True
    assert body["transport"] == TRANSPORT_COMPANY
    assert "own mailbox" in body["detail"]
    assert used["host"] == "smtp.gmail.com"
    assert used["password"] == _APP_PASSWORD, "decrypted on the way to the server"
    assert used["from"] == "Tenant A Corp <steve@acme.com>"


@pytest.mark.asyncio
async def test_a_rejected_sign_in_is_reported_rather_than_raised(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    """The operator asked about their configuration; the refusal is the answer."""
    from smtplib import SMTPAuthenticationError

    company_id = seed_two_tenants["tenant_a_id"]
    await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={
            "smtp_host": "smtp.gmail.com",
            "smtp_user": "steve@acme.com",
            "smtp_password": _APP_PASSWORD,
        },
    )

    def _reject(self, to, subject, text_body, html_body):
        raise SMTPAuthenticationError(535, b"5.7.8 Username and Password not accepted.")

    monkeypatch.setattr(email_module.EmailService, "_send_smtp", _reject)

    resp = await tenant_a_client.post(f"/api/v1/companies/{company_id}/email/test")
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["delivered"] is False
    assert "SMTPAuthenticationError" in body["detail"]
    assert "5.7.8" in body["detail"], "the provider's own words"


@pytest.mark.asyncio
async def test_a_rotated_key_asks_for_the_password_again(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    """Unreadable ciphertext must not be mistaken for the server rejecting us."""
    company_id = seed_two_tenants["tenant_a_id"]
    await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={
            "smtp_host": "smtp.gmail.com",
            "smtp_user": "steve@acme.com",
            "smtp_password": _APP_PASSWORD,
        },
    )

    monkeypatch.setattr(
        secrets_module.settings,
        "credentials_encryption_key",
        Fernet.generate_key().decode(),
    )

    resp = await tenant_a_client.post(f"/api/v1/companies/{company_id}/email/test")
    assert resp.status_code == 400, resp.text
    assert "entered again" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_status_says_the_mailbox_is_the_only_option_without_a_relay(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    """The settings screen calls this to decide whether its own mailbox section
    is optional or the only way this company can send anything."""
    monkeypatch.setattr(email_module.settings, "smtp_host", None)
    company_id = seed_two_tenants["tenant_a_id"]

    resp = await tenant_a_client.get(f"/api/v1/companies/{company_id}/email/status")
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["relay_available"] is False
    assert body["mailbox_configured"] is False
    assert body["can_send"] is False, "nothing could carry a quote right now"
    assert body["transport"] == TRANSPORT_DEV


@pytest.mark.asyncio
async def test_status_reports_the_relay_when_the_server_has_one(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch: pytest.MonkeyPatch
):
    company_id = seed_two_tenants["tenant_a_id"]
    await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}", json={"email_from_address": "q@acme.com"}
    )
    monkeypatch.setattr(email_module.settings, "smtp_host", "smtp.relay.test")
    monkeypatch.setattr(email_module.settings, "smtp_from", "ContractorHub <ops@relay.test>")

    resp = await tenant_a_client.get(f"/api/v1/companies/{company_id}/email/status")
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["relay_available"] is True
    assert body["can_send"] is True, "their own mailbox is genuinely optional here"
    assert body["transport"] == TRANSPORT_RELAY
    assert body["sender"] == "Tenant A Corp <ops@relay.test>"
    assert body["reply_to"] == "q@acme.com"


@pytest.mark.asyncio
async def test_status_reports_the_companys_own_mailbox_once_set(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={
            "email_from_address": "steve@acme.com",
            "smtp_host": "smtp.gmail.com",
            "smtp_user": "steve@acme.com",
            "smtp_password": _APP_PASSWORD,
        },
    )

    resp = await tenant_a_client.get(f"/api/v1/companies/{company_id}/email/status")
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["mailbox_configured"] is True
    assert body["can_send"] is True
    assert body["transport"] == TRANSPORT_COMPANY
    assert body["sender"] == "Tenant A Corp <steve@acme.com>"
    assert body["reply_to"] is None, "the sender is already theirs"
    # Still never the credential.
    assert _APP_PASSWORD not in resp.text


@pytest.mark.asyncio
async def test_status_is_not_readable_by_another_tenant(
    tenant_b_client: AsyncClient, seed_two_tenants: dict
):
    resp = await tenant_b_client.get(
        f"/api/v1/companies/{seed_two_tenants['tenant_a_id']}/email/status"
    )
    assert resp.status_code == 404, resp.text
