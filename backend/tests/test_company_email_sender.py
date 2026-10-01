"""Whose address does a company's mail come from?

A quote is from the contractor, not from whoever runs the instance — and the
previous version got this wrong by sending everything through one operator
mailbox. It cannot be fixed by writing the company's address into From either: a
provider only accepts a sender it has authenticated. So there are three
outcomes, and which one applies has to be unambiguous.
"""

from __future__ import annotations

import pytest
from cryptography.fernet import Fernet

from app.core import email as email_module
from app.core import secrets as secrets_module
from app.core.email import (
    TRANSPORT_COMPANY,
    TRANSPORT_DEV,
    TRANSPORT_RELAY,
    EmailService,
)
from app.core.secrets import encrypt_secret
from app.features.companies.models import Company

_APP_PASSWORD = "abcd efgh ijkl mnop"


@pytest.fixture(autouse=True)
def _encryption_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        secrets_module.settings,
        "credentials_encryption_key",
        Fernet.generate_key().decode(),
    )


@pytest.fixture
def relay(monkeypatch: pytest.MonkeyPatch) -> None:
    """An instance relay, as a deployed box would have."""
    monkeypatch.setattr(email_module.settings, "smtp_host", "smtp.relay.test")
    monkeypatch.setattr(email_module.settings, "smtp_port", 587)
    monkeypatch.setattr(email_module.settings, "smtp_use_tls", True)
    monkeypatch.setattr(email_module.settings, "smtp_user", "ops@relay.test")
    monkeypatch.setattr(email_module.settings, "smtp_password", "relay-secret")
    monkeypatch.setattr(email_module.settings, "smtp_from", "ContractorHub <ops@relay.test>")


@pytest.fixture
def no_relay(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(email_module.settings, "smtp_host", None)


def _company(**overrides) -> Company:
    company = Company(name="Acme Electrical")
    company.email_from_name = None
    company.email_from_address = None
    company.smtp_host = None
    company.smtp_port = None
    company.smtp_use_tls = True
    company.smtp_user = None
    company.smtp_password_encrypted = None
    for key, value in overrides.items():
        setattr(company, key, value)
    return company


def test_a_company_with_its_own_mailbox_sends_as_itself(relay: None) -> None:
    company = _company(
        smtp_host="smtp.gmail.com",
        smtp_port=587,
        smtp_user="steve@acme.com",
        smtp_password_encrypted=encrypt_secret(_APP_PASSWORD),
        email_from_address="steve@acme.com",
    )

    sender = EmailService.for_company(company)._sender

    assert sender.label == TRANSPORT_COMPANY
    assert sender.from_header == "Acme Electrical <steve@acme.com>"
    # No Reply-To needed: the From is already theirs.
    assert sender.reply_to is None
    assert sender.transport is not None
    assert sender.transport.host == "smtp.gmail.com"
    # The password reaches the transport decrypted, and only there.
    assert sender.transport.password == _APP_PASSWORD


def test_their_own_mailbox_is_preferred_over_the_relay(relay: None) -> None:
    company = _company(
        smtp_host="smtp.gmail.com",
        smtp_user="steve@acme.com",
        smtp_password_encrypted=encrypt_secret(_APP_PASSWORD),
    )

    sender = EmailService.for_company(company)._sender

    assert sender.transport is not None
    assert sender.transport.host == "smtp.gmail.com", "not the relay"


def test_without_a_mailbox_the_relay_carries_it_but_the_company_is_visible(
    relay: None,
) -> None:
    """The envelope stays the authenticated one — anything else is rejected —
    while the name and Reply-To make it read as the contractor's."""
    company = _company(email_from_address="steve@acme.com")

    sender = EmailService.for_company(company)._sender

    assert sender.label == TRANSPORT_RELAY
    assert sender.from_header == "Acme Electrical <ops@relay.test>"
    assert sender.reply_to == "steve@acme.com", "replies must reach the contractor"
    assert sender.transport is not None
    assert sender.transport.host == "smtp.relay.test"


def test_a_configured_display_name_wins_over_the_company_name(relay: None) -> None:
    company = _company(email_from_name="Acme Electrical Quotes", email_from_address="q@acme.com")

    sender = EmailService.for_company(company)._sender

    assert sender.from_header == "Acme Electrical Quotes <ops@relay.test>"


def test_a_display_name_with_an_accent_is_encoded_not_mangled(relay: None) -> None:
    """Trade names carry punctuation and accents; the header has to survive it."""
    from email.header import decode_header, make_header

    company = _company(email_from_name="Électrique Montréal — Devis")

    sender = EmailService.for_company(company)._sender

    name = str(make_header(decode_header(sender.from_header)))
    assert name == "Électrique Montréal — Devis <ops@relay.test>"


def test_a_company_with_no_address_gets_no_reply_to(relay: None) -> None:
    """Nothing to point replies at, so the header is omitted rather than empty."""
    sender = EmailService.for_company(_company())._sender

    assert sender.reply_to is None
    assert sender.label == TRANSPORT_RELAY


def test_with_no_relay_and_no_mailbox_nothing_is_delivered(no_relay: None) -> None:
    """Reported as not delivering, so a caller can refuse instead of pretending."""
    service = EmailService.for_company(_company(email_from_address="steve@acme.com"))

    assert service.transport_label == TRANSPORT_DEV
    assert service.delivers is False


def test_a_partial_company_config_falls_back_rather_than_half_sending(
    relay: None,
) -> None:
    """The database CHECK prevents this, so it is belt and braces: a host with no
    credentials must not be dialled."""
    company = _company(smtp_host="smtp.gmail.com")

    sender = EmailService.for_company(company)._sender

    assert sender.label == TRANSPORT_RELAY
    assert sender.transport is not None
    assert sender.transport.host == "smtp.relay.test"


def test_the_instance_sender_is_unchanged_for_app_mail(relay: None) -> None:
    """Password reset is from the app, not from a company."""
    service = EmailService()

    assert service.transport_label == TRANSPORT_RELAY
    assert service._sender.from_header == "ContractorHub <ops@relay.test>"
    assert service._sender.reply_to is None
