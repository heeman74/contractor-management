"""Dropbox Sign (HelloSign) implementation of SignatureProvider.

Thin httpx client against the v3 API — no vendor SDK, to keep dependencies minimal.
All secrets come from settings (env). Embedded signing is used so both the mobile
WebView and the emailed magic-link web page host the same ceremony; signature/date
fields are placed via the text tags embedded in the contract PDF.
"""

from __future__ import annotations

import hashlib
import hmac
import json

import httpx

from app.core.config import settings
from app.features.contracts.providers.base import (
    ProviderRequest,
    WebhookEvent,
)

_API_BASE = "https://api.hellosign.com/v3"
_TIMEOUT = 30.0


class DropboxSignProvider:
    """SignatureProvider backed by the Dropbox Sign v3 API."""

    def __init__(self) -> None:
        if not settings.dropbox_sign_api_key or not settings.dropbox_sign_client_id:
            raise RuntimeError(
                "Dropbox Sign is not configured. Set DROPBOX_SIGN_API_KEY and "
                "DROPBOX_SIGN_CLIENT_ID."
            )
        self._api_key = settings.dropbox_sign_api_key
        self._client_id = settings.dropbox_sign_client_id
        self._test_mode = "1" if settings.dropbox_sign_test_mode else "0"

    def _auth(self) -> tuple[str, str]:
        # API key as basic-auth username, empty password.
        return (self._api_key, "")

    async def create_embedded_request(
        self,
        *,
        pdf_bytes: bytes,
        signer_name: str,
        signer_email: str,
        subject: str,
        metadata: dict[str, str],
    ) -> ProviderRequest:
        data = {
            "client_id": self._client_id,
            "test_mode": self._test_mode,
            "subject": subject,
            "use_text_tags": "1",
            "hide_text_tags": "1",
            "signers[0][name]": signer_name,
            "signers[0][email_address]": signer_email,
        }
        for key, value in metadata.items():
            data[f"metadata[{key}]"] = value
        files = {"file[0]": ("contract.pdf", pdf_bytes, "application/pdf")}

        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.post(
                f"{_API_BASE}/signature_request/create_embedded",
                data=data,
                files=files,
                auth=self._auth(),
            )
            resp.raise_for_status()
            body = resp.json()["signature_request"]

        request_id = body["signature_request_id"]
        signature_id = body["signatures"][0]["signature_id"]
        sign_url = await self.get_sign_url(signature_id)
        return ProviderRequest(request_id=request_id, signature_id=signature_id, sign_url=sign_url)

    async def get_sign_url(self, signature_id: str) -> str:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.get(
                f"{_API_BASE}/embedded/sign_url/{signature_id}", auth=self._auth()
            )
            resp.raise_for_status()
            return resp.json()["embedded"]["sign_url"]

    async def get_signed_pdf(self, request_id: str) -> bytes:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.get(
                f"{_API_BASE}/signature_request/files/{request_id}",
                params={"file_type": "pdf"},
                auth=self._auth(),
            )
            resp.raise_for_status()
            return resp.content

    def verify_and_parse_webhook(
        self, headers: dict[str, str], raw_body: bytes
    ) -> WebhookEvent | None:
        """Dropbox Sign posts form-encoded with a `json` field; event_hash is an
        HMAC-SHA256 of (event_time + event_type) keyed by the API key."""
        try:
            from urllib.parse import parse_qs

            parsed = parse_qs(raw_body.decode())
            payload = json.loads(parsed["json"][0])
            event = payload["event"]
            event_time = str(event["event_time"])
            event_type = str(event["event_type"])
            received_hash = str(event["event_hash"])
        except (KeyError, ValueError, IndexError):
            return None

        expected = hmac.new(
            self._api_key.encode(), (event_time + event_type).encode(), hashlib.sha256
        ).hexdigest()
        if not hmac.compare_digest(expected, received_hash):
            return None

        signature_request = payload.get("signature_request", {}) or {}
        return WebhookEvent(
            event_type=event_type,
            request_id=str(signature_request.get("signature_request_id", "")),
            metadata=signature_request.get("metadata", {}) or {},
        )
