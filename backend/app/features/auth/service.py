"""Auth service — registration, login, token refresh, logout business logic."""

import logging
import secrets
import uuid
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import select, text, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.core.email import EmailService
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
from app.features.auth.models import PasswordResetToken, RefreshToken
from app.features.companies.models import Company
from app.features.projects.repository import TradeCatalogRepository
from app.features.rbac.repository import RbacRepository
from app.features.users.models import User, UserRole

logger = logging.getLogger(__name__)

RESET_TOKEN_EXPIRE_HOURS = 1


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

        # Seed the editable role -> permission matrix from code-defined defaults.
        await RbacRepository(self.db).seed_defaults(company_id)

        # Seed the standard construction trades so the catalog isn't empty.
        await TradeCatalogRepository(self.db).seed_defaults(company_id)

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

        # Human-readable identity for the UI (avoids showing raw UUIDs).
        company = (
            (await self.db.execute(select(Company).where(Company.id == user.company_id)))
            .scalars()
            .first()
        )
        company_name = company.name if company else None
        display_name = f"{user.first_name or ''} {user.last_name or ''}".strip() or user.email

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
            "email": user.email,
            "display_name": display_name,
            "company_name": company_name,
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
            # EXCEPTION to CLAUDE.md "no commit in services" rule:
            # Family revocation MUST persist even though we raise an error afterward.
            # Using flush() would be rolled back by get_db's exception handler,
            # leaving the stolen token family active (OWASP token reuse vulnerability).
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

    async def change_password(
        self, user_id: UUID, current_password: str, new_password: str
    ) -> None:
        """Change the signed-in user's password after verifying the current one.

        Raises ValueError if the current password is wrong (or the account has no
        password set) or the new password matches the old. The active session is
        left intact — its tokens live in httpOnly cookies and stay valid.
        """
        result = await self.db.execute(select(User).where(User.id == user_id))
        user = result.scalars().first()
        if user is None or user.password_hash is None:
            raise ValueError("Current password is incorrect")
        if not verify_password(current_password, user.password_hash):
            raise ValueError("Current password is incorrect")
        if verify_password(new_password, user.password_hash):
            raise ValueError("New password must be different from the current one")

        user.password_hash = hash_password(new_password)
        await self.db.flush()

    async def request_password_reset(self, email: str) -> None:
        """Email a password-reset link if the address belongs to a user.

        Always returns without indicating whether the email exists, so the
        endpoint can respond identically either way (no account enumeration).
        """
        result = await self.db.execute(select(User).where(User.email == email))
        user = result.scalars().first()
        if user is None:
            return

        token = secrets.token_urlsafe(32)
        self.db.add(
            PasswordResetToken(
                user_id=user.id,
                token_hash=hash_refresh_token(token),
                expires_at=datetime.now(UTC) + timedelta(hours=RESET_TOKEN_EXPIRE_HOURS),
            )
        )
        await self.db.flush()

        reset_url = f"{settings.public_web_url}/reset-password?token={token}"
        try:
            await EmailService().send_password_reset(to=user.email, reset_url=reset_url)
        except Exception:
            # Delivery failure must neither leak account existence nor 500.
            logger.exception("Failed to send password-reset email to %s", user.email)

    async def reset_password(self, token: str, new_password: str) -> None:
        """Consume a reset token and set the user's new password.

        Raises ValueError if the token is unknown, already used, or expired.
        """
        token_hash = hash_refresh_token(token)
        result = await self.db.execute(
            select(PasswordResetToken).where(PasswordResetToken.token_hash == token_hash)
        )
        reset = result.scalars().first()
        now = datetime.now(UTC)
        if reset is None or reset.used_at is not None or reset.expires_at <= now:
            raise ValueError("This reset link is invalid or has expired")

        user = await self.db.get(User, reset.user_id)
        if user is None:
            raise ValueError("This reset link is invalid or has expired")

        # The request is unauthenticated, so establish the user's tenant context
        # for the RLS-guarded UPDATE on users (mirrors registration).
        set_current_tenant_id(user.company_id)
        conn = await self.db.connection()
        await conn.execute(text(f"SET LOCAL app.current_company_id = '{user.company_id}'"))

        user.password_hash = hash_password(new_password)
        reset.used_at = now
        # Burn any other outstanding reset tokens for this user.
        await self.db.execute(
            update(PasswordResetToken)
            .where(
                PasswordResetToken.user_id == user.id,
                PasswordResetToken.used_at.is_(None),
            )
            .values(used_at=now)
        )
        await self.db.flush()
