"""Users API router.

Endpoints:
  POST   /api/v1/users/                  — create user (company_id from JWT)
  GET    /api/v1/users/                  — list users (RLS-filtered to tenant)
  POST   /api/v1/users/{user_id}/roles   — assign role to user
  GET    /api/v1/users/{user_id}/roles   — get user's roles

All endpoints require a valid JWT Bearer token. The tenant context (company_id)
is extracted from the JWT by the get_current_user dependency, replacing the
previous X-Company-Id header approach.
"""

import uuid

from fastapi import Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_router import CRUDRouter
from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user
from app.features.users.schemas import (
    RoleAssignment,
    UserCreate,
    UserResponse,
    UserRoleResponse,
)
from app.features.users.service import UserService


class UserRouter(CRUDRouter):
    """User CRUD router — create, list, plus role management endpoints."""

    prefix = "/users"
    tags = ["users"]
    service_class = UserService
    create_schema = UserCreate
    response_schema = UserResponse

    def _register_routes(self) -> None:
        """User uses create + list + custom role endpoints."""
        self._register_create()
        self._register_list()
        self._register_assign_role()
        self._register_get_roles()

    def _register_assign_role(self) -> None:
        svc_cls = self.service_class

        async def assign_role(
            user_id: uuid.UUID,
            data: RoleAssignment,
            db: AsyncSession = Depends(get_db),
            _current_user: CurrentUser = Depends(get_current_user),
        ) -> UserRoleResponse:
            svc = svc_cls(db)
            user_role = await svc.assign_role(user_id, data)
            return UserRoleResponse.model_validate(user_role)

        self.router.add_api_route(
            "/{user_id}/roles",
            assign_role,
            methods=["POST"],
            response_model=UserRoleResponse,
            status_code=status.HTTP_201_CREATED,
        )

    def _register_get_roles(self) -> None:
        svc_cls = self.service_class

        async def get_user_roles(
            user_id: uuid.UUID,
            db: AsyncSession = Depends(get_db),
            _current_user: CurrentUser = Depends(get_current_user),
        ) -> list[UserRoleResponse]:
            svc = svc_cls(db)
            roles = await svc.get_user_roles(user_id)
            return [UserRoleResponse.model_validate(r) for r in roles]

        self.router.add_api_route(
            "/{user_id}/roles",
            get_user_roles,
            methods=["GET"],
            response_model=list[UserRoleResponse],
        )


_user_router = UserRouter()
router = _user_router.router
