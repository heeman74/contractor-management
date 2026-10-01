"""Rate limiter configuration — shared across routers.

Keyed on the browser rather than the connecting socket. Every browser request
reaches this API through the web app, so keying on the connecting address made
one bucket for the whole world: `5/minute` on login was five logins a minute
across all users, and anyone testing collected 429s caused by somebody else.
"""

from slowapi import Limiter
from slowapi.util import get_remote_address
from starlette.requests import Request

# Set by the web app on requests it makes for a browser. Deliberately not
# X-Forwarded-For: the platform writes that on its own hop, and which entry of
# the resulting chain counts as the client varies by uvicorn version — a header
# nothing else writes has one unambiguous meaning.
CLIENT_IP_HEADER = "x-client-ip"


def client_identity(request: Request) -> str:
    """Who to count this request against.

    Falls back to the connecting address, which is right for a caller that
    reaches this API directly — the mobile app, or a browser in development.

    This is a throttling key, not an identity: this API is publicly reachable,
    so a caller that skips the web app can send whatever it likes here. What
    stands between an attacker and an account is password hashing and
    refresh-token reuse detection, not this header.
    """
    forwarded = request.headers.get(CLIENT_IP_HEADER)
    if forwarded:
        return forwarded.strip()
    return get_remote_address(request)


limiter = Limiter(key_func=client_identity)
