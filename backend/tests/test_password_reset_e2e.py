"""E2E tests for the self-service forgot/reset password flow.

No SMTP is configured in tests, so EmailService runs in dev mode and records
each message in ``app.core.email.sent_emails``; tests read the reset link from
there to exercise the full round trip.
"""

import re

import pytest
from httpx import AsyncClient

from app.core.email import sent_emails

pytestmark = pytest.mark.asyncio

ORIGINAL = "TestPass123!"
NEW = "BrandNew789!"
_TOKEN_RE = re.compile(r"token=([A-Za-z0-9_\-]+)")


def _latest_reset_token(recipient: str) -> str:
    message = next(m for m in reversed(sent_emails) if m["to"] == recipient)
    match = _TOKEN_RE.search(message["text"])
    assert match, f"no reset token in email body: {message['text']!r}"
    return match.group(1)


async def _register(client: AsyncClient, email: str) -> None:
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": ORIGINAL, "company_name": "Reset Co"},
    )
    assert resp.status_code == 201, resp.text


class TestPasswordReset:
    async def test_full_reset_flow(self, async_client: AsyncClient):
        """Request a reset, follow the emailed token, and log in with the new password."""
        email = "reset-user@example.com"
        await _register(async_client, email)
        sent_emails.clear()

        forgot = await async_client.post("/api/v1/auth/forgot-password", json={"email": email})
        assert forgot.status_code == 202

        token = _latest_reset_token(email)
        reset = await async_client.post(
            "/api/v1/auth/reset-password",
            json={"token": token, "new_password": NEW},
        )
        assert reset.status_code == 204

        new_login = await async_client.post(
            "/api/v1/auth/login", json={"email": email, "password": NEW}
        )
        assert new_login.status_code == 200

        old_login = await async_client.post(
            "/api/v1/auth/login", json={"email": email, "password": ORIGINAL}
        )
        assert old_login.status_code == 401

    async def test_unknown_email_still_202_and_sends_nothing(self, async_client: AsyncClient):
        """An unregistered email gets the same 202 and produces no email (no enumeration)."""
        sent_emails.clear()
        resp = await async_client.post(
            "/api/v1/auth/forgot-password", json={"email": "nobody@example.com"}
        )
        assert resp.status_code == 202
        assert all(m["to"] != "nobody@example.com" for m in sent_emails)

    async def test_invalid_token_rejected(self, async_client: AsyncClient):
        """A garbage token returns 400."""
        resp = await async_client.post(
            "/api/v1/auth/reset-password",
            json={"token": "not-a-real-token", "new_password": NEW},
        )
        assert resp.status_code == 400

    async def test_token_is_single_use(self, async_client: AsyncClient):
        """A token cannot be reused after a successful reset."""
        email = "single-use@example.com"
        await _register(async_client, email)
        sent_emails.clear()

        await async_client.post("/api/v1/auth/forgot-password", json={"email": email})
        token = _latest_reset_token(email)

        first = await async_client.post(
            "/api/v1/auth/reset-password", json={"token": token, "new_password": NEW}
        )
        assert first.status_code == 204

        second = await async_client.post(
            "/api/v1/auth/reset-password",
            json={"token": token, "new_password": "AnotherPass1!"},
        )
        assert second.status_code == 400

    async def test_short_password_rejected(self, async_client: AsyncClient):
        """A new password under the minimum length is 422 before any token check."""
        resp = await async_client.post(
            "/api/v1/auth/reset-password",
            json={"token": "whatever", "new_password": "short"},
        )
        assert resp.status_code == 422
