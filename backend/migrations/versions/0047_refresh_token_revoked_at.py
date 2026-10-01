"""refresh_tokens.revoked_at: timestamp for the concurrent-refresh grace window

Revision ID: 0047_refresh_token_revoked_at
Revises: 0046_company_email_settings
Create Date: 2026-10-01

Records when a refresh token was revoked so token rotation can tell a concurrent
refresh (two tabs racing, within a short grace window) from a genuinely replayed
stolen token. Without it, the second tab's refresh looked like reuse and revoked
the whole session family, logging the user out unexpectedly.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0047_refresh_token_revoked_at"
down_revision: str | None = "0046_company_email_settings"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "refresh_tokens",
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("refresh_tokens", "revoked_at")
