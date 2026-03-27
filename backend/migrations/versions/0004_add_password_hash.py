"""Add password_hash column to users table.

Revision ID: 0004
Revises: 0003
Create Date: 2026-03-05

Changes:
- Add password_hash column (nullable) to users table
- Nullable because existing users (pre-auth) don't have passwords yet
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("password_hash", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "password_hash")
