"""Add client_type column to users table.

Revision ID: 0012
Revises: 0011
Create Date: 2026-03-16

Changes:
- ALTER TABLE users ADD COLUMN client_type VARCHAR (nullable)

NOTES:
- client_type identifies the originating client ('mobile' | 'web' | NULL).
- Nullable so existing rows are unaffected (backfill not required).
- Used by Phase 13 web auth to attribute sessions to their client origin.
- No RLS policy change needed — column is purely informational.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0012"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("client_type", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "client_type")
