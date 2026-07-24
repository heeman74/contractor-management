"""Short-lived capability tokens for public (login-free) contract access.

The token is the capability: whoever holds it may view + sign that one contract via
the public /sign page. Signed with the app's JWT secret, scoped to a contract, and
carries the company_id so the (RLS-forced) contract can be resolved without a login.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from jose import JWTError, jwt

from app.core.config import settings

_ALGORITHM = "HS256"
_TOKEN_TYPE = "contract_access"
_TTL_HOURS = 72


def make_contract_token(
    contract_id: uuid.UUID, client_user_id: uuid.UUID | None, company_id: uuid.UUID
) -> str:
    """Mint a 72-hour contract-access token."""
    now = datetime.now(UTC)
    payload = {
        "contract_id": str(contract_id),
        "client_user_id": str(client_user_id) if client_user_id else None,
        "company_id": str(company_id),
        "type": _TOKEN_TYPE,
        "iat": now,
        "exp": now + timedelta(hours=_TTL_HOURS),
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=_ALGORITHM)


def parse_contract_token(token: str) -> dict[str, Any] | None:
    """Return the token payload if valid + correct type, else None."""
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[_ALGORITHM])
    except JWTError:
        return None
    if payload.get("type") != _TOKEN_TYPE:
        return None
    return payload
