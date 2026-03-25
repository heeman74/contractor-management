"""GC Inspection Workflow: task_inspections, site_walk_flags, punch_list_items tables

Revision ID: 0022_inspection_workflow
Revises: 0021_performance_indexes
Create Date: 2026-03-25

Changes:
- Extend tasks status CHECK constraint to include 'rejected'
- Add inspection_checklist JSONB column to trade_scopes
- Create task_inspections table with RLS
- Create site_walk_flags table with RLS
- Create punch_list_items table with RLS
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

# revision identifiers, used by Alembic.
revision: str = "0022_inspection_workflow"
down_revision: str | None = "0021_performance_indexes"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # 1. Extend tasks status CHECK constraint to include 'rejected'
    op.drop_constraint("tasks_status_check", "tasks", type_="check")
    op.create_check_constraint(
        "tasks_status_check",
        "tasks",
        "status IN ('not_started','in_progress','complete','blocked','rejected')",
    )

    # 2. Add inspection_checklist JSONB column to trade_scopes
    op.add_column(
        "trade_scopes",
        sa.Column("inspection_checklist", JSONB, nullable=True),
    )

    # 3. Create task_inspections table
    op.create_table(
        "task_inspections",
        sa.Column(
            "id",
            sa.UUID(),
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
            primary_key=True,
        ),
        sa.Column("company_id", sa.UUID(), nullable=False),
        sa.Column("task_id", sa.UUID(), nullable=False),
        sa.Column("inspector_id", sa.UUID(), nullable=False),
        sa.Column("decision", sa.Text(), nullable=False),
        sa.Column(
            "checklist_results",
            JSONB,
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("rejection_reason", sa.Text(), nullable=True),
        sa.Column("rejection_comment", sa.Text(), nullable=True),
        sa.Column("rejection_photo_url", sa.Text(), nullable=True),
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
        sa.ForeignKeyConstraint(["task_id"], ["tasks.id"], ondelete="CASCADE"),
        sa.CheckConstraint(
            "decision IN ('approved','rejected')",
            name="task_inspections_decision_check",
        ),
    )
    op.create_index("ix_task_inspections_task_id", "task_inspections", ["task_id"])
    op.create_index("ix_task_inspections_company_id", "task_inspections", ["company_id"])
    op.execute("ALTER TABLE task_inspections ENABLE ROW LEVEL SECURITY")
    op.execute(
        "CREATE POLICY tenant_isolation ON task_inspections "
        "USING (company_id = current_setting('app.current_company_id')::uuid)"
    )

    # 4. Create site_walk_flags table
    op.create_table(
        "site_walk_flags",
        sa.Column(
            "id",
            sa.UUID(),
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
            primary_key=True,
        ),
        sa.Column("company_id", sa.UUID(), nullable=False),
        sa.Column("project_id", sa.UUID(), nullable=False),
        sa.Column("flagged_by", sa.UUID(), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("severity", sa.Text(), nullable=False, server_default="'medium'"),
        sa.Column("location_label", sa.Text(), nullable=True),
        sa.Column("photo_url", sa.Text(), nullable=True),
        sa.Column("annotation_data", JSONB, nullable=True),
        sa.Column("status", sa.Text(), nullable=False, server_default="'open'"),
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
        sa.ForeignKeyConstraint(["project_id"], ["projects.id"], ondelete="CASCADE"),
        sa.CheckConstraint(
            "severity IN ('low','medium','high')",
            name="site_walk_flags_severity_check",
        ),
        sa.CheckConstraint(
            "status IN ('open','converted','dismissed')",
            name="site_walk_flags_status_check",
        ),
    )
    op.create_index("ix_site_walk_flags_project_id", "site_walk_flags", ["project_id"])
    op.create_index("ix_site_walk_flags_company_id", "site_walk_flags", ["company_id"])
    op.execute("ALTER TABLE site_walk_flags ENABLE ROW LEVEL SECURITY")
    op.execute(
        "CREATE POLICY tenant_isolation ON site_walk_flags "
        "USING (company_id = current_setting('app.current_company_id')::uuid)"
    )

    # 5. Create punch_list_items table
    op.create_table(
        "punch_list_items",
        sa.Column(
            "id",
            sa.UUID(),
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
            primary_key=True,
        ),
        sa.Column("company_id", sa.UUID(), nullable=False),
        sa.Column("project_id", sa.UUID(), nullable=False),
        sa.Column("trade_scope_id", sa.UUID(), nullable=False),
        sa.Column("created_by", sa.UUID(), nullable=False),
        sa.Column("assigned_to", sa.UUID(), nullable=True),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("priority", sa.Text(), nullable=False, server_default="'medium'"),
        sa.Column("status", sa.Text(), nullable=False, server_default="'open'"),
        sa.Column("photo_url", sa.Text(), nullable=True),
        sa.Column("annotation_data", JSONB, nullable=True),
        sa.Column("source_flag_id", sa.UUID(), nullable=True),
        sa.Column("due_date", sa.Date(), nullable=True),
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
        sa.ForeignKeyConstraint(["project_id"], ["projects.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["trade_scope_id"], ["trade_scopes.id"], ondelete="CASCADE"),
        sa.CheckConstraint(
            "priority IN ('low','medium','high','urgent')",
            name="punch_list_items_priority_check",
        ),
        sa.CheckConstraint(
            "status IN ('open','in_progress','resolved','verified')",
            name="punch_list_items_status_check",
        ),
    )
    op.create_index("ix_punch_list_items_trade_scope_id", "punch_list_items", ["trade_scope_id"])
    op.create_index("ix_punch_list_items_project_id", "punch_list_items", ["project_id"])
    op.create_index("ix_punch_list_items_company_id", "punch_list_items", ["company_id"])
    op.execute("ALTER TABLE punch_list_items ENABLE ROW LEVEL SECURITY")
    op.execute(
        "CREATE POLICY tenant_isolation ON punch_list_items "
        "USING (company_id = current_setting('app.current_company_id')::uuid)"
    )


def downgrade() -> None:
    # Drop tables in reverse order (respect foreign key dependencies)
    op.execute("DROP POLICY IF EXISTS tenant_isolation ON punch_list_items")
    op.drop_table("punch_list_items")

    op.execute("DROP POLICY IF EXISTS tenant_isolation ON site_walk_flags")
    op.drop_table("site_walk_flags")

    op.execute("DROP POLICY IF EXISTS tenant_isolation ON task_inspections")
    op.drop_table("task_inspections")

    # Remove inspection_checklist column from trade_scopes
    op.drop_column("trade_scopes", "inspection_checklist")

    # Restore original tasks status CHECK constraint (without 'rejected')
    op.drop_constraint("tasks_status_check", "tasks", type_="check")
    op.create_check_constraint(
        "tasks_status_check",
        "tasks",
        "status IN ('not_started','in_progress','complete','blocked')",
    )
