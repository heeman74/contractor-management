"""User service — business logic for user operations.

Phase 1: stub implementations. Full logic in later phases.
"""

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.features.users.models import User, UserRole
from app.features.users.schemas import UserCreate, UserRoleCreate


async def create_user(db: AsyncSession, data: UserCreate) -> User:
    """Create a new user within a company."""
    user = User(
        company_id=data.company_id,
        email=data.email,
        first_name=data.first_name,
        last_name=data.last_name,
        phone=data.phone,
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)
    return user


async def get_user(db: AsyncSession, user_id: uuid.UUID) -> User | None:
    """Retrieve a user by ID."""
    return await db.get(User, user_id)


async def assign_role(db: AsyncSession, data: UserRoleCreate) -> UserRole:
    """Assign a role to a user within a company."""
    user_role = UserRole(
        user_id=data.user_id,
        company_id=data.company_id,
        role=data.role.value,
    )
    db.add(user_role)
    await db.flush()
    await db.refresh(user_role)
    return user_role
