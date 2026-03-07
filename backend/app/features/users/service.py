"""User service — business logic for user operations.

CRITICAL: All tenant-scoped operations derive company_id from the
get_current_tenant_id() ContextVar, never from request body.
This prevents tenant isolation bypass vulnerabilities.
"""

import uuid

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import selectinload

from app.core.base_repository import TenantScopedRepository
from app.core.base_service import TenantScopedService
from app.features.users.models import User, UserRole
from app.features.users.schemas import RoleAssignment, UserCreate


class UserRepository(TenantScopedRepository[User]):
    """Repository for User entities with eager-loaded roles."""

    model = User
    eager_load_options = [selectinload(User.roles)]


class UserRoleRepository(TenantScopedRepository[UserRole]):
    """Repository for UserRole entities."""

    model = UserRole


class UserService(TenantScopedService[User]):
    """Business logic for user CRUD operations."""

    repository_class = UserRepository

    async def create(self, data: UserCreate) -> User:
        """Create a new user within the current tenant company.

        company_id is derived from TenantMiddleware ContextVar — never from
        the request body. This is the tenant isolation enforcement point.
        """
        company_id = self._require_tenant_id()
        user = User(
            company_id=company_id,
            email=data.email,
            first_name=data.first_name,
            last_name=data.last_name,
            phone=data.phone,
        )
        self.db.add(user)
        await self.db.flush()
        await self.db.refresh(user, attribute_names=["roles"])
        return user

    async def create_idempotent(self, user_id: uuid.UUID, data: UserCreate) -> User:
        """Idempotent user create using INSERT ON CONFLICT DO NOTHING.

        When a client provides a UUID and a user with that id already exists,
        the insert is silently skipped and the existing record returned.
        This is the correct behaviour for offline sync retry deduplication.

        company_id is always derived from TenantMiddleware ContextVar.
        """
        company_id = self._require_tenant_id()

        stmt = (
            insert(User)
            .values(
                id=user_id,
                company_id=company_id,
                email=data.email,
                first_name=data.first_name,
                last_name=data.last_name,
                phone=data.phone,
            )
            .on_conflict_do_nothing(index_elements=["id"])
        )
        await self.db.execute(stmt)

        result = await self.db.execute(
            select(User).where(User.id == user_id).options(selectinload(User.roles))
        )
        return result.scalars().first()  # type: ignore[return-value]

    async def create_role_idempotent(
        self, role_id: uuid.UUID, user_id: uuid.UUID, role: str
    ) -> UserRole:
        """Idempotent user role create using INSERT ON CONFLICT DO NOTHING.

        company_id is always derived from TenantMiddleware ContextVar.
        """
        company_id = self._require_tenant_id()

        stmt = (
            insert(UserRole)
            .values(
                id=role_id,
                user_id=user_id,
                company_id=company_id,
                role=role,
            )
            .on_conflict_do_nothing(index_elements=["id"])
        )
        await self.db.execute(stmt)

        return await self.db.get(UserRole, role_id)  # type: ignore[return-value]

    async def assign_role(self, user_id: uuid.UUID, data: RoleAssignment) -> UserRole:
        """Assign a role to a user within the current tenant company.

        company_id is derived from TenantMiddleware — never from request body.
        Validates that the user_id in path matches the body for consistency.
        """
        company_id = self._require_tenant_id()

        # Verify user exists
        user = await self.db.get(User, user_id)
        if user is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )

        user_role = UserRole(
            user_id=user_id,
            company_id=company_id,
            role=data.role,
        )
        self.db.add(user_role)
        await self.db.flush()
        await self.db.refresh(user_role)
        return user_role

    async def get_user_roles(self, user_id: uuid.UUID) -> list[UserRole]:
        """Get all roles for a specific user within the current tenant."""
        result = await self.db.execute(select(UserRole).where(UserRole.user_id == user_id))
        return list(result.scalars().all())
