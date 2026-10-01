"""Email transport.

A single ``EmailService`` with two backends chosen by configuration:

- **SMTP** (when ``settings.smtp_host`` is set) — sends via stdlib ``smtplib`` in
  a worker thread so the async event loop is never blocked. No third-party
  dependency, so it works with any provider (Gmail, Mailgun, SES, …).
- **Dev** (default, no SMTP configured) — logs the message and appends it to an
  in-memory outbox instead of sending. Lets local development and tests exercise
  the full flow without a mail server.
"""

from __future__ import annotations

import asyncio
import logging
import smtplib
from email.message import EmailMessage

from app.core.config import settings

logger = logging.getLogger(__name__)

# Dev-mode outbox: every message "sent" without SMTP lands here. Tests read and
# clear it; it is never populated when a real SMTP host is configured.
sent_emails: list[dict[str, str]] = []


class EmailService:
    """Sends transactional email via SMTP, or logs it in dev mode."""

    async def send(self, *, to: str, subject: str, text_body: str, html_body: str) -> None:
        """Send one message. Falls back to the dev outbox when SMTP is unset."""
        if settings.smtp_host:
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
                "Email NOT sent: SMTP_HOST is unset, so this instance is in dev mode "
                "and the message was discarded. to=%s subject=%s",
                to,
                subject,
            )

    def _send_smtp(self, to: str, subject: str, text_body: str, html_body: str) -> None:
        message = EmailMessage()
        message["From"] = settings.smtp_from
        message["To"] = to
        message["Subject"] = subject
        message.set_content(text_body)
        message.add_alternative(html_body, subtype="html")

        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as server:
            if settings.smtp_use_tls:
                server.starttls()
            if settings.smtp_user and settings.smtp_password:
                server.login(settings.smtp_user, settings.smtp_password)
            server.send_message(message)

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
