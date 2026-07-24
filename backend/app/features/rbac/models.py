"""ORM model for the per-company role -> permission matrix."""

from __future__ import annotations

from sqlalchemy import CheckConstraint, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base_models import TenantScopedModel

_ROLE_CHECK = (
    "role IN ('owner', 'admin', 'project_manager', 'gc', "
    "'foreman', 'contractor', 'worker', 'client')"
)


class CompanyRolePermission(TenantScopedModel):
    """One row per (company, role) holding the granted permission keys.

    Seeded from app.core.permissions.DEFAULT_ROLE_PERMISSIONS and editable by
    owner/admin. RLS enforced via company_id.
    """

    __tablename__ = "company_role_permissions"

    __table_args__ = (
        UniqueConstraint("company_id", "role", name="uq_company_role"),
        CheckConstraint(_ROLE_CHECK, name="company_role_permissions_role_check"),
    )

    role: Mapped[str] = mapped_column(Text, nullable=False)
    permissions: Mapped[list] = mapped_column(JSONB, nullable=False, server_default="'[]'::jsonb")
