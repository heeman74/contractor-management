"""quote_number: human-facing sequential quote number per company

Revision ID: 0039_quote_number
Revises: 0038_change_orders
Create Date: 2026-07-31

Quotes have been identified in the UI by a slice of their UUID (e.g. "QT-27E6E3"),
which is opaque. This adds an integer `quote_number` assigned sequentially per
company and shared across a quote's revision chain (so revising #5 keeps #5).

Backfill: each revision chain is collapsed to its root (revised_from_quote_id IS
NULL), roots are numbered per company by created_at, and every quote in the chain
inherits its root's number.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0039_quote_number"
down_revision: str | None = "0038_change_orders"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("quotes", sa.Column("quote_number", sa.Integer(), nullable=True))

    # Map every quote to the root of its revision chain, number the roots per
    # company by creation time, and propagate that number to the whole chain.
    op.execute(
        """
        WITH RECURSIVE chain AS (
            SELECT id, id AS root_id FROM quotes WHERE revised_from_quote_id IS NULL
            UNION ALL
            SELECT q.id, c.root_id
            FROM quotes q
            JOIN chain c ON q.revised_from_quote_id = c.id
        ),
        root_num AS (
            SELECT id AS root_id,
                   row_number() OVER (PARTITION BY company_id ORDER BY created_at, id) AS num
            FROM quotes
            WHERE revised_from_quote_id IS NULL
        )
        UPDATE quotes q
        SET quote_number = rn.num
        FROM chain c
        JOIN root_num rn ON rn.root_id = c.root_id
        WHERE q.id = c.id
        """
    )


def downgrade() -> None:
    op.drop_column("quotes", "quote_number")
