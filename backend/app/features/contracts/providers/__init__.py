"""E-signature provider selection."""

from __future__ import annotations

from app.features.contracts.providers.base import SignatureProvider
from app.features.contracts.providers.dropbox_sign import DropboxSignProvider


def get_signature_provider() -> SignatureProvider:
    """FastAPI dependency returning the configured e-sign provider.

    Overridden in tests with a fake so no network calls occur.
    """
    return DropboxSignProvider()
