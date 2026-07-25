"""project_quotes: project-level quotes that convert to a project with per-field jobs

Revision ID: 0033_project_quotes
Revises: 0032_financial_schema_and_rbac
Create Date: 2026-07-25

Changes:
- quotes.title (TEXT, nullable) — optional project name for a project-level quote,
  used as the created Project's name when the quote is approved.
- quotes.project_id (UUID, nullable, FK projects ON DELETE SET NULL) — set when a
  project-level quote is approved and converted into a project.
- quote_line_items.field (TEXT, nullable) — the trade/field a line item belongs to;
  line items are grouped by field to generate one job per field on conversion.

A "project-level quote" is a quote with neither job_id nor trade_scope_id set. No
new tables and no RLS changes — the added columns live on existing tenant-scoped
tables (quotes, quote_line_items) that already have RLS policies.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0033_project_quotes"
down_revision: str | None = "0032_financial_schema_and_rbac"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("quotes", sa.Column("title", sa.Text(), nullable=True))
    op.add_column(
        "quotes",
        sa.Column("project_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "quotes_project_id_fkey",
        "quotes",
        "projects",
        ["project_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.add_column("quote_line_items", sa.Column("field", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("quote_line_items", "field")
    op.drop_constraint("quotes_project_id_fkey", "quotes", type_="foreignkey")
    op.drop_column("quotes", "project_id")
    op.drop_column("quotes", "title")
