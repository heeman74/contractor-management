"""Database URL normalisation.

Managed platforms (Render, Heroku, Fly) inject a DATABASE_URL spelled
``postgres://`` or ``postgresql://``. SQLAlchemy picks its driver from that
prefix, so either one loads the synchronous psycopg2 driver, which this
project does not install — the app and Alembic both die at startup with
``ModuleNotFoundError: psycopg2``. Rewriting the prefix keeps the platform's
injected credentials intact while selecting the async driver we do use.
"""

from __future__ import annotations

ASYNC_PREFIX = "postgresql+asyncpg://"
_SYNC_PREFIXES = ("postgresql://", "postgres://")


def normalize_async_dsn(url: str) -> str:
    """Return ``url`` with an explicit asyncpg driver.

    URLs that already name a driver (``postgresql+asyncpg://``, and any other
    ``postgresql+...``) are returned untouched.
    """
    if not isinstance(url, str) or "+" in url.split("://", 1)[0]:
        return url
    for prefix in _SYNC_PREFIXES:
        if url.startswith(prefix):
            return ASYNC_PREFIX + url[len(prefix) :]
    return url
