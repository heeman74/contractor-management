"""Repository for the per-company role -> permission matrix."""

from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.core.base_repository import TenantScopedRepository
from app.core.permissions import DEFAULT_ROLE_PERMISSIONS
from app.features.rbac.models import CompanyRolePermission

_CONFLICT_COLUMNS = ["company_id", "role"]


class RbacRepository(TenantScopedRepository[CompanyRolePermission]):
    """Reads and writes company_role_permissions rows (RLS-scoped to the tenant)."""

    model = CompanyRolePermission

    async def get_all_for_company(self) -> list[CompanyRolePermission]:
        """Return every non-deleted role row for the current tenant."""
        result = await self.db.execute(
            select(CompanyRolePermission).where(CompanyRolePermission.deleted_at.is_(None))
        )
        return list(result.scalars().all())

    async def get_map(self) -> dict[str, list[str]]:
        """Return {role: permission_keys} for the current tenant."""
        rows = await self.get_all_for_company()
        return {row.role: list(row.permissions) for row in rows}

    async def set_role(self, company_id: uuid.UUID, role: str, permissions: list[str]) -> None:
        """Upsert one role's permission list for the given company."""
        await self.db.execute(
            pg_insert(CompanyRolePermission)
            .values(company_id=company_id, role=role, permissions=permissions)
            .on_conflict_do_update(
                index_elements=_CONFLICT_COLUMNS,
                set_={"permissions": permissions, "updated_at": func.now()},
            )
        )

    async def seed_defaults(self, company_id: uuid.UUID) -> None:
        """Insert the default matrix rows for a company (idempotent)."""
        for role, permissions in DEFAULT_ROLE_PERMISSIONS.items():
            await self.db.execute(
                pg_insert(CompanyRolePermission)
                .values(company_id=company_id, role=role, permissions=permissions)
                .on_conflict_do_nothing(index_elements=_CONFLICT_COLUMNS)
            )
