"""Encryption for third-party credentials the app stores on a tenant's behalf.

Per-company SMTP means holding each company's mailbox password, which is not
ours and is probably reused elsewhere. So it is encrypted at rest with a key
that lives only in the environment: a database dump on its own does not yield
the passwords.

The key is deliberately separate from ``jwt_secret_key``. Rotating the JWT
secret only logs everyone out, and that has to stay a cheap, safe operation —
if the same value also decrypted stored credentials, rotating it would silently
destroy every company's mail settings.

With no key configured, encryption is unavailable rather than skipped: storing
a credential in plaintext because a variable was unset is the failure mode this
module exists to prevent.
"""

from __future__ import annotations

from cryptography.fernet import Fernet, InvalidToken

from app.core.config import settings


class EncryptionUnavailableError(RuntimeError):
    """Raised when a secret is handled without a key configured to protect it."""


class SecretDecryptionError(RuntimeError):
    """Raised when stored ciphertext cannot be read with the current key.

    Means the key changed (or the value was not written by us) — the credential
    has to be re-entered, and reporting that is better than treating a mangled
    password as a mail failure.
    """


def encryption_available() -> bool:
    """Whether a key is configured, so callers can refuse the write up front."""
    return bool(settings.credentials_encryption_key)


def _cipher() -> Fernet:
    if not settings.credentials_encryption_key:
        raise EncryptionUnavailableError(
            "CREDENTIALS_ENCRYPTION_KEY is not set, so credentials cannot be "
            "stored. Generate one with: "
            "python -c 'from cryptography.fernet import Fernet; "
            "print(Fernet.generate_key().decode())'"
        )
    try:
        return Fernet(settings.credentials_encryption_key)
    except (ValueError, TypeError) as exc:
        raise EncryptionUnavailableError(
            "CREDENTIALS_ENCRYPTION_KEY is not a valid Fernet key: it must be "
            "44 characters of url-safe base64 encoding 32 bytes."
        ) from exc


def encrypt_secret(plaintext: str) -> str:
    """Encrypt a credential for storage. The result is safe to put in a column."""
    return _cipher().encrypt(plaintext.encode()).decode()


def decrypt_secret(ciphertext: str) -> str:
    """Recover a credential written by :func:`encrypt_secret`."""
    try:
        return _cipher().decrypt(ciphertext.encode()).decode()
    except InvalidToken as exc:
        raise SecretDecryptionError(
            "A stored credential could not be decrypted with the current "
            "CREDENTIALS_ENCRYPTION_KEY. It needs to be entered again."
        ) from exc
