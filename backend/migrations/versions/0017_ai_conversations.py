"""Phase 21 AI module: ai_conversations, ai_messages, ai_token_usage tables.

Revision ID: 0017
Revises: 0016
Create Date: 2026-03-23

Changes:
- Create ai_conversations table (chat sessions for project intake / contractor interview)
- Create ai_messages table (individual messages within a conversation)
- Create ai_token_usage table (per-call token counts for analytics)
- Enable RLS and add set_updated_at triggers on ai_conversations and ai_messages
- Create indexes for efficient FK lookups

NOTES:
- ai_messages uses ON DELETE CASCADE from ai_conversations
- ai_token_usage does NOT cascade — usage records are immutable analytics data
- CHECK constraints enforce conv_type IN ('intake','interview') and role IN ('user','assistant')
- UNIQUE(conversation_id, sequence_num) prevents duplicate message ordering
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision: str = "0017"
down_revision: str | None = "0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # ai_conversations — top-level chat session entity
    #
    # conv_type: intake (GC describes project) or interview (contractor interview)
    # status: active -> complete or abandoned
    # project_id: SET NULL on project delete (conversation history preserved)
    # scope_id: SET NULL on trade scope delete
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE ai_conversations (
            id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id  UUID        NOT NULL REFERENCES companies(id),
            project_id  UUID        REFERENCES projects(id) ON DELETE SET NULL,
            scope_id    UUID        REFERENCES trade_scopes(id) ON DELETE SET NULL,
            user_id     UUID        NOT NULL REFERENCES users(id),
            conv_type   TEXT        NOT NULL CHECK (conv_type IN ('intake','interview')),
            status      TEXT        NOT NULL DEFAULT 'active'
                                    CHECK (status IN ('active','complete','abandoned')),
            version     INTEGER     NOT NULL DEFAULT 1,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at  TIMESTAMPTZ
        )
        """)
    )

    # -------------------------------------------------------------------------
    # ai_messages — individual messages in a conversation
    #
    # content_json: Claude API content array stored verbatim as JSONB.
    #   User messages: [{"type":"text","text":"..."}]
    #   Assistant messages: full content array including tool_use blocks
    #   Tool results: [{"type":"tool_result","tool_use_id":"...","content":"..."}]
    # sequence_num: 0-indexed ordering; UNIQUE with conversation_id
    # ON DELETE CASCADE: removing a conversation removes all its messages
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE ai_messages (
            id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id      UUID        NOT NULL REFERENCES companies(id),
            conversation_id UUID        NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
            role            TEXT        NOT NULL CHECK (role IN ('user','assistant')),
            content_json    JSONB       NOT NULL,
            sequence_num    INTEGER     NOT NULL,
            version         INTEGER     NOT NULL DEFAULT 1,
            created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at      TIMESTAMPTZ,
            UNIQUE (conversation_id, sequence_num)
        )
        """)
    )

    # -------------------------------------------------------------------------
    # ai_token_usage — immutable token analytics records
    #
    # No CASCADE on conversation_id — usage records persist for cost tracking
    # even if conversation is soft-deleted.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE ai_token_usage (
            id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id      UUID        NOT NULL REFERENCES companies(id),
            conversation_id UUID        NOT NULL REFERENCES ai_conversations(id),
            user_id         UUID        NOT NULL REFERENCES users(id),
            model           TEXT        NOT NULL,
            input_tokens    INTEGER     NOT NULL,
            output_tokens   INTEGER     NOT NULL,
            version         INTEGER     NOT NULL DEFAULT 1,
            created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at      TIMESTAMPTZ
        )
        """)
    )

    # -------------------------------------------------------------------------
    # Row Level Security — standard tenant isolation (same pattern as 0016)
    # -------------------------------------------------------------------------
    for table in ["ai_conversations", "ai_messages", "ai_token_usage"]:
        op.execute(text(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY"))
        op.execute(
            text(f"""
            CREATE POLICY tenant_isolation ON {table}
                USING (
                    company_id = NULLIF(current_setting('app.current_company_id', TRUE), '')::UUID
                )
            """)
        )
        op.execute(text(f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY"))

    # -------------------------------------------------------------------------
    # set_updated_at triggers — auto-update updated_at on every row mutation
    # set_updated_at() function was created in migration 0002
    # -------------------------------------------------------------------------
    for table in ["ai_conversations", "ai_messages"]:
        op.execute(
            text(f"""
            CREATE TRIGGER set_updated_at
                BEFORE UPDATE ON {table}
                FOR EACH ROW EXECUTE FUNCTION set_updated_at()
            """)
        )

    # -------------------------------------------------------------------------
    # Indexes for efficient FK lookups
    # -------------------------------------------------------------------------
    op.execute(
        text("CREATE INDEX ix_ai_conversations_project_id ON ai_conversations (project_id)")
    )
    op.execute(
        text("CREATE INDEX ix_ai_conversations_scope_id ON ai_conversations (scope_id)")
    )
    op.execute(
        text("CREATE INDEX ix_ai_messages_conversation_id ON ai_messages (conversation_id)")
    )


def downgrade() -> None:
    # Drop triggers first
    for table in ["ai_messages", "ai_conversations"]:
        op.execute(text(f"DROP TRIGGER IF EXISTS set_updated_at ON {table}"))

    # Drop indexes
    op.execute(text("DROP INDEX IF EXISTS ix_ai_messages_conversation_id"))
    op.execute(text("DROP INDEX IF EXISTS ix_ai_conversations_scope_id"))
    op.execute(text("DROP INDEX IF EXISTS ix_ai_conversations_project_id"))

    # Drop tables in reverse dependency order
    op.execute(text("DROP TABLE IF EXISTS ai_token_usage"))
    op.execute(text("DROP TABLE IF EXISTS ai_messages"))
    op.execute(text("DROP TABLE IF EXISTS ai_conversations"))
