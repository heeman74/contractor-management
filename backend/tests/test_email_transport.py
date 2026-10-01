"""Unit tests for the IPv4-only SMTP transport.

Guards the fix for Render's missing IPv6 route: the SMTP client must connect
over IPv4 so a server's IPv6 address can't trip "[Errno 101] Network is
unreachable" before IPv4 is tried.
"""

import socket
from unittest.mock import MagicMock, patch

from app.core.email import _IPv4SMTP


def _bare_client() -> _IPv4SMTP:
    # Build without __init__ so constructing the object doesn't open a connection.
    client = _IPv4SMTP.__new__(_IPv4SMTP)
    client.source_address = None
    return client


def test_get_socket_requests_ipv4_only():
    fake_sock = MagicMock()
    with (
        patch("app.core.email.socket.getaddrinfo") as getaddrinfo,
        patch("app.core.email.socket.create_connection", return_value=fake_sock) as connect,
    ):
        getaddrinfo.return_value = [
            (socket.AF_INET, socket.SOCK_STREAM, 6, "", ("142.250.1.1", 587))
        ]
        result = _bare_client()._get_socket("smtp.gmail.com", 587, 15)

    assert result is fake_sock
    assert socket.AF_INET in getaddrinfo.call_args.args
    connect.assert_called_once_with(("142.250.1.1", 587), 15, None)


def test_get_socket_falls_through_to_next_ipv4_address():
    good_sock = MagicMock()
    with (
        patch("app.core.email.socket.getaddrinfo") as getaddrinfo,
        patch(
            "app.core.email.socket.create_connection",
            side_effect=[OSError("unreachable"), good_sock],
        ) as connect,
    ):
        getaddrinfo.return_value = [
            (socket.AF_INET, socket.SOCK_STREAM, 6, "", ("1.1.1.1", 587)),
            (socket.AF_INET, socket.SOCK_STREAM, 6, "", ("2.2.2.2", 587)),
        ]
        result = _bare_client()._get_socket("smtp.gmail.com", 587, 15)

    assert result is good_sock
    assert connect.call_count == 2
