"""Auth service — registration, login, token refresh, logout business logic."""

import uuid
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import select, text, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.security import (
    REFRESH_TOKEN_EXPIRE_DAYS,
    create_access_token,
    create_refresh_token_jwt,
    decode_token,
    hash_password,
    hash_refresh_token,
    verify_password,
)
from app.core.tenant import set_current_tenant_id
from app.features.auth.models import RefreshToken
from app.features.companies.models import Company
from app.features.users.models import User, UserRole


class AuthService:
    """Authentication service — handles register, login, token refresh, logout.

    Does not inherit from BaseService because auth flows are unique and
    do not follow standard CRUD patterns.
    """

    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def register(
        self,
        email: str,
        password: str,
        company_name: str,
        first_name: str | None = None,
        last_name: str | None = None,
    ) -> dict:
        """Register a new company + admin user atomically.

        Returns dict with access_token, refresh_token, user_id, company_id, roles.
        Raises ValueError if email already exists.
        """
        # Check email uniqueness (global — not tenant-scoped for registration)
        existing = await self.db.execute(select(User).where(User.email == email))
        if existing.scalars().first() is not None:
            raise ValueError("Email already registered")

        # Create company
        company_id = uuid.uuid4()
        company = Company(id=company_id, name=company_name)
        self.db.add(company)
        await self.db.flush()

        # Set tenant context so RLS allows inserts into users/user_roles
        set_current_tenant_id(company_id)
        conn = await self.db.connection()
        await conn.execute(
            text(f"SET LOCAL app.current_company_id = '{company_id}'"),
        )

        # Create user with hashed password
        user_id = uuid.uuid4()
        user = User(
            id=user_id,
            company_id=company_id,
            email=email,
            password_hash=hash_password(password),
            first_name=first_name,
            last_name=last_name,
        )
        self.db.add(user)
        await self.db.flush()

        # Assign admin role
        role = UserRole(
            id=uuid.uuid4(),
            user_id=user_id,
            company_id=company_id,
            role="admin",
        )
        self.db.add(role)
        await self.db.flush()

        # Generate tokens
        roles = ["admin"]
        access_token = create_access_token(user_id, company_id, roles)
        family_id = str(uuid.uuid4())
        refresh_token = create_refresh_token_jwt(user_id, company_id, family_id)

        # Store refresh token hash
        rt = RefreshToken(
            user_id=user_id,
            token_hash=hash_refresh_token(refresh_token),
            family_id=family_id,
            expires_at=datetime.now(UTC) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
        )
        self.db.add(rt)

        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "user_id": user_id,
            "company_id": company_id,
            "roles": roles,
        }

    async def login(self, email: str, password: str) -> dict:
        """Authenticate user with email + password.

        Returns token pair or raises ValueError on bad credentials.
        """
        # Query user with roles eagerly loaded (single query with JOIN)
        result = await self.db.execute(
            select(User).where(User.email == email).options(selectinload(User.roles))
        )
        user = result.scalars().first()

        if user is None or user.password_hash is None:
            raise ValueError("Invalid email or password")
        if not verify_password(password, user.password_hash):
            raise ValueError("Invalid email or password")

        roles = [
            r.role for r in user.roles if r.company_id == user.company_id and r.deleted_at is None
        ]

        # Generate tokens
        access_token = create_access_token(user.id, user.company_id, roles)
        family_id = str(uuid.uuid4())
        refresh_token = create_refresh_token_jwt(user.id, user.company_id, family_id)

        # Store refresh token hash
        rt = RefreshToken(
            user_id=user.id,
            token_hash=hash_refresh_token(refresh_token),
            family_id=family_id,
            expires_at=datetime.now(UTC) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
        )
        self.db.add(rt)

        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "user_id": user.id,
            "company_id": user.company_id,
            "roles": roles,
        }

    async def refresh_tokens(self, refresh_token_str: str) -> dict:
        """Rotate a refresh token: revoke old, issue new pair.

        Implements OWASP refresh token rotation with family revocation:
        - If token is valid and not revoked: rotate (revoke old, issue new).
        - If token is revoked (reuse detected): revoke entire family (theft).
        """
        # Decode the JWT
        payload = decode_token(refresh_token_str)
        if payload is None or payload.get("type") != "refresh":
            raise ValueError("Invalid refresh token")

        token_hash = hash_refresh_token(refresh_token_str)

        # Look up the stored token
        result = await self.db.execute(
            select(RefreshToken).where(RefreshToken.token_hash == token_hash)
        )
        stored_token = result.scalars().first()

        if stored_token is None:
            raise ValueError("Refresh token not found")

        # Reuse detection: if token is already revoked, revoke entire family
        if stored_token.revoked:
            await self.db.execute(
                update(RefreshToken)
                .where(RefreshToken.family_id == stored_token.family_id)
                .values(revoked=True)
            )
            # Commit family revocation BEFORE raising so rollback doesn't undo it
            await self.db.commit()
            raise ValueError("Token reuse detected — family revoked")

        # Check expiration
        if stored_token.expires_at < datetime.now(UTC):
            raise ValueError("Refresh token expired")

        # Revoke the current token
        stored_token.revoked = True

        # Issue new token pair in the same family
        user_id = UUID(payload["sub"])
        company_id = UUID(payload["company_id"])
        family_id = payload["family_id"]

        # Get current roles
        roles_result = await self.db.execute(
            select(UserRole.role).where(
                UserRole.user_id == user_id,
                UserRole.company_id == company_id,
                UserRole.deleted_at.is_(None),
            )
        )
        roles = list(roles_result.scalars().all())

        access_token = create_access_token(user_id, company_id, roles)
        new_refresh_token = create_refresh_token_jwt(user_id, company_id, family_id)

        # Store new refresh token hash
        new_rt = RefreshToken(
            user_id=user_id,
            token_hash=hash_refresh_token(new_refresh_token),
            family_id=family_id,
            expires_at=datetime.now(UTC) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
        )
        self.db.add(new_rt)

        return {
            "access_token": access_token,
            "refresh_token": new_refresh_token,
            "user_id": user_id,
            "company_id": company_id,
            "roles": roles,
        }

    async def logout(self, refresh_token_str: str) -> None:
        """Revoke a refresh token and its entire family."""
        token_hash = hash_refresh_token(refresh_token_str)

        result = await self.db.execute(
            select(RefreshToken).where(RefreshToken.token_hash == token_hash)
        )
        stored_token = result.scalars().first()

        if stored_token is not None:
            # Revoke entire family
            await self.db.execute(
                update(RefreshToken)
                .where(RefreshToken.family_id == stored_token.family_id)
                .values(revoked=True)
            )
