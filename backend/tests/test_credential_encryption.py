"""Credentials the app holds for a tenant must not be readable from the database.

Per-company SMTP means storing a password that belongs to the customer, not to
us, and is probably reused elsewhere. The guarantee worth testing is narrow: the
stored form does not contain the password, the round trip is exact, and a wrong
key is reported rather than mistaken for a mail failure.
"""

from __future__ import annotations

import pytest
from cryptography.fernet import Fernet

from app.core import secrets as secrets_module
from app.core.secrets import (
    EncryptionUnavailableError,
    SecretDecryptionError,
    decrypt_secret,
    encrypt_secret,
    encryption_available,
)

_PASSWORD = "abcd efgh ijkl mnop"  # the shape of a Gmail app password


@pytest.fixture
def key(monkeypatch: pytest.MonkeyPatch) -> str:
    generated = Fernet.generate_key().decode()
    monkeypatch.setattr(secrets_module.settings, "credentials_encryption_key", generated)
    return generated


def test_round_trip_is_exact(key: str) -> None:
    assert decrypt_secret(encrypt_secret(_PASSWORD)) == _PASSWORD


def test_the_stored_form_does_not_contain_the_password(key: str) -> None:
    stored = encrypt_secret(_PASSWORD)
    assert _PASSWORD not in stored
    assert "abcd" not in stored


def test_the_same_password_encrypts_differently_each_time(key: str) -> None:
    """Fernet includes a nonce, so equal passwords are not equal ciphertext —
    otherwise the column would reveal which companies share a password."""
    assert encrypt_secret(_PASSWORD) != encrypt_secret(_PASSWORD)


def test_without_a_key_storing_is_refused_rather_than_done_in_the_clear(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(secrets_module.settings, "credentials_encryption_key", None)

    assert encryption_available() is False
    with pytest.raises(EncryptionUnavailableError) as exc:
        encrypt_secret(_PASSWORD)
    assert "Fernet.generate_key" in str(exc.value), "the error should say how to fix it"


def test_a_malformed_key_is_reported_as_configuration(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(secrets_module.settings, "credentials_encryption_key", "not-a-fernet-key")

    with pytest.raises(EncryptionUnavailableError) as exc:
        encrypt_secret(_PASSWORD)
    assert "44 characters" in str(exc.value)


def test_a_changed_key_asks_for_the_credential_again(
    key: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Rotating the key makes stored credentials unreadable, which has to be
    distinguishable from the mail server rejecting them."""
    stored = encrypt_secret(_PASSWORD)
    monkeypatch.setattr(
        secrets_module.settings,
        "credentials_encryption_key",
        Fernet.generate_key().decode(),
    )

    with pytest.raises(SecretDecryptionError) as exc:
        decrypt_secret(stored)
    assert "entered again" in str(exc.value)
