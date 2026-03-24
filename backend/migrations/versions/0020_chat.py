"""Add chat tables: chat_threads, chat_messages, chat_memberships, chat_read_receipts

Revision ID: 0020_chat
Revises: 0019_task_notes_and_annotation
Create Date: 2026-03-24

Changes:
- Create chat_threads table (project-scoped threads: scope or project_wide)
- Create chat_messages table with client-generated UUID PK for deduplication
- Create chat_memberships table (who belongs to each thread)
- Create chat_read_receipts table (per-user read position per thread)
- Create chat_message_seq sequence for server-assigned monotonic message ordering
- Enable Row Level Security on all 4 tables with tenant isolation policies
- Create indexes for common access patterns (thread+seq, company, project, user)
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision: str = "0020_chat"
down_revision: str | None = "0019_task_notes_and_annotation"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # chat_message_seq — monotonic server-assigned sequence for message ordering
    #
    # Client-generated UUIDs are used as PK (dedup key), but seq gives a
    # monotonically increasing integer for cursor pagination and read receipts.
    # -------------------------------------------------------------------------
    op.execute(text("CREATE SEQUENCE IF NOT EXISTS chat_message_seq"))

    # -------------------------------------------------------------------------
    # chat_threads — top-level container: one per trade scope or project-wide
    #
    # thread_type: 'scope' (one per trade scope) or 'project_wide' (one per project)
    # trade_scope_id: NULL for project_wide threads, FK for scope threads
    # name: human-readable thread name (e.g. "Plumbing" or "Project-Wide")
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE IF NOT EXISTS chat_threads (
            id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id      UUID        NOT NULL REFERENCES companies(id),
            project_id      UUID        NOT NULL REFERENCES projects(id),
            thread_type     TEXT        NOT NULL CHECK (thread_type IN ('scope', 'project_wide')),
            trade_scope_id  UUID        REFERENCES trade_scopes(id),
            name            TEXT        NOT NULL,
            version         INTEGER     NOT NULL DEFAULT 1,
            created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at      TIMESTAMPTZ
        )
        """)
    )

    # -------------------------------------------------------------------------
    # chat_messages — individual messages within a thread
    #
    # id: client-generated UUID — acts as idempotency key (ON CONFLICT DO NOTHING)
    # seq: server-assigned from chat_message_seq — stable ordering for pagination
    # content: nullable — attachment-only messages have no text content
    # attachment_type: 'photo', 'pdf', or 'annotated_photo'
    # annotation_data: JSON string for annotated photos (overlay coordinates)
    # mentions: JSONB array of user UUIDs mentioned in the message
    # mention_all: true if the sender used @everyone
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE IF NOT EXISTS chat_messages (
            id               UUID        PRIMARY KEY,
            company_id       UUID        NOT NULL REFERENCES companies(id),
            thread_id        UUID        NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
            sender_id        UUID        NOT NULL REFERENCES users(id),
            content          TEXT,
            seq              BIGINT      NOT NULL DEFAULT nextval('chat_message_seq'),
            attachment_url   TEXT,
            attachment_type  TEXT        CHECK (attachment_type IN ('photo', 'pdf', 'annotated_photo')),
            annotation_data  TEXT,
            mentions         JSONB       NOT NULL DEFAULT '[]'::jsonb,
            mention_all      BOOLEAN     NOT NULL DEFAULT false,
            version          INTEGER     NOT NULL DEFAULT 1,
            created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at       TIMESTAMPTZ
        )
        """)
    )

    # -------------------------------------------------------------------------
    # chat_memberships — maps users to threads they can access
    #
    # muted: user has silenced notifications for this thread
    # joined_at: when the user was added (may differ from thread creation)
    # UNIQUE (thread_id, user_id): one membership per user per thread
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE IF NOT EXISTS chat_memberships (
            id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id  UUID        NOT NULL REFERENCES companies(id),
            thread_id   UUID        NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
            user_id     UUID        NOT NULL REFERENCES users(id),
            muted       BOOLEAN     NOT NULL DEFAULT false,
            joined_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
            version     INTEGER     NOT NULL DEFAULT 1,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at  TIMESTAMPTZ,
            UNIQUE (thread_id, user_id)
        )
        """)
    )

    # -------------------------------------------------------------------------
    # chat_read_receipts — per-user read position per thread
    #
    # last_read_seq: the highest seq the user has confirmed reading
    # read_at: when the user last marked messages as read
    # UNIQUE (thread_id, user_id): upserted on mark_read to update position
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE IF NOT EXISTS chat_read_receipts (
            id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id      UUID        NOT NULL REFERENCES companies(id),
            thread_id       UUID        NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
            user_id         UUID        NOT NULL REFERENCES users(id),
            last_read_seq   BIGINT      NOT NULL,
            read_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
            version         INTEGER     NOT NULL DEFAULT 1,
            created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at      TIMESTAMPTZ,
            UNIQUE (thread_id, user_id)
        )
        """)
    )

    # Indexes for common access patterns
    op.execute(
        text(
            "CREATE INDEX IF NOT EXISTS idx_chat_messages_thread_seq "
            "ON chat_messages (thread_id, seq)"
        )
    )
    op.execute(
        text("CREATE INDEX IF NOT EXISTS idx_chat_messages_company ON chat_messages (company_id)")
    )
    op.execute(
        text("CREATE INDEX IF NOT EXISTS idx_chat_threads_project ON chat_threads (project_id)")
    )
    op.execute(
        text("CREATE INDEX IF NOT EXISTS idx_chat_memberships_user ON chat_memberships (user_id)")
    )

    # -------------------------------------------------------------------------
    # Row Level Security — tenant isolation on all 4 tables
    #
    # Follows the same pattern as other tables: company_id must match the
    # JWT-injected app.current_company_id setting. FORCE ROW LEVEL SECURITY
    # ensures table owner (appuser) is also subject to the policy.
    # -------------------------------------------------------------------------
    for table in ["chat_threads", "chat_messages", "chat_memberships", "chat_read_receipts"]:
        op.execute(text(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY"))
        op.execute(
            text(f"""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_policies
                    WHERE tablename = '{table}' AND policyname = '{table}_isolation'
                ) THEN
                    CREATE POLICY {table}_isolation ON {table}
                        USING (
                            company_id = NULLIF(current_setting('app.current_company_id', TRUE), '')::UUID
                        );
                END IF;
            END $$;
            """)
        )
        op.execute(text(f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY"))
        op.execute(text(f"GRANT SELECT, INSERT, UPDATE, DELETE ON {table} TO appuser"))


def downgrade() -> None:
    for table in ["chat_read_receipts", "chat_memberships", "chat_messages", "chat_threads"]:
        op.execute(text(f"DROP TABLE IF EXISTS {table} CASCADE"))
    op.execute(text("DROP SEQUENCE IF EXISTS chat_message_seq"))
