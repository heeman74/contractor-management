"""Backfill user_roles.updated_at for rows with NULL values.

Revision ID: 0003
Revises: 0002
Create Date: 2026-03-06

Changes:
- Backfill user_roles.updated_at = created_at WHERE updated_at IS NULL
- Alter user_roles.updated_at to NOT NULL (safe after backfill)

Root cause: migration 0002 added updated_at via ALTER TABLE ADD COLUMN with a
server_default, but PostgreSQL does NOT backfill server_default into existing
rows — only new inserts after the ALTER receive the default. Rows seeded or
inserted before migration 0002 ran have updated_at = NULL.

The sync query in service.py filters on:
  WHERE updated_at > since OR deleted_at > since

In PostgreSQL, NULL > any_value evaluates to NULL (not TRUE). Both updated_at
and deleted_at are NULL on every pre-existing user_role row, so the WHERE
clause matches zero rows and user_roles returns empty.

Fix: backfill updated_at = created_at for all NULL rows, then enforce NOT NULL
so future inserts cannot silently produce NULL values.
"""

from typing import Sequence, Union

from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # Backfill updated_at for rows where it is NULL.
    #
    # Sets updated_at = created_at, which is always non-NULL (it was present
    # from migration 0001). This gives each pre-existing row a meaningful
    # timestamp that reflects when it was first created.
    # -------------------------------------------------------------------------
    op.execute(
        text("UPDATE user_roles SET updated_at = created_at WHERE updated_at IS NULL")
    )

    # -------------------------------------------------------------------------
    # Enforce NOT NULL constraint now that all rows have a value.
    #
    # Safe to apply after the UPDATE above — no rows can have NULL updated_at
    # at this point. This makes user_roles.updated_at consistent with the
    # updated_at columns on users and companies (both already NOT NULL).
    # -------------------------------------------------------------------------
    op.alter_column("user_roles", "updated_at", nullable=False)


def downgrade() -> None:
    # Reverse the NOT NULL constraint only.
    # We do NOT un-backfill the data — rows that were backfilled keep their
    # updated_at value. This is intentional: a downgrade should only relax
    # the constraint, not destroy data.
    op.alter_column("user_roles", "updated_at", nullable=True)
