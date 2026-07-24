"""JWT and password security utilities.

Provides bcrypt password hashing, JWT access/refresh token creation and
decoding, and the get_current_user FastAPI dependency for endpoint protection.
"""

import hashlib
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

from fastapi import Cookie, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.permissions import DEFAULT_ROLE_PERMISSIONS, expand
from app.core.tenant import set_current_tenant_id, set_current_user_id

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
    access_token: str | None = Cookie(default=None),
    db: AsyncSession = Depends(get_db),
) -> CurrentUser:
    """FastAPI dependency that validates the Bearer token or access_token cookie.

    Auth source priority: Bearer header (mobile) > access_token cookie (web).
    Also sets the tenant context for RLS enforcement.
    """
    raw_token = (credentials.credentials if credentials else None) or access_token
    if raw_token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )

    payload = decode_token(raw_token)
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

    # Set tenant context for RLS (company-scoped)
    set_current_tenant_id(company_id)
    # Set user context for user-scoped RLS (device_tokens table)
    set_current_user_id(user_id)

    return CurrentUser(
        user_id=user_id,
        company_id=company_id,
        roles=payload.get("roles", []),
    )


def create_test_token(payload: dict[str, Any]) -> str:
    """Create a test JWT. For use in tests only."""
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=_ALGORITHM)


# ---------------------------------------------------------------------------
# Role capability groups
#
# These name the coarse privilege tiers and double as the source of the default
# permission matrix seeded per company (see app/core/permissions.py). "owner"
# implies "admin", so broadening require_admin here means no admin call site
# needs to add "owner" explicitly.
# ---------------------------------------------------------------------------
OWNER_ROLES: tuple[str, ...] = ("owner",)
ADMIN_ROLES: tuple[str, ...] = ("owner", "admin")
MANAGER_ROLES: tuple[str, ...] = ("owner", "admin", "project_manager")
GC_ROLES: tuple[str, ...] = ("owner", "admin", "gc")


def require_roles(
    current_user: CurrentUser,
    *allowed_roles: str,
    detail: str = "Insufficient role",
) -> None:
    """Raise 403 unless the current user has at least one of the allowed roles."""
    if not any(role in current_user.roles for role in allowed_roles):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detail)


def require_owner(current_user: CurrentUser) -> None:
    """Raise 403 unless the current user is a company owner."""
    require_roles(current_user, *OWNER_ROLES, detail="Owner role required")


def require_admin(current_user: CurrentUser) -> None:
    """Raise 403 unless the current user is an owner or admin."""
    require_roles(current_user, *ADMIN_ROLES, detail="Admin role required")


def require_manager(current_user: CurrentUser) -> None:
    """Raise 403 unless the current user can manage operations (owner/admin/PM)."""
    require_roles(current_user, *MANAGER_ROLES, detail="Manager role required")


def require_gc(current_user: CurrentUser) -> None:
    """Raise 403 unless the current user oversees construction (owner/admin/gc)."""
    require_roles(current_user, *GC_ROLES, detail="GC role required")


async def effective_permissions(current_user: CurrentUser, db: AsyncSession) -> set[str]:
    """Resolve the caller's effective permission keys (union across their roles).

    Reads the tenant's editable role -> permission matrix, falling back to the
    code-defined defaults for any role missing a stored row.
    """
    # Imported lazily: core must not import feature modules at load time.
    from app.features.rbac.repository import RbacRepository

    role_map = await RbacRepository(db).get_map()
    granted: set[str] = set()
    for role in current_user.roles:
        keys = role_map.get(role, DEFAULT_ROLE_PERMISSIONS.get(role, []))
        granted |= expand(keys)
    return granted


def require_permission(permission_key: str):
    """Build a dependency that 403s unless the caller's roles grant permission_key.

    Enforcement reads the per-company matrix, so an admin editing a role's
    permissions changes access immediately.
    """

    async def _dependency(
        current_user: CurrentUser = Depends(get_current_user),
        db: AsyncSession = Depends(get_db),
    ) -> None:
        granted = await effective_permissions(current_user, db)
        if permission_key not in granted:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Missing permission: {permission_key}",
            )

    return _dependency
