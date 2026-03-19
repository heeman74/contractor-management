"""Add unique constraint on users.email.

Revision ID: 0014
Revises: 0013
Create Date: 2026-03-19

Changes:
- ALTER TABLE users ADD CONSTRAINT uq_users_email UNIQUE (email)

NOTES:
- Prevents race-condition duplicate registrations that the Python-level
  SELECT-before-INSERT check in AuthService.register() cannot prevent.
- Model already declares unique=True; this migration enforces it at the DB level.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0014"
down_revision: str | None = "0013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_unique_constraint("uq_users_email", "users", ["email"])


def downgrade() -> None:
    op.drop_constraint("uq_users_email", "users", type_="unique")
