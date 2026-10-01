"""Guards on the container entrypoint.

start.sh only runs on a deployed instance, so nothing else in the suite covers
it — and the settings in it are the kind whose absence shows up as a production
bug rather than a failing test. Trailing-slash redirects on every list endpoint
came back as http:// because the app was not reading X-Forwarded-Proto, and a
https -> http hop is cross-origin, where fetch drops Authorization. Every list
endpoint answered 401 while endpoints registered without a trailing slash kept
working.
"""

import pathlib

_START_SH = pathlib.Path(__file__).resolve().parent.parent / "start.sh"


def _start_script() -> str:
    return _START_SH.read_text()


def test_uvicorn_reads_forwarded_proto() -> None:
    """Without this the app builds http:// URLs behind a TLS terminator."""
    assert "--proxy-headers" in _start_script()


def test_forwarded_headers_are_trusted_from_the_platform_router() -> None:
    """--proxy-headers is inert without this: uvicorn trusts only 127.0.0.1 by
    default, and the platform router connects from an internal address."""
    assert "--forwarded-allow-ips" in _start_script()


def test_migrations_run_before_the_server_starts() -> None:
    script = _start_script()
    assert script.index("alembic upgrade head") < script.index("exec uvicorn")
