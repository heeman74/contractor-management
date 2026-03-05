"""Add deleted_at columns and updated_at PostgreSQL trigger for sync.

Revision ID: 0002
Revises: 0001
Create Date: 2026-03-05

Changes:
- Add deleted_at (nullable, timestamptz) to companies, users, user_roles
- Add updated_at to user_roles (needed for delta sync cursor filter)
- Create set_updated_at() PostgreSQL trigger function
- Attach trigger to companies, users, user_roles BEFORE UPDATE

CRITICAL: The PostgreSQL trigger ensures updated_at advances on ALL updates,
including bulk SQLAlchemy operations. SQLAlchemy onupdate=func.now() is ORM-
level only and does NOT fire for bulk updates or raw SQL.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision: str = "0002"
down_revision: Union[str, None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # Add deleted_at to all three entity tables
    # nullable — NULL means the record is active (not deleted)
    # -------------------------------------------------------------------------
    op.add_column(
        "companies",
        sa.Column("deleted_at", sa.TIMESTAMP(timezone=True), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("deleted_at", sa.TIMESTAMP(timezone=True), nullable=True),
    )
    op.add_column(
        "user_roles",
        sa.Column("deleted_at", sa.TIMESTAMP(timezone=True), nullable=True),
    )

    # -------------------------------------------------------------------------
    # Add updated_at to user_roles (was missing from initial migration)
    # Required for delta sync filter: updated_at > cursor
    # -------------------------------------------------------------------------
    op.add_column(
        "user_roles",
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            nullable=True,
            server_default=sa.func.now(),
        ),
    )

    # -------------------------------------------------------------------------
    # Create set_updated_at() trigger function
    #
    # This ensures updated_at is set by PostgreSQL itself on every UPDATE,
    # regardless of whether the update comes from the ORM, raw SQL, or bulk ops.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE OR REPLACE FUNCTION set_updated_at()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.updated_at = NOW();
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
    """)
    )

    # -------------------------------------------------------------------------
    # Attach trigger to each entity table (BEFORE UPDATE, FOR EACH ROW)
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TRIGGER set_companies_updated_at
        BEFORE UPDATE ON companies
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER set_users_updated_at
        BEFORE UPDATE ON users
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER set_user_roles_updated_at
        BEFORE UPDATE ON user_roles
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    """)
    )


def downgrade() -> None:
    # Drop triggers first (must exist before function is dropped)
    op.execute(text("DROP TRIGGER IF EXISTS set_user_roles_updated_at ON user_roles"))
    op.execute(text("DROP TRIGGER IF EXISTS set_users_updated_at ON users"))
    op.execute(text("DROP TRIGGER IF EXISTS set_companies_updated_at ON companies"))

    # Drop the trigger function
    op.execute(text("DROP FUNCTION IF EXISTS set_updated_at()"))

    # Drop updated_at from user_roles (added in this migration)
    op.drop_column("user_roles", "updated_at")

    # Drop deleted_at from all three tables
    op.drop_column("user_roles", "deleted_at")
    op.drop_column("users", "deleted_at")
    op.drop_column("companies", "deleted_at")
