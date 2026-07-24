"""Business logic for reading and editing the per-company role permission matrix."""

from __future__ import annotations

from fastapi import HTTPException, status

from app.core.base_service import TenantScopedService
from app.core.permissions import (
    DEFAULT_ROLE_PERMISSIONS,
    PERMISSION_CATALOG,
    PERMISSION_KEYS,
    PERMISSIONS_MANAGE,
    expand,
)
from app.core.security import CurrentUser, effective_permissions
from app.features.rbac.models import CompanyRolePermission
from app.features.rbac.repository import RbacRepository
from app.features.rbac.schemas import (
    MyPermissionsResponse,
    PermissionCatalogItem,
    RolePermissionsResponse,
)

_LOCKED_ROLE = "owner"


class RbacService(TenantScopedService[CompanyRolePermission]):
    """Reads/edits the tenant's role permission matrix with lockout safeguards."""

    repository_class = RbacRepository

    async def get_matrix(self) -> RolePermissionsResponse:
        """Return the catalog, the company's current matrix, and the defaults."""
        roles = await self._current_role_map()
        catalog = [PermissionCatalogItem(**item) for item in PERMISSION_CATALOG]
        return RolePermissionsResponse(
            catalog=catalog,
            roles=roles,
            defaults=DEFAULT_ROLE_PERMISSIONS,
        )

    async def update_role(self, role: str, permissions: list[str]) -> None:
        """Replace one role's permission list, enforcing the safeguards."""
        self._require_known_role(role)
        if role == _LOCKED_ROLE:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Owner permissions are locked and cannot be edited",
            )
        self._require_known_keys(permissions)

        proposed = await self._current_role_map()
        proposed[role] = permissions
        self._require_permissions_manager_remains(proposed)

        await self.repository.set_role(self._require_tenant_id(), role, permissions)

    async def reset(self, role: str | None = None) -> None:
        """Reset one role (or all roles when role is None) to their defaults."""
        targets = [role] if role is not None else list(DEFAULT_ROLE_PERMISSIONS)
        company_id = self._require_tenant_id()
        for target in targets:
            self._require_known_role(target)
            await self.repository.set_role(
                company_id, target, list(DEFAULT_ROLE_PERMISSIONS[target])
            )

    async def my_permissions(self, current_user: CurrentUser) -> MyPermissionsResponse:
        """Return the caller's effective permission keys, sorted."""
        granted = await effective_permissions(current_user, self.db)
        return MyPermissionsResponse(permissions=sorted(granted))

    async def _current_role_map(self) -> dict[str, list[str]]:
        """Stored matrix merged over defaults so every role is present."""
        stored = await self.repository.get_map()
        return {
            role: stored.get(role, list(DEFAULT_ROLE_PERMISSIONS[role]))
            for role in DEFAULT_ROLE_PERMISSIONS
        }

    @staticmethod
    def _require_known_role(role: str) -> None:
        if role not in DEFAULT_ROLE_PERMISSIONS:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Unknown role: {role}",
            )

    @staticmethod
    def _require_known_keys(permissions: list[str]) -> None:
        unknown = sorted(set(permissions) - PERMISSION_KEYS)
        if unknown:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Unknown permission keys: {unknown}",
            )

    @staticmethod
    def _require_permissions_manager_remains(role_map: dict[str, list[str]]) -> None:
        """Reject a change that would leave no role able to edit permissions."""
        has_manager = any(PERMISSIONS_MANAGE in expand(keys) for keys in role_map.values())
        if not has_manager:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(f"At least one role must retain the '{PERMISSIONS_MANAGE}' permission"),
            )
