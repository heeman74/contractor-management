"""Email transport.

Who the mail is from is a per-company question. A quote is from the contractor,
not from whoever operates the instance, and it cannot be made so by writing
their address into From: a provider only accepts a sender it has authenticated.
So there are two ways a company's mail can go out, and one fallback:

- **The company's own mailbox** (``smtp_*`` on the company). Mail genuinely
  originates from them and appears in their Sent folder. The stored password is
  ciphertext; see :mod:`app.core.secrets`.
- **The instance relay** (``settings.smtp_*``). The envelope stays the relay's,
  because that is what the provider authenticated, but the company is the
  display name and the Reply-To — so it reads as theirs and replies reach them.
- **Dev** (no SMTP anywhere) — logs the message and appends it to an in-memory
  outbox. Lets local development and tests exercise the full flow without a mail
  server.
"""

from __future__ import annotations

import asyncio
import logging
import smtplib
import socket
from dataclasses import dataclass
from email.message import EmailMessage
from email.utils import formataddr, parseaddr
from typing import TYPE_CHECKING

from app.core.config import settings
from app.core.secrets import decrypt_secret

if TYPE_CHECKING:
    from app.features.companies.models import Company

logger = logging.getLogger(__name__)

# Dev-mode outbox: every message "sent" without SMTP lands here. Tests read and
# clear it; it is never populated when a real SMTP host is configured.
sent_emails: list[dict[str, str]] = []

_DEFAULT_SMTP_PORT = 587


class _IPv4SMTP(smtplib.SMTP):
    """SMTP client that connects over IPv4 only.

    Some container hosts (notably Render) advertise an IPv6 address but have no
    route to the IPv6 internet. smtplib's default dual-stack connect then tries
    the server's IPv6 address and fails with "[Errno 101] Network is unreachable"
    before it ever falls back to IPv4. Pinning to IPv4 sidesteps that — every
    provider we target (Gmail included) publishes an IPv4 endpoint.
    """

    def _get_socket(self, host: str, port: int, timeout: float) -> socket.socket:
        last_exc: OSError | None = None
        for *_meta, sockaddr in socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM):
            try:
                return socket.create_connection(sockaddr, timeout, self.source_address)
            except OSError as exc:
                last_exc = exc
        raise last_exc or OSError(f"No IPv4 address found for {host}")


class _IPv4SMTPS(smtplib.SMTP_SSL, _IPv4SMTP):
    """Implicit-TLS SMTP, also pinned to IPv4.

    Port 465 speaks TLS from the first byte rather than upgrading with STARTTLS.
    Worth supporting because a network that silently drops 587 sometimes leaves
    465 alone, and the only alternative is telling someone their mail cannot be
    sent from here. SMTP_SSL builds its socket through super(), so the IPv4
    resolution above is what it gets.
    """


class MailTransportError(RuntimeError):
    """A mail server could not be reached, with the reason a person can act on.

    "TimeoutError: timed out" names neither the host nor what was being
    attempted, so it cannot distinguish a blocked port from a wrong password.
    """


# Implicit TLS rather than STARTTLS, by long-standing convention.
IMPLICIT_TLS_PORT = 465

# A cold free instance plus DNS, TCP and a TLS handshake does not always fit in
# fifteen seconds, and a timeout that is really just slowness reads as a block.
SMTP_TIMEOUT_SECONDS = 30


# Named in logs so a send that reached nobody is distinguishable from one that
# left the building. The three are otherwise identical from the outside.
TRANSPORT_COMPANY = "company-smtp"
TRANSPORT_RELAY = "relay"
TRANSPORT_DEV = "dev-outbox"


@dataclass(frozen=True)
class MailTransport:
    """The server a message is handed to."""

    host: str
    port: int
    use_tls: bool
    user: str | None
    password: str | None


