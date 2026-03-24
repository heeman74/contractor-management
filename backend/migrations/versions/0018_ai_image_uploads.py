"""Add ai_image_uploads table

Revision ID: 0018_ai_image_uploads
Revises: 0017
Create Date: 2026-03-23

Changes:
- Create ai_image_uploads table for server-side compressed images used in AI vision
- Enable RLS with tenant isolation policy
- Add index on conversation_id for efficient FK lookups
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision: str = "0018_ai_image_uploads"
down_revision: str | None = "0017"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # ai_image_uploads — compressed JPEG images uploaded for Claude vision
    #
    # Images are compressed server-side to max 1280x1280 JPEG.
    # ON DELETE CASCADE from ai_conversations: images deleted with conversation.
    # media_type is always 'image/jpeg' after server-side normalization.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE IF NOT EXISTS ai_image_uploads (
            id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id        UUID        NOT NULL REFERENCES companies(id),
            conversation_id   UUID        NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
            user_id           UUID        NOT NULL REFERENCES users(id),
            file_path         TEXT        NOT NULL,
            original_filename TEXT        NOT NULL,
            media_type        TEXT        NOT NULL DEFAULT 'image/jpeg',
            file_size_bytes   INTEGER     NOT NULL,
            version           INTEGER     NOT NULL DEFAULT 1,
            created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at        TIMESTAMPTZ
        )
        """)
    )

    # Index for efficient conversation-based lookups
    op.execute(
        text("CREATE INDEX IF NOT EXISTS ix_ai_image_uploads_conversation_id ON ai_image_uploads (conversation_id)")
    )

    # Row Level Security — standard tenant isolation
    op.execute(text("ALTER TABLE ai_image_uploads ENABLE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_policies
                WHERE tablename = 'ai_image_uploads' AND policyname = 'tenant_isolation'
            ) THEN
                CREATE POLICY tenant_isolation ON ai_image_uploads
                    USING (
                        company_id = NULLIF(current_setting('app.current_company_id', TRUE), '')::UUID
                    );
            END IF;
        END $$;
        """)
    )
    op.execute(text("ALTER TABLE ai_image_uploads FORCE ROW LEVEL SECURITY"))

    # set_updated_at trigger — auto-update updated_at on every row mutation
    op.execute(
        text("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_trigger
                WHERE tgname = 'set_updated_at'
                  AND tgrelid = 'ai_image_uploads'::regclass
            ) THEN
                CREATE TRIGGER set_updated_at
                    BEFORE UPDATE ON ai_image_uploads
                    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
            END IF;
        END $$;
        """)
    )


def downgrade() -> None:
    op.execute(text("DROP TRIGGER IF EXISTS set_updated_at ON ai_image_uploads"))
    op.execute(text("DROP INDEX IF EXISTS ix_ai_image_uploads_conversation_id"))
    op.execute(text("DROP TABLE IF EXISTS ai_image_uploads"))
