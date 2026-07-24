"""Provider-agnostic e-signature interface.

The rest of the contracts feature depends only on this protocol, so the concrete
vendor (Dropbox Sign today, DocuSign later) can be swapped without changes elsewhere.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol, runtime_checkable


@dataclass
class ProviderRequest:
    """Result of creating an embedded signature request."""

    request_id: str
    signature_id: str
    sign_url: str


@dataclass
class WebhookEvent:
    """A parsed, verified webhook event from the provider."""

    event_type: str
    request_id: str
    metadata: dict = field(default_factory=dict)


@runtime_checkable
class SignatureProvider(Protocol):
    """Abstract e-signature provider."""

    async def create_embedded_request(
        self,
        *,
        pdf_bytes: bytes,
        signer_name: str,
        signer_email: str,
        subject: str,
        metadata: dict[str, str],
    ) -> ProviderRequest:
        """Create an embedded signature request; returns ids + a signing URL."""
        ...

    async def get_sign_url(self, signature_id: str) -> str:
        """Return a fresh (short-lived) embedded signing URL for a signer."""
        ...

    async def get_signed_pdf(self, request_id: str) -> bytes:
        """Download the completed, signed PDF bytes."""
        ...

    def verify_and_parse_webhook(
        self, headers: dict[str, str], raw_body: bytes
    ) -> WebhookEvent | None:
        """Verify the provider's signature and parse the event, or None if invalid."""
        ...
