"""JWT security utilities.

Phase 1 stub: decodes a simple JWT or returns a hardcoded payload.
Real authentication (password hashing, token issuance, refresh rotation)
is implemented in Phase 6 (Auth).
"""

from typing import Any

from jose import JWTError, jwt

# Phase 1 test secret — replace with env var in Phase 6
_TEST_SECRET = "phase1-test-secret-replace-in-v2"
_ALGORITHM = "HS256"


def decode_token(token: str) -> dict[str, Any] | None:
    """Decode a JWT and return its payload.

    Returns None if the token is invalid or expired.
    Phase 1: used only in tests; real auth middleware in Phase 6.
    """
    try:
        payload = jwt.decode(token, _TEST_SECRET, algorithms=[_ALGORITHM])
        return payload
    except JWTError:
        return None


def create_test_token(payload: dict[str, Any]) -> str:
    """Create a test JWT. For use in tests only — not for production."""
    return jwt.encode(payload, _TEST_SECRET, algorithm=_ALGORITHM)
