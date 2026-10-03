"""A mail failure has to say which failure it was.

"TimeoutError: timed out" names neither the host nor what was attempted, so a
blocked port, a wrong port and a wrong password all look the same on screen —
and the deployed instance reported exactly that, leaving nothing to act on.

These use real sockets: the thing under test is how a connection fails, which a
mock would simply assert into existence.
"""

from __future__ import annotations

import socket

import pytest

from app.core.email import (
    IMPLICIT_TLS_PORT,
    SMTP_TIMEOUT_SECONDS,
    EmailService,
    MailSender,
    MailTransport,
    MailTransportError,
    _IPv4SMTP,
    _IPv4SMTPS,
)

# conftest stubs _send_smtp for every test so nothing leaves the process. The
# two tests below are about what that method does, so they need the real one —
# captured here at import, which happens before any fixture replaces it.
_REAL_SEND_SMTP = EmailService._send_smtp


def _transport(host: str, port: int) -> MailTransport:
    return MailTransport(host=host, port=port, use_tls=True, user="u", password="p")


def _free_port() -> int:
    """A port with nothing on it, so a connection is refused rather than hang."""
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def test_a_refused_connection_says_nothing_is_listening() -> None:
    with pytest.raises(MailTransportError) as exc:
        EmailService._connect(_transport("127.0.0.1", _free_port()))

    message = str(exc.value)
    assert "refused the connection" in message
    assert "nothing is listening" in message
    assert "127.0.0.1" in message, "the error must name where it tried"


def test_an_unresolvable_host_names_the_host() -> None:
    with pytest.raises(MailTransportError) as exc:
        EmailService._connect(_transport("smtp.invalid.example", 587))

    assert "smtp.invalid.example:587" in str(exc.value)