@dataclass(frozen=True)
class MailSender:
    """How one message is addressed, and what carries it.

    ``transport`` of None means there is no mail server configured at all, so the
    message goes to the dev outbox and reaches nobody.
    """

    from_header: str
    reply_to: str | None
    transport: MailTransport | None
    label: str

    @property
    def delivers(self) -> bool:
        """False when sending would succeed without the message going anywhere."""
        return self.transport is not None


def _instance_sender() -> MailSender:
    """The operator's own sender — used for mail that is from the app itself."""
    if not settings.smtp_host:
        return MailSender(
            from_header=settings.smtp_from,
            reply_to=None,
            transport=None,
            label=TRANSPORT_DEV,
        )
    return MailSender(
        from_header=settings.smtp_from,
        reply_to=None,
        transport=MailTransport(
            host=settings.smtp_host,
            port=settings.smtp_port,
            use_tls=settings.smtp_use_tls,
            user=settings.smtp_user,
            password=settings.smtp_password,
        ),
        label=TRANSPORT_RELAY,
    )


def _company_sender(company: Company) -> MailSender:
    """How this company's mail should be addressed and carried.

    Prefers their own mailbox. Falling back to the relay keeps the company
    visible without claiming an envelope the provider would reject: the display
    name and Reply-To are theirs, the sender address stays the authenticated one.
    """
    display_name = company.email_from_name or company.name

    if company.smtp_host and company.smtp_user and company.smtp_password_encrypted:
        # Their address, since their server is now vouching for it.
        address = company.email_from_address or company.smtp_user
        return MailSender(
            from_header=formataddr((display_name, address)),
            reply_to=None,
            transport=MailTransport(
                host=company.smtp_host,
                port=company.smtp_port or _DEFAULT_SMTP_PORT,
                use_tls=company.smtp_use_tls,
                user=company.smtp_user,
                password=decrypt_secret(company.smtp_password_encrypted),
            ),
            label=TRANSPORT_COMPANY,
        )

    instance = _instance_sender()
    relay_address = _address_of(instance.from_header)
    return MailSender(
        from_header=formataddr((display_name, relay_address)),
        reply_to=company.email_from_address,
        transport=instance.transport,
        label=instance.label,
    )


def _address_of(from_header: str) -> str:
    """The bare address out of a possibly display-named From."""
    return parseaddr(from_header)[1]


