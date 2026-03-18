"""Add amount_paid column to invoices table.

Revision ID: 0013
Revises: 0012
Create Date: 2026-03-18

Changes:
- ALTER TABLE invoices ADD COLUMN amount_paid NUMERIC(10, 2) NOT NULL DEFAULT 0

NOTES:
- amount_paid tracks partial or full payment amounts recorded by admin.
- server_default=0 ensures existing invoice rows default to 0 with no backfill needed.
- Used by Phase 16 Invoices UI to show Total/Paid/Balance payment summary.
- MarkPaidRequest now accepts optional amount_paid alongside status.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0013"
down_revision: str | None = "0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "invoices",
        sa.Column(
            "amount_paid",
            sa.Numeric(10, 2),
            nullable=False,
            server_default="0",
        ),
    )


def downgrade() -> None:
    op.drop_column("invoices", "amount_paid")
