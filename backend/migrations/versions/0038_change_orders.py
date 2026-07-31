"""change_orders: change-order-flavored quotes scoped to an existing project

Revision ID: 0038_change_orders
Revises: 0037_quote_line_review_state
Create Date: 2026-07-30

A change order is a quote raised while work is in progress, against an EXISTING
project, that on client approval adds work to that project (a new job, or scope
appended to the originating job) and rolls its amount into the project budget.

Modeled as a quote variant (no new table): quotes gains
- quote_kind         'standard' | 'change_order' (default 'standard')
- co_number          INTEGER — sequential per project for change orders
- change_reason      TEXT — the justification (unforeseen finding, added scope)
- schedule_impact_days INTEGER — days added to the project completion
- originating_job_id UUID FK jobs — the in-progress job that surfaced the change
- co_target          'new_job' | 'existing_job' — what approval creates
- created_job_id     UUID FK jobs — the job created on approval (traceability)

For a change order, quotes.project_id is set at DRAFT time (the project it
amends); a standard project-level quote still sets project_id only on approval.
quote_kind disambiguates the two. Columns live on the existing tenant-scoped
quotes table, which already has RLS — no new tables, no RLS changes.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0038_change_orders"
down_revision: str | None = "0037_quote_line_review_state"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "quotes",
        sa.Column("quote_kind", sa.Text(), nullable=False, server_default="standard"),
    )
    op.add_column("quotes", sa.Column("co_number", sa.Integer(), nullable=True))
    op.add_column("quotes", sa.Column("change_reason", sa.Text(), nullable=True))
    op.add_column("quotes", sa.Column("schedule_impact_days", sa.Integer(), nullable=True))
    op.add_column(
        "quotes",
        sa.Column("originating_job_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.add_column("quotes", sa.Column("co_target", sa.Text(), nullable=True))
    op.add_column(
        "quotes",
        sa.Column("created_job_id", postgresql.UUID(as_uuid=True), nullable=True),
    )

    op.create_check_constraint(
        "quotes_quote_kind_check",
        "quotes",
        "quote_kind IN ('standard','change_order')",
    )
    op.create_check_constraint(
        "quotes_co_target_check",
        "quotes",
        "co_target IS NULL OR co_target IN ('new_job','existing_job')",
    )
    op.create_foreign_key(
        "quotes_originating_job_id_fkey",
        "quotes",
        "jobs",
        ["originating_job_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_foreign_key(
        "quotes_created_job_id_fkey",
        "quotes",
        "jobs",
        ["created_job_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint("quotes_created_job_id_fkey", "quotes", type_="foreignkey")
    op.drop_constraint("quotes_originating_job_id_fkey", "quotes", type_="foreignkey")
    op.drop_constraint("quotes_co_target_check", "quotes", type_="check")
    op.drop_constraint("quotes_quote_kind_check", "quotes", type_="check")
    op.drop_column("quotes", "created_job_id")
    op.drop_column("quotes", "co_target")
    op.drop_column("quotes", "originating_job_id")
    op.drop_column("quotes", "schedule_impact_days")
    op.drop_column("quotes", "change_reason")
    op.drop_column("quotes", "co_number")
    op.drop_column("quotes", "quote_kind")