class EmailService:
    """Sends transactional email as the app, or as one of its companies."""

    def __init__(self, sender: MailSender | None = None) -> None:
        self._sender = sender or _instance_sender()

    @classmethod
    def for_company(cls, company: Company) -> EmailService:
        """A service that sends as ``company`` rather than as the instance."""
        return cls(_company_sender(company))

    @property
    def transport_label(self) -> str:
        """Which of the three paths a send would take — worth logging."""
        return self._sender.label

    @property
    def delivers(self) -> bool:
        """False when a send would report success and reach nobody."""
        return self._sender.delivers

    @property
    def sender_header(self) -> str:
        """The From a recipient would see."""
        return self._sender.from_header

    @property
    def reply_to(self) -> str | None:
        """Where a reply would go, when that differs from the sender."""
        return self._sender.reply_to

    async def send(self, *, to: str, subject: str, text_body: str, html_body: str) -> None:
        """Send one message. Falls back to the dev outbox when no SMTP is set."""
        if self._sender.transport is not None:
            await asyncio.to_thread(self._send_smtp, to, subject, text_body, html_body)
            return

        sent_emails.append({"to": to, "subject": subject, "text": text_body, "html": html_body})
        if settings.debug:
            logger.info("Email (dev mode, not sent) to=%s subject=%s\n%s", to, subject, text_body)
        else:
            # Dev mode on a deployed instance is almost certainly unintended: the
            # caller is told the message was sent and nothing leaves the box. Say
            # so at a level that shows up, rather than filing it under info.
            logger.error(
                "Email NOT sent: no SMTP host is configured for this sender, so the "
                "message was discarded. to=%s subject=%s",
                to,
                subject,
            )

    def _send_smtp(self, to: str, subject: str, text_body: str, html_body: str) -> None:
        transport = self._sender.transport
        assert transport is not None  # send() only reaches here with one

        message = EmailMessage()
        message["From"] = self._sender.from_header
        message["To"] = to
        message["Subject"] = subject
        if self._sender.reply_to:
            message["Reply-To"] = self._sender.reply_to
        message.set_content(text_body)
        message.add_alternative(html_body, subtype="html")

        with self._connect(transport) as server:
            # 465 is already encrypted; STARTTLS on top of it is an error.
            if transport.use_tls and transport.port != IMPLICIT_TLS_PORT:
                server.starttls()
            if transport.user and transport.password:
                server.login(transport.user, transport.password)
            server.send_message(message)

    @staticmethod
    def _connect(transport: MailTransport) -> smtplib.SMTP:
        """Open the connection, reporting a failure in terms of what was tried.

        A refusal and a silent drop mean different things — the first says
        nothing is listening, the second usually says something between here and
        there is discarding the packets — and neither is a credential problem.
        Saying which happened is the difference between a fixable report and
        "timed out".
        """
        where = f"{transport.host}:{transport.port}"
        client = _IPv4SMTPS if transport.port == IMPLICIT_TLS_PORT else _IPv4SMTP
        try:
            return client(transport.host, transport.port, timeout=SMTP_TIMEOUT_SECONDS)
        except TimeoutError as exc:
            raise MailTransportError(
                f"No answer from {where} within {SMTP_TIMEOUT_SECONDS}s. The "
                "server never replied, which usually means outbound mail on "
                "this port is blocked between here and there rather than "
                "anything being wrong with the address or password. Port 465 is "
                "worth trying, or a provider that sends over HTTPS."
            ) from exc
        except ConnectionRefusedError as exc:
            raise MailTransportError(
                f"{where} refused the connection — nothing is listening there. "
                "Check the server address and port."
            ) from exc
        except OSError as exc:
            raise MailTransportError(f"Could not reach {where}: {exc}") from exc

    async def send_password_reset(self, *, to: str, reset_url: str) -> None:
        """Send the password-reset link email."""
        subject = "Reset your ContractorHub password"
        text_body = (
            "We received a request to reset your ContractorHub password.\n\n"
            f"Reset it here (the link expires in 1 hour):\n{reset_url}\n\n"
            "If you didn't request this, you can safely ignore this email."
        )
        html_body = (
            "<p>We received a request to reset your ContractorHub password.</p>"
            f'<p><a href="{reset_url}">Reset your password</a> '
            "(the link expires in 1 hour).</p>"
            "<p>If you didn't request this, you can safely ignore this email.</p>"
        )
        await self.send(to=to, subject=subject, text_body=text_body, html_body=html_body)

    async def send_quote_to_client(
        self,
        *,
        to: str,
        quote_number: str,
        company_name: str,
        total: str,
        quote_url: str,
        expiry_date: str | None,
    ) -> None:
        """Send a quote to the client it is addressed to."""
        subject = f"Quote {quote_number} from {company_name}"
        validity = (
            f"This quote is valid through {expiry_date}.\n\n" if expiry_date is not None else ""
        )
        text_body = (
            f"{company_name} has sent you quote {quote_number}.\n\n"
            f"Total: {total}\n\n"
            f"{validity}"
            f"Review and approve it here:\n{quote_url}\n"
        )
        html_validity = (
            f"<p>This quote is valid through {expiry_date}.</p>" if expiry_date is not None else ""
        )
        html_body = (
            f"<p>{company_name} has sent you quote {quote_number}.</p>"
            f"<p><strong>Total: {total}</strong></p>"
            f"{html_validity}"
            f'<p><a href="{quote_url}">Review and approve this quote</a></p>'
        )
        await self.send(to=to, subject=subject, text_body=text_body, html_body=html_body)
