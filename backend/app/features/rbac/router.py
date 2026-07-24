"""REST endpoints for the role-permission editor and effective-permission lookup.

  GET  /api/v1/roles/permissions              — read the company's role matrix (owner/admin)
  PUT  /api/v1/roles/{role}/permissions       — replace one role's permission keys (owner/admin)
  POST /api/v1/roles/permissions/reset        — reset one/all roles to defaults (owner/admin)
  GET  /api/v1/me/permissions                 — the caller's effective permission keys

Editor endpoints are gated by the roles.permissions.manage permission; /me/permissions
requires only authentication. Router functions are thin — logic lives in RbacService.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user, require_permission
from app.features.rbac.schemas import (
    MyPermissionsResponse,
    ResetRequest,
    RolePermissionsResponse,
    RolePermissionsUpdate,
)
from app.features.rbac.service import RbacService

router = APIRouter(tags=["rbac"])

_manage_permissions = Depends(require_permission("roles.permissions.manage"))


@router.get("/roles/permissions", response_model=RolePermissionsResponse)
async def get_role_permissions(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[None, _manage_permissions],
) -> RolePermissionsResponse:
    """Return the catalog, the company's matrix, and the defaults."""
    return await RbacService(db).get_matrix()


@router.put("/roles/{role}/permissions", response_model=RolePermissionsResponse)
async def update_role_permissions(
    role: str,
    body: RolePermissionsUpdate,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[None, _manage_permissions],
) -> RolePermissionsResponse:
    """Replace one role's permission keys, then return the refreshed matrix."""
    service = RbacService(db)
    await service.update_role(role, body.permissions)
    return await service.get_matrix()


@router.post("/roles/permissions/reset", response_model=RolePermissionsResponse)
async def reset_role_permissions(
    body: ResetRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[None, _manage_permissions],
) -> RolePermissionsResponse:
    """Reset one role (or all roles) to defaults, then return the refreshed matrix."""
    service = RbacService(db)
    await service.reset(body.role)
    return await service.get_matrix()


@router.get("/me/permissions", response_model=MyPermissionsResponse)
async def get_my_permissions(
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> MyPermissionsResponse:
    """Return the current user's effective permission keys."""
    return await RbacService(db).my_permissions(current_user)
