"""Initial schema with companies, users, user_roles and RLS policies.

Revision ID: 0001
Revises:
Create Date: 2026-03-04

Creates:
- companies table (tenant root — NO RLS)
- users table (tenant-scoped, RLS + FORCE RLS)
- user_roles table (tenant-scoped, RLS + FORCE RLS)
- Tenant isolation policies using current_setting('app.current_company_id', true)
- Indexes for tenant queries
- Extensions: uuid-ossp, btree_gist (idempotent — init.sql may have already run them)
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Extensions — idempotent (safe even though docker/init.sql may have run them)
    # NOTE: if the migration user lacks superuser privileges, these are no-ops
    # because init.sql already installed them as the postgres superuser.
    op.execute(text('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"'))
    op.execute(text("CREATE EXTENSION IF NOT EXISTS btree_gist"))

    # -------------------------------------------------------------------------
    # Companies table — tenant root
    # NEVER apply RLS or FORCE RLS to this table: it IS the tenant boundary.
    # -------------------------------------------------------------------------
    op.create_table(
        "companies",
        sa.Column(
            "id",
            sa.UUID(),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("address", sa.String(), nullable=True),
        sa.Column("phone", sa.String(), nullable=True),
        sa.Column("business_number", sa.String(), nullable=True),
        sa.Column("logo_url", sa.String(), nullable=True),
        sa.Column(
            "version", sa.Integer(), nullable=False, server_default=sa.text("1")
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )

    # -------------------------------------------------------------------------
    # Users table — tenant-scoped (RLS enforced)
    # -------------------------------------------------------------------------
    op.create_table(
        "users",
        sa.Column(
            "id",
            sa.UUID(),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column(
            "company_id",
            sa.UUID(),
            sa.ForeignKey("companies.id"),
            nullable=False,
        ),
        sa.Column("email", sa.String(), nullable=False),
        sa.Column("first_name", sa.String(), nullable=True),
        sa.Column("last_name", sa.String(), nullable=True),
        sa.Column("phone", sa.String(), nullable=True),
        sa.Column(
            "version", sa.Integer(), nullable=False, server_default=sa.text("1")
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index("idx_users_company_id", "users", ["company_id"])

    # -------------------------------------------------------------------------
    # User roles junction table — tenant-scoped (RLS enforced)
    # Supports multiple roles per user (e.g., admin in company A, contractor in B)
    # -------------------------------------------------------------------------
    op.create_table(
        "user_roles",
        sa.Column(
            "id",
            sa.UUID(),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            sa.UUID(),
            sa.ForeignKey("users.id"),
            nullable=False,
        ),
        sa.Column(
            "company_id",
            sa.UUID(),
            sa.ForeignKey("companies.id"),
            nullable=False,
        ),
        sa.Column("role", sa.String(), nullable=False),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.CheckConstraint(
            "role IN ('admin', 'contractor', 'client')", name="valid_role"
        ),
    )
    op.create_index("idx_user_roles_company_id", "user_roles", ["company_id"])
    op.create_index("idx_user_roles_user_id", "user_roles", ["user_id"])

    # -------------------------------------------------------------------------
    # Enable Row Level Security on tenant-scoped tables
    # FORCE ROW LEVEL SECURITY ensures table owner (appuser) is also subject to
    # the policy — prevents accidental bypass during development.
    # NEVER apply FORCE RLS to the companies table.
    # -------------------------------------------------------------------------
    op.execute(text("ALTER TABLE users ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE users FORCE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE user_roles FORCE ROW LEVEL SECURITY"))

    # -------------------------------------------------------------------------
    # Tenant isolation RLS policies
    #
    # CRITICAL: current_setting('app.current_company_id', true)
    #   - The `true` second argument = "return NULL if setting is not set"
    #     (prevents ERROR on superuser sessions, Alembic runs, DBA tooling)
    #   - Without `true`: ERROR: unrecognized configuration parameter "..."
    #   - With `true`: NULL::uuid = any uuid evaluates to NULL (not true),
    #     so no rows match — correct behavior for unscoped sessions.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON users
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON user_roles
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )


def downgrade() -> None:
    # Drop policies before tables
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON user_roles"))
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON users"))

    # Drop tables in reverse dependency order
    op.drop_table("user_roles")
    op.drop_table("users")
    op.drop_table("companies")
