"""Create field workflow tables: job_notes, attachments, time_entries + GPS columns on jobs.

Revision ID: 0009
Revises: 0008
Create Date: 2026-03-11

Changes:
- Create job_notes table with RLS (company_id isolation, soft delete, version)
- Create attachments table with RLS (linked to job_notes, type check, sort order)
- Create time_entries table with RLS (clock in/out, duration, adjustment_log JSONB)
- ALTER TABLE jobs ADD COLUMN gps_latitude, gps_longitude, gps_address

CRITICAL NOTES:
- All table creation uses op.execute(text(...)) NOT op.create_table() — consistent with
  migration 0007/0008 pattern for complex DDL (RLS policies, triggers).
- set_updated_at() trigger function was created in migration 0002 — just CREATE TRIGGER here.
- RLS policy name is 'tenant_isolation' on all tables (same pattern as earlier migrations).
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. job_notes — contractor/admin notes attached to a job
    #
    # Each note has an author (user) and optional attachments (photos/PDFs).
    # body: plain-text content of the note (max 2000 chars enforced at app layer).
    # version: used for optimistic locking and sync delta tracking.
    # deleted_at: soft delete — notes are never hard-deleted.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE job_notes (
            id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id   UUID        NOT NULL REFERENCES companies(id),
            job_id       UUID        NOT NULL REFERENCES jobs(id),
            author_id    UUID        NOT NULL REFERENCES users(id),
            body         TEXT        NOT NULL,
            version      INTEGER     NOT NULL DEFAULT 1,
            created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at   TIMESTAMPTZ
        )
    """)
    )
    op.execute(text("ALTER TABLE job_notes ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE job_notes FORCE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON job_notes
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER set_job_notes_updated_at
        BEFORE UPDATE ON job_notes
        FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """)
    )

    # Indexes for job_notes
    op.execute(
        text("CREATE INDEX idx_job_notes_job_id ON job_notes (job_id) WHERE deleted_at IS NULL")
    )

    # -------------------------------------------------------------------------
    # 2. attachments — file attachments linked to a job_note
    #
    # attachment_type: photo / pdf / drawing (enforced via CHECK constraint).
    # remote_url: URL path to the file on disk (e.g. /files/attachments/{note_id}/{filename}).
    # sort_order: display ordering within a note (default 0).
    # caption: optional human-readable label for the attachment.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE attachments (
            id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id      UUID        NOT NULL REFERENCES companies(id),
            note_id         UUID        NOT NULL REFERENCES job_notes(id),
            attachment_type TEXT        NOT NULL
                            CHECK (attachment_type IN ('photo','pdf','drawing')),
            remote_url      TEXT,
            caption         TEXT,
            sort_order      INTEGER     NOT NULL DEFAULT 0,
            version         INTEGER     NOT NULL DEFAULT 1,
            created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at      TIMESTAMPTZ
        )
    """)
    )
    op.execute(text("ALTER TABLE attachments ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE attachments FORCE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON attachments
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER set_attachments_updated_at
        BEFORE UPDATE ON attachments
        FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """)
    )

    # Indexes for attachments
    op.execute(
        text(
            "CREATE INDEX idx_attachments_note_id ON attachments (note_id) "
            "WHERE deleted_at IS NULL"
        )
    )

    # -------------------------------------------------------------------------
    # 3. time_entries — contractor clock-in/clock-out sessions for a job
    #
    # clocked_in_at: when the contractor started work (required, set by client).
    # clocked_out_at: when the contractor stopped (nullable — null = active session).
    # duration_seconds: computed on clock-out (may differ from diff for break time).
    # session_status: active (clocked in) / completed (clocked out) / adjusted (admin edit).
    # adjustment_log: JSONB array of admin edits, each with {adjusted_by, reason, old_in, old_out, new_in, new_out, timestamp}.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE time_entries (
            id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id        UUID        NOT NULL REFERENCES companies(id),
            job_id            UUID        NOT NULL REFERENCES jobs(id),
            contractor_id     UUID        NOT NULL REFERENCES users(id),
            clocked_in_at     TIMESTAMPTZ NOT NULL,
            clocked_out_at    TIMESTAMPTZ,
            duration_seconds  INTEGER,
            session_status    TEXT        NOT NULL DEFAULT 'active'
                              CHECK (session_status IN ('active','completed','adjusted')),
            adjustment_log    JSONB       NOT NULL DEFAULT '[]'::jsonb,
            version           INTEGER     NOT NULL DEFAULT 1,
            created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at        TIMESTAMPTZ
        )
    """)
    )
    op.execute(text("ALTER TABLE time_entries ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE time_entries FORCE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON time_entries
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER set_time_entries_updated_at
        BEFORE UPDATE ON time_entries
        FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """)
    )

    # Indexes for time_entries
    op.execute(
        text(
            "CREATE INDEX idx_time_entries_job_id ON time_entries (job_id) "
            "WHERE deleted_at IS NULL"
        )
    )
    op.execute(
        text(
            "CREATE INDEX idx_time_entries_contractor_id ON time_entries (contractor_id) "
            "WHERE deleted_at IS NULL"
        )
    )
    # Partial index for active sessions — used to enforce one-at-a-time per contractor
    op.execute(
        text(
            "CREATE INDEX idx_time_entries_active ON time_entries (contractor_id) "
            "WHERE session_status = 'active' AND deleted_at IS NULL"
        )
    )

    # -------------------------------------------------------------------------
    # 4. GPS columns on jobs
    #
    # Added to support field technician location tracking and reverse geocoding.
    # gps_latitude / gps_longitude: decimal degrees (9 total digits, 6 decimal places).
    # gps_address: reverse-geocoded address string (may be NULL if geocoding fails).
    # -------------------------------------------------------------------------
    op.execute(text("ALTER TABLE jobs ADD COLUMN gps_latitude NUMERIC(9,6)"))
    op.execute(text("ALTER TABLE jobs ADD COLUMN gps_longitude NUMERIC(9,6)"))
    op.execute(text("ALTER TABLE jobs ADD COLUMN gps_address TEXT"))


def downgrade() -> None:
    # -------------------------------------------------------------------------
    # Reverse in dependency order (children before parents):
    # attachments -> job_notes -> (drop GPS columns from jobs)
    # time_entries is independent (no FK to job_notes)
    # -------------------------------------------------------------------------

    # Drop triggers before dropping tables
    op.execute(text("DROP TRIGGER IF EXISTS set_attachments_updated_at ON attachments"))
    op.execute(text("DROP TRIGGER IF EXISTS set_job_notes_updated_at ON job_notes"))
    op.execute(text("DROP TRIGGER IF EXISTS set_time_entries_updated_at ON time_entries"))

    # Drop RLS policies before dropping tables
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON attachments"))
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON job_notes"))
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON time_entries"))

    # Drop tables in reverse dependency order
    op.execute(text("DROP TABLE IF EXISTS attachments"))
    op.execute(text("DROP TABLE IF EXISTS job_notes"))
    op.execute(text("DROP TABLE IF EXISTS time_entries"))

    # Remove GPS columns from jobs
    op.execute(text("ALTER TABLE jobs DROP COLUMN IF EXISTS gps_latitude"))
    op.execute(text("ALTER TABLE jobs DROP COLUMN IF EXISTS gps_longitude"))
    op.execute(text("ALTER TABLE jobs DROP COLUMN IF EXISTS gps_address"))
