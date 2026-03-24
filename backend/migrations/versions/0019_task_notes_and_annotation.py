"""Add task_notes table and annotation_data column on task_attachments

Revision ID: 0019_task_notes_and_annotation
Revises: 0018_ai_image_uploads
Create Date: 2026-03-24

Changes:
- Create task_notes table for task-level field notes (author, body, timestamps)
- Add annotation_data JSONB column to task_attachments (for photo annotation data)
- Enable RLS on task_notes with tenant isolation policy
- Add index on task_notes(task_id) for efficient task-based lookups
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy import text
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "0019_task_notes_and_annotation"
down_revision: str | None = "0018_ai_image_uploads"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # task_notes — field notes written by contractors against a specific task
    #
    # author_id is a soft FK to users (no hard FK) per project pattern:
    # avoids tight coupling between task notes and user table structure.
    # task_id has ON DELETE CASCADE — notes are deleted when their task is.
    # RLS policy mirrors other task tables: company_id must match JWT claim.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE IF NOT EXISTS task_notes (
            id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id  UUID        NOT NULL REFERENCES companies(id),
            task_id     UUID        NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            author_id   UUID        NOT NULL,
            body        TEXT        NOT NULL,
            version     INTEGER     NOT NULL DEFAULT 1,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at  TIMESTAMPTZ
        )
        """)
    )

    # Index for efficient task-based lookups (GET /tasks/{task_id}/notes)
    op.execute(text("CREATE INDEX IF NOT EXISTS ix_task_notes_task_id ON task_notes (task_id)"))

    # Row Level Security — standard tenant isolation
    op.execute(text("ALTER TABLE task_notes ENABLE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_policies
                WHERE tablename = 'task_notes' AND policyname = 'tenant_isolation'
            ) THEN
                CREATE POLICY tenant_isolation ON task_notes
                    USING (
                        company_id = NULLIF(current_setting('app.current_company_id', TRUE), '')::UUID
                    );
            END IF;
        END $$;
        """)
    )
    op.execute(text("ALTER TABLE task_notes FORCE ROW LEVEL SECURITY"))

    # set_updated_at trigger — auto-update updated_at on every row mutation
    op.execute(
        text("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_trigger
                WHERE tgname = 'set_updated_at'
                  AND tgrelid = 'task_notes'::regclass
            ) THEN
                CREATE TRIGGER set_updated_at
                    BEFORE UPDATE ON task_notes
                    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
            END IF;
        END $$;
        """)
    )

    # -------------------------------------------------------------------------
    # annotation_data — JSONB column on task_attachments
    #
    # Stores non-destructive annotation JSON (arrows, circles, text, etc.).
    # Base photo is immutable; annotations stored separately per D-6 decision.
    # Nullable — not all attachments have annotations.
    # -------------------------------------------------------------------------
    op.add_column(
        "task_attachments",
        sa.Column("annotation_data", postgresql.JSONB, nullable=True),
    )


def downgrade() -> None:
    op.drop_column("task_attachments", "annotation_data")
    op.execute(text("DROP TRIGGER IF EXISTS set_updated_at ON task_notes"))
    op.execute(text("DROP INDEX IF EXISTS ix_task_notes_task_id"))
    op.execute(text("DROP TABLE IF EXISTS task_notes"))
