"""Users API router.

Phase 1: stub endpoints. Full CRUD with auth in later phases.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.features.users import service
from app.features.users.schemas import (
    UserCreate,
    UserResponse,
    UserRoleCreate,
    UserRoleResponse,
)

router = APIRouter(prefix="/users", tags=["users"])


@router.post("/", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    data: UserCreate,
    db: AsyncSession = Depends(get_db),
) -> UserResponse:
    """Create a new user. Phase 1: no auth required."""
    user = await service.create_user(db, data)
    return UserResponse.model_validate(user)


@router.get("/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
) -> UserResponse:
    """Retrieve a user by ID. Phase 1: no auth required."""
    user = await service.get_user(db, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )
    return UserResponse.model_validate(user)


@router.post("/roles", response_model=UserRoleResponse, status_code=status.HTTP_201_CREATED)
async def assign_role(
    data: UserRoleCreate,
    db: AsyncSession = Depends(get_db),
) -> UserRoleResponse:
    """Assign a role to a user. Phase 1: no auth required."""
    user_role = await service.assign_role(db, data)
    return UserRoleResponse.model_validate(user_role)
