"""company_role_permissions: per-company editable role -> permission matrix

Revision ID: 0027_company_role_permissions
Revises: 0026_expand_user_roles
Create Date: 2026-07-23

Changes:
- CREATE TABLE company_role_permissions — one row per (company, role) holding a
  JSONB list of granted permission keys.
- Backfill every existing company with the default matrix BEFORE enabling RLS,
  so the table owner (appuser, NOBYPASSRLS) can insert without tenant context.
- Enable + FORCE RLS with company-scoped tenant isolation, matching the other
  tenant tables.

Default seeds come from app.core.permissions.DEFAULT_ROLE_PERMISSIONS — the same
source seed-on-register uses, so new and existing companies start identically.
"""

import json
from collections.abc import Sequence

from alembic import op

from app.core.permissions import DEFAULT_ROLE_PERMISSIONS

# revision identifiers, used by Alembic.
revision: str = "0027_company_role_permissions"
down_revision: str | None = "0026_expand_user_roles"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_ROLE_CHECK = (
    "role IN ('owner', 'admin', 'project_manager', 'gc', "
    "'foreman', 'contractor', 'worker', 'client')"
)


def _default_rows_values() -> str:
    """Build the VALUES clause of (role, permissions) default rows.

    Permission lists are JSON-encoded; catalog keys contain no single quotes, so
    the encoded literals are safe to interpolate directly.
    """
    return ", ".join(
        f"('{role}', '{json.dumps(perms)}'::jsonb)"
        for role, perms in DEFAULT_ROLE_PERMISSIONS.items()
    )


def upgrade() -> None:
    op.execute(f"""
        CREATE TABLE company_role_permissions (
            id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id  UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            role        TEXT NOT NULL CHECK ({_ROLE_CHECK}),
            permissions JSONB NOT NULL DEFAULT '[]'::jsonb,
            version     INTEGER NOT NULL DEFAULT 1,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at  TIMESTAMPTZ,
            CONSTRAINT uq_company_role UNIQUE (company_id, role)
        )
    """)

    # Backfill existing companies from the default matrix while RLS is still off.
    op.execute(f"""
        INSERT INTO company_role_permissions (company_id, role, permissions)
        SELECT c.id, d.role, d.permissions
        FROM companies c
        CROSS JOIN (VALUES {_default_rows_values()}) AS d(role, permissions)
    """)

    op.execute("ALTER TABLE company_role_permissions ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE company_role_permissions FORCE ROW LEVEL SECURITY")
    op.execute("""
        CREATE POLICY tenant_isolation_company_role_permissions
        ON company_role_permissions
        USING (company_id = current_setting('app.current_company_id')::uuid)
    """)


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS company_role_permissions CASCADE")
