"""project_assignment_roles: allow project_manager and contractor assignments

Revision ID: 0028_project_assignment_roles
Revises: 0027_company_role_permissions
Create Date: 2026-07-23

Changes:
- Widen project_assignments.role CHECK constraint from
  ('foreman', 'lead', 'inspector') to also allow 'project_manager' and 'contractor',
  so a project can have an assigned PM and contractors (not just foreman roles).

No data changes — existing rows already satisfy the wider constraint.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0028_project_assignment_roles"
down_revision: str | None = "0027_company_role_permissions"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_CONSTRAINT = "project_assignments_role_check"
_NEW_ROLES = "'foreman', 'lead', 'inspector', 'project_manager', 'contractor'"
_OLD_ROLES = "'foreman', 'lead', 'inspector'"


def upgrade() -> None:
    op.execute(f"ALTER TABLE project_assignments DROP CONSTRAINT {_CONSTRAINT}")
    op.execute(
        f"ALTER TABLE project_assignments ADD CONSTRAINT {_CONSTRAINT} "
        f"CHECK (role IN ({_NEW_ROLES}))"
    )


def downgrade() -> None:
    # Reverting requires no rows use the new roles; callers must clean those first.
    op.execute(f"ALTER TABLE project_assignments DROP CONSTRAINT {_CONSTRAINT}")
    op.execute(
        f"ALTER TABLE project_assignments ADD CONSTRAINT {_CONSTRAINT} "
        f"CHECK (role IN ({_OLD_ROLES}))"
    )
