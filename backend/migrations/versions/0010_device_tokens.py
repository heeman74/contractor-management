"""Create device_tokens table for FCM push notification registration.

Revision ID: 0010
Revises: 0009
Create Date: 2026-03-13

Changes:
- Create device_tokens table with RLS (user_id-scoped, not company-scoped)
- Unique constraint on (user_id, token) — same device registers once per user
- Index on user_id for efficient token lookup per user
- Platforms restricted to 'android' and 'ios' via CHECK constraint

CRITICAL NOTES:
- device_tokens is user-scoped, NOT tenant-scoped — no company_id column.
- RLS policy uses app.current_user_id (set by auth layer) OR allows access
  via super-user appuser for admin operations.
- Table creation uses op.execute(text(...)) consistent with migration 0007/0008/0009 pattern.
- set_updated_at() trigger function was created in migration 0002 — just CREATE TRIGGER here.
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision: str = "0010"
down_revision: str | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # device_tokens — FCM device token registry for push notification dispatch
    #
    # user_id: FK to users(id) — token belongs to authenticated user
    # token:   FCM registration token string (variable length)
    # platform: 'android' or 'ios' — determines FCM message format
    # created_at: when token was first registered
    # last_used_at: updated on each successful notification send or re-registration
    #
    # UNIQUE(user_id, token): same device (token) registered once per user.
    # If user re-registers with same token, last_used_at is updated (upsert pattern).
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE device_tokens (
            id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            token        TEXT        NOT NULL,
            platform     VARCHAR(10) NOT NULL CHECK (platform IN ('android', 'ios')),
            created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
            last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            UNIQUE (user_id, token)
        )
        """)
    )

    # Index on user_id for efficient lookup of all tokens for a given user
    op.execute(text("CREATE INDEX idx_device_tokens_user_id ON device_tokens (user_id)"))

    # -------------------------------------------------------------------------
    # Row Level Security — user-scoped access
    # Users can only see/manage their own device tokens.
    # The appuser DB role bypasses RLS for backend service operations.
    # -------------------------------------------------------------------------
    op.execute(text("ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY"))

    op.execute(
        text("""
        CREATE POLICY user_isolation ON device_tokens
            USING (
                user_id = NULLIF(current_setting('app.current_user_id', TRUE), '')::UUID
            )
        """)
    )

    # Allow appuser (backend service account) full access — bypasses RLS
    op.execute(text("ALTER TABLE device_tokens FORCE ROW LEVEL SECURITY"))


def downgrade() -> None:
    op.execute(text("DROP TABLE IF EXISTS device_tokens"))
