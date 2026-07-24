"""Expand user_roles.valid_role CHECK to the eight-role set

Revision ID: 0026_expand_user_roles
Revises: 0025_foreman_role
Create Date: 2026-07-23

Changes:
- Replace the user_roles valid_role CHECK constraint so it accepts the five new
  user-level roles (owner, project_manager, gc, foreman, worker) alongside the
  existing admin, contractor, client.

The role column is TEXT + a named CHECK constraint, so this is a pure
DROP/ADD CONSTRAINT — additive, reversible, and does not rewrite any data.
RLS on user_roles is company-scoped only and is intentionally left unchanged.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0026_expand_user_roles"
down_revision: str | None = "0025_foreman_role"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_EXPANDED_ROLES = (
    "'owner', 'admin', 'project_manager', 'gc', 'foreman', 'contractor', 'worker', 'client'"
)
_ORIGINAL_ROLES = "'admin', 'contractor', 'client'"


def upgrade() -> None:
    op.execute("ALTER TABLE user_roles DROP CONSTRAINT valid_role")
    op.execute(
        f"ALTER TABLE user_roles ADD CONSTRAINT valid_role CHECK (role IN ({_EXPANDED_ROLES}))"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE user_roles DROP CONSTRAINT valid_role")
    op.execute(
        f"ALTER TABLE user_roles ADD CONSTRAINT valid_role CHECK (role IN ({_ORIGINAL_ROLES}))"
    )
