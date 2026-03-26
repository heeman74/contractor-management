"""Per-trade billing: billing_milestones table, trade_scope_id on quotes/invoices, job_id nullable

Revision ID: 0023_per_trade_billing
Revises: 0022_inspection_workflow
Create Date: 2026-03-26

Changes:
- ALTER quotes: add trade_scope_id (nullable FK to trade_scopes), make job_id nullable
- ALTER invoices: add trade_scope_id (nullable FK to trade_scopes), add milestone_id (nullable FK
  to billing_milestones), make job_id nullable
- CREATE TABLE billing_milestones with RLS policy
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0023_per_trade_billing"
down_revision: str | None = "0022_inspection_workflow"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # 1. CREATE TABLE billing_milestones (must exist before FK refs from invoices)
    op.create_table(
        "billing_milestones",
        sa.Column(
            "id",
            sa.UUID(),
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
            primary_key=True,
        ),
        sa.Column("company_id", sa.UUID(), nullable=False),
        sa.Column("trade_scope_id", sa.UUID(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("percentage", sa.Numeric(5, 2), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("is_invoiced", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["company_id"], ["companies.id"]),
        sa.ForeignKeyConstraint(["trade_scope_id"], ["trade_scopes.id"], ondelete="CASCADE"),
        sa.CheckConstraint(
            "percentage > 0 AND percentage <= 100",
            name="billing_milestones_percentage_check",
        ),
    )
    op.create_index(
        "ix_billing_milestones_trade_scope_id", "billing_milestones", ["trade_scope_id"]
    )
    op.create_index("ix_billing_milestones_company_id", "billing_milestones", ["company_id"])
    op.execute("ALTER TABLE billing_milestones ENABLE ROW LEVEL SECURITY")
    op.execute(
        "CREATE POLICY tenant_isolation ON billing_milestones "
        "USING (company_id = current_setting('app.current_company_id')::uuid)"
    )
    op.execute(
        "GRANT SELECT, INSERT, UPDATE, DELETE ON billing_milestones TO appuser"
    )
    op.execute(
        "CREATE TRIGGER set_updated_at "
        "BEFORE UPDATE ON billing_milestones "
        "FOR EACH ROW EXECUTE FUNCTION set_updated_at()"
    )

    # 2. ALTER quotes: add trade_scope_id, make job_id nullable
    op.add_column(
        "quotes",
        sa.Column("trade_scope_id", sa.UUID(), nullable=True),
    )
    op.create_foreign_key(
        "fk_quotes_trade_scope_id",
        "quotes",
        "trade_scopes",
        ["trade_scope_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_quotes_trade_scope_id", "quotes", ["trade_scope_id"])
    op.alter_column("quotes", "job_id", nullable=True)

    # 3. ALTER invoices: add trade_scope_id, add milestone_id, make job_id nullable
    op.add_column(
        "invoices",
        sa.Column("trade_scope_id", sa.UUID(), nullable=True),
    )
    op.create_foreign_key(
        "fk_invoices_trade_scope_id",
        "invoices",
        "trade_scopes",
        ["trade_scope_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_invoices_trade_scope_id", "invoices", ["trade_scope_id"])

    op.add_column(
        "invoices",
        sa.Column("milestone_id", sa.UUID(), nullable=True),
    )
    op.create_foreign_key(
        "fk_invoices_milestone_id",
        "invoices",
        "billing_milestones",
        ["milestone_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_invoices_milestone_id", "invoices", ["milestone_id"])
    op.alter_column("invoices", "job_id", nullable=True)


def downgrade() -> None:
    # Reverse: restore job_id NOT NULL on invoices, remove new columns
    op.alter_column("invoices", "job_id", nullable=False)
    op.drop_index("ix_invoices_milestone_id", table_name="invoices")
    op.drop_constraint("fk_invoices_milestone_id", "invoices", type_="foreignkey")
    op.drop_column("invoices", "milestone_id")
    op.drop_index("ix_invoices_trade_scope_id", table_name="invoices")
    op.drop_constraint("fk_invoices_trade_scope_id", "invoices", type_="foreignkey")
    op.drop_column("invoices", "trade_scope_id")

    # Reverse: restore job_id NOT NULL on quotes, remove new columns
    op.alter_column("quotes", "job_id", nullable=False)
    op.drop_index("ix_quotes_trade_scope_id", table_name="quotes")
    op.drop_constraint("fk_quotes_trade_scope_id", "quotes", type_="foreignkey")
    op.drop_column("quotes", "trade_scope_id")

    # Drop billing_milestones table
    op.execute("DROP TRIGGER IF EXISTS set_updated_at ON billing_milestones")
    op.execute("DROP POLICY IF EXISTS tenant_isolation ON billing_milestones")
    op.drop_index("ix_billing_milestones_company_id", table_name="billing_milestones")
    op.drop_index("ix_billing_milestones_trade_scope_id", table_name="billing_milestones")
    op.drop_table("billing_milestones")
