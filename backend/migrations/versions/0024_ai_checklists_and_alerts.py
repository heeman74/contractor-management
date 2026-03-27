"""AI checklists and dashboard alerts: daily_checklists and dashboard_alerts tables with RLS

Revision ID: 0024_ai_checklists_and_alerts
Revises: 0023_per_trade_billing
Create Date: 2026-03-26

Changes:
- CREATE TABLE daily_checklists — AI-generated per-contractor daily task lists
- CREATE TABLE dashboard_alerts — schedule slip and rescheduling suggestion alerts
- RLS policies on both tables (tenant isolation via app.current_company_id)
- UNIQUE constraint on daily_checklists(company_id, contractor_id, trade_scope_id, checklist_date)
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

# revision identifiers, used by Alembic.
revision: str = "0024_ai_checklists_and_alerts"
down_revision: str | None = "0023_per_trade_billing"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # 1. CREATE TABLE daily_checklists
    op.create_table(
        "daily_checklists",
        sa.Column(
            "id",
            sa.UUID(),
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
            primary_key=True,
        ),
        sa.Column("company_id", sa.UUID(), nullable=False),
        sa.Column("contractor_id", sa.UUID(), nullable=False),
        sa.Column("project_id", sa.UUID(), nullable=False),
        sa.Column("trade_scope_id", sa.UUID(), nullable=False),
        sa.Column("checklist_date", sa.Date(), nullable=False),
        sa.Column("checklist_json", JSONB(), nullable=False, server_default=sa.text("'{}'::jsonb")),
        sa.Column("summary_text", sa.Text(), nullable=False),
        sa.Column("is_pushed", sa.Boolean(), nullable=False, server_default="false"),
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
        sa.ForeignKeyConstraint(["company_id"], ["companies.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["contractor_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["project_id"], ["projects.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["trade_scope_id"], ["trade_scopes.id"], ondelete="CASCADE"),
    )

    # BP-8: Partial unique index with WHERE deleted_at IS NULL instead of plain unique constraint.
    # This allows soft-deleted rows to coexist (e.g., regenerating after soft-delete).
    op.execute(
        "CREATE UNIQUE INDEX uq_daily_checklist_contractor_scope_date "
        "ON daily_checklists (company_id, contractor_id, trade_scope_id, checklist_date) "
        "WHERE deleted_at IS NULL"
    )

    # Indexes for daily_checklists
    op.create_index(
        "ix_daily_checklists_company_contractor_date",
        "daily_checklists",
        ["company_id", "contractor_id", "checklist_date"],
    )

    # RLS for daily_checklists
    op.execute("ALTER TABLE daily_checklists ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE daily_checklists FORCE ROW LEVEL SECURITY")
    op.execute(
        "CREATE POLICY tenant_isolation_daily_checklists ON daily_checklists "
        "USING (company_id = current_setting('app.current_company_id')::uuid)"
    )
    op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON daily_checklists TO appuser")
    op.execute(
        "CREATE TRIGGER set_updated_at "
        "BEFORE UPDATE ON daily_checklists "
        "FOR EACH ROW EXECUTE FUNCTION set_updated_at()"
    )

    # 2. CREATE TABLE dashboard_alerts
    op.create_table(
        "dashboard_alerts",
        sa.Column(
            "id",
            sa.UUID(),
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
            primary_key=True,
        ),
        sa.Column("company_id", sa.UUID(), nullable=False),
        sa.Column("project_id", sa.UUID(), nullable=False),
        sa.Column("trade_scope_id", sa.UUID(), nullable=True),
        sa.Column("severity", sa.Text(), nullable=False),
        sa.Column("alert_type", sa.Text(), nullable=False),
        sa.Column("days_behind", sa.Integer(), nullable=True),
        sa.Column("impact_text", sa.Text(), nullable=False),
        sa.Column("remediation_text", sa.Text(), nullable=True),
        sa.Column(
            "affected_scope_ids",
            JSONB(),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("is_read", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("rescheduling_payload", JSONB(), nullable=True),
        sa.Column("rescheduling_accepted", sa.Boolean(), nullable=True),
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
        sa.ForeignKeyConstraint(["company_id"], ["companies.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["project_id"], ["projects.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["trade_scope_id"], ["trade_scopes.id"], ondelete="SET NULL"),
        sa.CheckConstraint(
            "severity IN ('info','warning','critical')",
            name="dashboard_alerts_severity_check",
        ),
        sa.CheckConstraint(
            "alert_type IN ('schedule_slip','rescheduling_suggestion','dependency_risk')",
            name="dashboard_alerts_alert_type_check",
        ),
    )

    # Indexes for dashboard_alerts
    op.create_index(
        "ix_dashboard_alerts_company_project_read",
        "dashboard_alerts",
        ["company_id", "project_id", "is_read"],
    )

    # RLS for dashboard_alerts
    op.execute("ALTER TABLE dashboard_alerts ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE dashboard_alerts FORCE ROW LEVEL SECURITY")
    op.execute(
        "CREATE POLICY tenant_isolation_dashboard_alerts ON dashboard_alerts "
        "USING (company_id = current_setting('app.current_company_id')::uuid)"
    )
    op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON dashboard_alerts TO appuser")
    op.execute(
        "CREATE TRIGGER set_updated_at "
        "BEFORE UPDATE ON dashboard_alerts "
        "FOR EACH ROW EXECUTE FUNCTION set_updated_at()"
    )


def downgrade() -> None:
    # Drop dashboard_alerts
    op.execute("DROP TRIGGER IF EXISTS set_updated_at ON dashboard_alerts")
    op.execute("DROP POLICY IF EXISTS tenant_isolation_dashboard_alerts ON dashboard_alerts")
    op.drop_index("ix_dashboard_alerts_company_project_read", table_name="dashboard_alerts")
    op.drop_table("dashboard_alerts")

    # Drop daily_checklists
    op.execute("DROP TRIGGER IF EXISTS set_updated_at ON daily_checklists")
    op.execute("DROP POLICY IF EXISTS tenant_isolation_daily_checklists ON daily_checklists")
    op.drop_index("ix_daily_checklists_company_contractor_date", table_name="daily_checklists")
    # BP-8: Drop partial unique index (was plain constraint, now a partial index)
    op.execute("DROP INDEX IF EXISTS uq_daily_checklist_contractor_scope_date")
    op.drop_table("daily_checklists")