def test_a_silent_drop_is_reported_as_a_block_rather_than_a_password_problem(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The deployed symptom: packets discarded, so the server never answers."""

    def _hang(*_args, **_kwargs):
        raise TimeoutError("timed out")

    monkeypatch.setattr(_IPv4SMTP, "__init__", _hang)

    with pytest.raises(MailTransportError) as exc:
        EmailService._connect(_transport("smtp.gmail.com", 587))

    message = str(exc.value)
    assert "smtp.gmail.com:587" in message
    assert "blocked" in message, "a drop is a network symptom, not a credential one"
    assert "465" in message, "it should name the alternative worth trying"
    assert "blocked" in message
    assert str(SMTP_TIMEOUT_SECONDS) in message


def test_port_465_uses_implicit_tls(monkeypatch: pytest.MonkeyPatch) -> None:
    """465 is encrypted from the first byte; STARTTLS on top of it is an error."""
    chosen: list[type] = []

    class _Stub:
        def __init__(self, host, port, timeout):
            chosen.append(type(self))

    monkeypatch.setattr(_IPv4SMTPS, "__init__", _Stub.__init__)
    monkeypatch.setattr(_IPv4SMTP, "__init__", _Stub.__init__)

    EmailService._connect(_transport("smtp.example.com", IMPLICIT_TLS_PORT))
    assert chosen == [_IPv4SMTPS]

    chosen.clear()
    EmailService._connect(_transport("smtp.example.com", 587))
    assert chosen == [_IPv4SMTP]


def test_starttls_is_not_attempted_on_an_implicitly_encrypted_port(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[str] = []

    class _Server:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def starttls(self):
            calls.append("starttls")

        def login(self, _user, _password):
            calls.append("login")

        def send_message(self, _message):
            calls.append("send")

    monkeypatch.setattr(EmailService, "_connect", staticmethod(lambda _t: _Server()))
    service = EmailService(
        MailSender(
            from_header="A <a@b.com>",
            reply_to=None,
            transport=_transport("smtp.example.com", IMPLICIT_TLS_PORT),
            label="company-smtp",
        )
    )

    _REAL_SEND_SMTP(service, "to@example.com", "subject", "text", "<p>html</p>")

    assert calls == ["login", "send"], calls


def test_starttls_is_still_used_on_587(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[str] = []

    class _Server:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def starttls(self):
            calls.append("starttls")

        def login(self, _user, _password):
            calls.append("login")

        def send_message(self, _message):
            calls.append("send")

    monkeypatch.setattr(EmailService, "_connect", staticmethod(lambda _t: _Server()))
    service = EmailService(
        MailSender(
            from_header="A <a@b.com>",
            reply_to=None,
            transport=_transport("smtp.example.com", 587),
            label="company-smtp",
        )
    )

    _REAL_SEND_SMTP(service, "to@example.com", "subject", "text", "<p>html</p>")

    assert calls == ["starttls", "login", "send"], calls


def test_a_timeout_on_465_does_not_suggest_465(monkeypatch: pytest.MonkeyPatch) -> None:
    """Advising the port someone just tried reads as advice already taken."""

    def _hang(*_args, **_kwargs):
        raise TimeoutError("timed out")

    monkeypatch.setattr(_IPv4SMTPS, "__init__", _hang)

    with pytest.raises(MailTransportError) as exc:
        EmailService._connect(_transport("smtp.gmail.com", IMPLICIT_TLS_PORT))

    message = str(exc.value)
    assert "Port 465 is worth trying" not in message
    assert "only a provider that sends over HTTPS will work" in message


# ---------------------------------------------------------------------------
# What actually goes on the wire
#
# A message with no Date and no Message-ID is accepted at the SMTP handshake and
# then discarded: it arrived in no folder at all, not even spam. Date is required
# by RFC 5322, and the absence of a Message-ID is one of the oldest signals of
# mail no real client wrote. Python adds neither and smtplib does not add them on
# the way out, so they have to be set here.
# ---------------------------------------------------------------------------


class _CapturingServer:
    """Stands in for the SMTP server, keeping what it was handed."""

    def __init__(self) -> None:
        self.message = None

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def starttls(self) -> None:
        pass

    def login(self, _user, _password) -> None:
        pass

    def send_message(self, message):
        self.message = message
        return {}


def _sent_message(monkeypatch: pytest.MonkeyPatch, from_header: str):
    server = _CapturingServer()
    monkeypatch.setattr(EmailService, "_connect", staticmethod(lambda _t: server))
    service = EmailService(
        MailSender(
            from_header=from_header,
            reply_to=None,
            transport=_transport("smtp.example.com", 587),
            label="company-smtp",
        )
    )
    _REAL_SEND_SMTP(service, "client@example.com", "Subject", "text", "<p>html</p>")
    return server.message


def test_every_message_carries_a_date(monkeypatch: pytest.MonkeyPatch) -> None:
    message = _sent_message(monkeypatch, "Acme <quotes@acme.com>")

    assert message["Date"], "RFC 5322 requires it; mail without it is discarded"


def test_every_message_carries_a_message_id(monkeypatch: pytest.MonkeyPatch) -> None:
    message = _sent_message(monkeypatch, "Acme <quotes@acme.com>")

    assert message["Message-ID"], "its absence is a decades-old spam signal"


def test_the_message_id_claims_the_senders_own_domain(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """An id whose domain does not match the sender reads as forged."""
    message = _sent_message(monkeypatch, "Acme <quotes@acme.com>")

    assert message["Message-ID"].endswith("@acme.com>"), message["Message-ID"]


def test_a_sender_without_a_domain_still_produces_a_message_id(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Malformed configuration must not stop mail going out entirely."""
    message = _sent_message(monkeypatch, "nonsense-without-an-at-sign")

    assert message["Message-ID"]


# ---------------------------------------------------------------------------
# The server's receipt
#
# A mail server that accepts a message answers with a queue id, and that id is
# the only handle anyone has on it afterwards. Discarding it leaves "accepted"
# as a claim with nothing behind it — which is what a message that is accepted
# and then dropped looks like from this end.
# ---------------------------------------------------------------------------


class _ReceiptServer(_CapturingServer):
    last_reply = (250, b"2.0.0 OK  1759456789 d9443c01a7336 - gsmtp")

    def send_message(self, message):
        self.message = message
        return {}


class _RefusingServer(_CapturingServer):
    def send_message(self, message):
        self.message = message
        return {"client@example.com": (550, b"5.1.1 No such user")}


def _service(monkeypatch: pytest.MonkeyPatch, server) -> EmailService:
    monkeypatch.setattr(EmailService, "_connect", staticmethod(lambda _t: server))
    return EmailService(
        MailSender(
            from_header="Acme <quotes@acme.com>",
            reply_to=None,
            transport=_transport("smtp.example.com", 587),
            label="company-smtp",
        )
    )


def test_the_servers_receipt_reaches_the_caller(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    service = _service(monkeypatch, _ReceiptServer())

    receipt = _REAL_SEND_SMTP(service, "client@example.com", "Subject", "text", "<p>html</p>")

    assert receipt is not None
    assert receipt.startswith("250")
    assert "gsmtp" in receipt, "the queue id is the part worth keeping"


def test_a_refused_recipient_is_not_reported_as_sent(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A refusal the caller never hears about is how "sent" starts meaning
    nothing."""
    service = _service(monkeypatch, _RefusingServer())

    with pytest.raises(MailTransportError) as exc:
        _REAL_SEND_SMTP(service, "client@example.com", "Subject", "text", "<p>html</p>")

    assert "refused the recipient" in str(exc.value)


def test_a_server_that_says_nothing_is_not_an_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Not every server records a reply; that is not a failure to send."""
    service = _service(monkeypatch, _CapturingServer())

    receipt = _REAL_SEND_SMTP(service, "client@example.com", "Subject", "text", "<p>html</p>")

    assert receipt is None
