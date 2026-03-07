"""JWT and password security utilities.

Provides bcrypt password hashing, JWT access/refresh token creation and
decoding, and the get_current_user FastAPI dependency for endpoint protection.
"""

import hashlib
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.tenant import set_current_tenant_id

# ---------------------------------------------------------------------------
# Password hashing
# ---------------------------------------------------------------------------
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    """Hash a plaintext password using bcrypt."""
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a plaintext password against a bcrypt hash."""
    return pwd_context.verify(plain_password, hashed_password)


# ---------------------------------------------------------------------------
# Refresh token hashing (stored as SHA-256 in DB)
# ---------------------------------------------------------------------------
def hash_refresh_token(token: str) -> str:
    """SHA-256 hash a refresh token for secure DB storage."""
    return hashlib.sha256(token.encode()).hexdigest()


# ---------------------------------------------------------------------------
# JWT token creation
# ---------------------------------------------------------------------------
_ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 15
REFRESH_TOKEN_EXPIRE_DAYS = 30


def create_access_token(
    user_id: UUID,
    company_id: UUID,
    roles: list[str],
) -> str:
    """Create a short-lived JWT access token (15 min)."""
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "company_id": str(company_id),
        "roles": roles,
        "type": "access",
        "iat": now,
        "exp": now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=_ALGORITHM)


def create_refresh_token_jwt(
    user_id: UUID,
    company_id: UUID,
    family_id: str,
) -> str:
    """Create a long-lived JWT refresh token (30 days)."""
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "company_id": str(company_id),
        "family_id": family_id,
        "type": "refresh",
        "jti": str(uuid4()),
        "iat": now,
        "exp": now + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=_ALGORITHM)


def decode_token(token: str) -> dict[str, Any] | None:
    """Decode a JWT and return its payload. Returns None if invalid/expired."""
    try:
        return jwt.decode(token, settings.jwt_secret_key, algorithms=[_ALGORITHM])
    except JWTError:
        return None


# ---------------------------------------------------------------------------
# FastAPI dependency: extract current user from Bearer token
# ---------------------------------------------------------------------------
_bearer_scheme = HTTPBearer(auto_error=False)


class CurrentUser:
    """Represents the authenticated user extracted from the JWT."""

    def __init__(self, user_id: UUID, company_id: UUID, roles: list[str]):
        self.user_id = user_id
        self.company_id = company_id
        self.roles = roles


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> CurrentUser:
    """FastAPI dependency that validates the Bearer token and returns the current user.

    Also sets the tenant context for RLS enforcement.
    """
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )

    payload = decode_token(credentials.credentials)
    if payload is None or payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        user_id = UUID(payload["sub"])
        company_id = UUID(payload["company_id"])
    except (KeyError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    # Set tenant context for RLS
    set_current_tenant_id(company_id)

    return CurrentUser(
        user_id=user_id,
        company_id=company_id,
        roles=payload.get("roles", []),
    )


def create_test_token(payload: dict[str, Any]) -> str:
    """Create a test JWT. For use in tests only."""
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=_ALGORITHM)
