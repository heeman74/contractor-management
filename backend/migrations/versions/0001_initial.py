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
        sa.Column("trade_types", sa.ARRAY(sa.String()), nullable=True),
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
    # SELECT: allow reads when no tenant context is set (auth flows like login
    # need to look up users by email globally) OR when tenant matches.
    # INSERT/UPDATE/DELETE: require tenant context to match.
    #
    # NULLIF handles empty-string GUC values that occur when a connection is
    # reused from the pool after a previous SET LOCAL.
    # -------------------------------------------------------------------------
    for table in ("users", "user_roles"):
        op.execute(text(f"""
            CREATE POLICY tenant_select ON {table}
            FOR SELECT
            USING (
                NULLIF(current_setting('app.current_company_id', true), '') IS NULL
                OR company_id = NULLIF(current_setting('app.current_company_id', true), '')::uuid
            )
        """))
        op.execute(text(f"""
            CREATE POLICY tenant_write ON {table}
            FOR INSERT
            WITH CHECK (company_id = NULLIF(current_setting('app.current_company_id', true), '')::uuid)
        """))
        op.execute(text(f"""
            CREATE POLICY tenant_update ON {table}
            FOR UPDATE
            USING (company_id = NULLIF(current_setting('app.current_company_id', true), '')::uuid)
        """))
        op.execute(text(f"""
            CREATE POLICY tenant_delete ON {table}
            FOR DELETE
            USING (company_id = NULLIF(current_setting('app.current_company_id', true), '')::uuid)
        """))


def downgrade() -> None:
    # Drop policies before tables
    for table in ("user_roles", "users"):
        op.execute(text(f"DROP POLICY IF EXISTS tenant_select ON {table}"))
        op.execute(text(f"DROP POLICY IF EXISTS tenant_write ON {table}"))
        op.execute(text(f"DROP POLICY IF EXISTS tenant_update ON {table}"))
        op.execute(text(f"DROP POLICY IF EXISTS tenant_delete ON {table}"))

    # Drop tables in reverse dependency order
    op.drop_table("user_roles")
    op.drop_table("users")
    op.drop_table("companies")
