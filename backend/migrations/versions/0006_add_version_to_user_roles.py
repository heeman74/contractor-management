"""Add version column to user_roles table.

Revision ID: 0006
Revises: 0005
Create Date: 2026-03-06

Changes:
- Add version (integer, NOT NULL, default 1) to user_roles table.
  This aligns user_roles with the BaseEntityModel which requires
  id, version, created_at, updated_at, deleted_at on all entities.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0006"
down_revision: Union[str, None] = "0005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "user_roles",
        sa.Column(
            "version",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("1"),
        ),
    )


def downgrade() -> None:
    op.drop_column("user_roles", "version")
