"""Sending mail over HTTPS, for hosts that do not allow outgoing SMTP.

Measured on this deployment: smtp.gmail.com times out on both 587 and 465, with
no answer at all. That is the platform discarding outbound mail traffic, and no
port, provider or credential changes it — the only way out is a provider whose
API is an ordinary HTTPS request, which the same host allows in every other part
of the app.

Three are supported because a contractor is likely to already have one of them,
and because they differ only in the shape of one JSON body. Each needs a verified
sender domain at the provider's end: they will refuse a From they have not been
told about, which is the same rule that makes SMTP relaying refuse it.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

import httpx

# Generous, because this runs inside a request a person is waiting on, and a
# cold provider edge is slower than a warm one.
API_TIMEOUT_SECONDS = 20


class MailApiError(RuntimeError):
    """A provider refused or could not be reached, in words a person can act on."""


@dataclass(frozen=True)
class MailApiProvider:
    """One provider's endpoint, authentication, and body shape."""

    name: str
    label: str
    url: str
    # The provider's own name for the credential, so the UI can ask for the
    # right thing rather than "password".
    credential_label: str
    auth_header: Callable[[str], dict[str, str]]
    payload: Callable[..., dict]


def _resend_payload(sender: str, to: str, subject: str, text: str, html: str) -> dict:
    return {"from": sender, "to": [to], "subject": subject, "text": text, "html": html}


def _sendgrid_payload(sender: str, to: str, subject: str, text: str, html: str) -> dict:
    return {
        "personalizations": [{"to": [{"email": to}]}],
        "from": {"email": _bare_address(sender), "name": _display_name(sender)},
        "subject": subject,
        "content": [
            {"type": "text/plain", "value": text},
            {"type": "text/html", "value": html},
        ],
    }


def _postmark_payload(sender: str, to: str, subject: str, text: str, html: str) -> dict:
    return {
        "From": sender,
        "To": to,
        "Subject": subject,
        "TextBody": text,
        "HtmlBody": html,
    }


def _bare_address(sender: str) -> str:
    from email.utils import parseaddr

    return parseaddr(sender)[1] or sender


def _display_name(sender: str) -> str:
    from email.utils import parseaddr

    return parseaddr(sender)[0]


PROVIDERS: dict[str, MailApiProvider] = {
    provider.name: provider
    for provider in (
        MailApiProvider(
            name="resend",
            label="Resend",
            url="https://api.resend.com/emails",
            credential_label="API key",
            auth_header=lambda key: {"Authorization": f"Bearer {key}"},
            payload=_resend_payload,
        ),
        MailApiProvider(
            name="sendgrid",
            label="SendGrid",
            url="https://api.sendgrid.com/v3/mail/send",
            credential_label="API key",
            auth_header=lambda key: {"Authorization": f"Bearer {key}"},
            payload=_sendgrid_payload,
        ),
        MailApiProvider(
            name="postmark",
            label="Postmark",
            url="https://api.postmarkapp.com/email",
            credential_label="Server API token",
            auth_header=lambda key: {"X-Postmark-Server-Token": key},
            payload=_postmark_payload,
        ),
    )
}

PROVIDER_NAMES = tuple(PROVIDERS)


async def send_via_api(
    *,
    provider_name: str,
    api_key: str,
    sender: str,
    to: str,
    subject: str,
    text_body: str,
    html_body: str,
) -> None:
    """Hand one message to a provider's HTTPS API.

    Failures are raised with the provider's own words where it gave any: "the
    provider said no" is not actionable, and the reason is almost always a sender
    address it has not been asked to verify.
    """
    provider = PROVIDERS.get(provider_name)
    if provider is None:
        raise MailApiError(
            f"{provider_name!r} is not a provider this app knows how to use. "
            f"Choose one of: {', '.join(PROVIDER_NAMES)}."
        )

    headers = {"Content-Type": "application/json", **provider.auth_header(api_key)}
    body = provider.payload(sender, to, subject, text_body, html_body)

    try:
        async with httpx.AsyncClient(timeout=API_TIMEOUT_SECONDS) as client:
            response = await client.post(provider.url, headers=headers, json=body)
    except httpx.TimeoutException as exc:
        raise MailApiError(
            f"{provider.label} did not answer within {API_TIMEOUT_SECONDS}s."
        ) from exc
    except httpx.HTTPError as exc:
        raise MailApiError(f"Could not reach {provider.label}: {exc}") from exc

    if response.status_code >= 400:
        raise MailApiError(
            f"{provider.label} refused the message ({response.status_code}): "
            f"{_provider_reason(response)}"
        )


def _provider_reason(response: httpx.Response) -> str:
    """The provider's own explanation, however it chose to word it."""
    try:
        body = response.json()
    except ValueError:
        return response.text[:300] or "no explanation given"

    if isinstance(body, dict):
        for field in ("message", "Message", "error", "detail"):
            value = body.get(field)
            if isinstance(value, str) and value:
                return value
        errors = body.get("errors")
        if isinstance(errors, list) and errors and isinstance(errors[0], dict):
            message = errors[0].get("message")
            if isinstance(message, str):
                return message
    return str(body)[:300]
