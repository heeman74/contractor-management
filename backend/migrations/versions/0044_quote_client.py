"""quotes.client_id: the client a quote is addressed to

Revision ID: 0044_quote_client
Revises: 0043_ai_quote_interview
Create Date: 2026-09-29

A quote had no client of its own. The only route to one was job.client_id,
which is itself nullable ("job may exist before client is assigned"), and a
project-level quote has no job at all — so no quote path guaranteed a
recipient, and the send transition never checked for one. Quotes were moving to
`sent` addressed to nobody.

Nullable, because a draft legitimately starts before the client is known and
existing drafts have none. The requirement is enforced on the send transition
instead, which is where "sent to whom?" actually has to have an answer.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0044_quote_client"
down_revision: str | None = "0043_ai_quote_interview"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("quotes", sa.Column("client_id", sa.UUID(), nullable=True))
    op.create_foreign_key("quotes_client_id_fkey", "quotes", "users", ["client_id"], ["id"])
    op.create_index("ix_quotes_client_id", "quotes", ["client_id"])

    # Backfill from the job that already named a client, so quotes which did
    # have a reachable recipient keep it rather than becoming unsendable.
    op.execute(
        """
        UPDATE quotes q
        SET client_id = j.client_id
        FROM jobs j
        WHERE q.job_id = j.id AND j.client_id IS NOT NULL AND q.client_id IS NULL
        """
    )


def downgrade() -> None:
    op.drop_index("ix_quotes_client_id", table_name="quotes")
    op.drop_constraint("quotes_client_id_fkey", "quotes", type_="foreignkey")
    op.drop_column("quotes", "client_id")
