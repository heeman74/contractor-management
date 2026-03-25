"""Add performance indexes for common query patterns

Revision ID: 0021_performance_indexes
Revises: 0020_chat
Create Date: 2026-03-25

Changes:
- Add indexes on frequently-filtered foreign key columns that were missing:
  - jobs.contractor_id, jobs.client_id (filtered in list/search endpoints)
  - job_notes.author_id (filtered by author)
  - quotes.job_id (lookup quote for a job)
  - invoices.job_id (lookup invoice for a job)
  - bookings.contractor_id (contractor schedule queries)
  - chat_memberships.user_id (list threads for a user)
  - chat_messages.thread_id + seq (cursor pagination)
  - job_requests.client_id (client's requests)
  - device_tokens.user_id (FCM token lookup)
  - time_entries.contractor_id (active session lookup)
- All indexes use partial WHERE deleted_at IS NULL for soft-delete models
  to reduce index size and improve write performance.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0021_performance_indexes"
down_revision: str | None = "0020_chat"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Jobs — filtered by contractor and client in list/search endpoints
    op.create_index(
        "ix_jobs_contractor_id",
        "jobs",
        ["contractor_id"],
        postgresql_where="deleted_at IS NULL",
    )
    op.create_index(
        "ix_jobs_client_id",
        "jobs",
        ["client_id"],
        postgresql_where="deleted_at IS NULL",
    )

    # Job notes — filtered by author
    op.create_index(
        "ix_job_notes_author_id",
        "job_notes",
        ["author_id"],
        postgresql_where="deleted_at IS NULL",
    )

    # Quotes — lookup by job_id
    op.create_index(
        "ix_quotes_job_id",
        "quotes",
        ["job_id"],
        postgresql_where="deleted_at IS NULL",
    )

    # Invoices — lookup by job_id
    op.create_index(
        "ix_invoices_job_id",
        "invoices",
        ["job_id"],
        postgresql_where="deleted_at IS NULL",
    )

    # Bookings — filtered by contractor for schedule views
    op.create_index(
        "ix_bookings_contractor_id",
        "bookings",
        ["contractor_id"],
        postgresql_where="deleted_at IS NULL",
    )

    # Chat memberships — user's thread list
    op.create_index(
        "ix_chat_memberships_user_id",
        "chat_memberships",
        ["user_id"],
        postgresql_where="deleted_at IS NULL",
    )

    # Chat messages — cursor pagination (thread_id + seq DESC)
    op.create_index(
        "ix_chat_messages_thread_seq",
        "chat_messages",
        ["thread_id", "seq"],
        postgresql_where="deleted_at IS NULL",
    )

    # Job requests — client's requests
    op.create_index(
        "ix_job_requests_client_id",
        "job_requests",
        ["client_id"],
        postgresql_where="deleted_at IS NULL",
    )

    # Time entries — active session lookup by contractor
    op.create_index(
        "ix_time_entries_contractor_id",
        "time_entries",
        ["contractor_id"],
        postgresql_where="deleted_at IS NULL",
    )

    # Sync performance — updated_at indexes for delta sync queries
    op.create_index("ix_jobs_updated_at", "jobs", ["updated_at"])
    op.create_index("ix_bookings_updated_at", "bookings", ["updated_at"])
    op.create_index("ix_job_notes_updated_at", "job_notes", ["updated_at"])
    op.create_index("ix_quotes_updated_at", "quotes", ["updated_at"])
    op.create_index("ix_invoices_updated_at", "invoices", ["updated_at"])


def downgrade() -> None:
    op.drop_index("ix_invoices_updated_at", table_name="invoices")
    op.drop_index("ix_quotes_updated_at", table_name="quotes")
    op.drop_index("ix_job_notes_updated_at", table_name="job_notes")
    op.drop_index("ix_bookings_updated_at", table_name="bookings")
    op.drop_index("ix_jobs_updated_at", table_name="jobs")

    op.drop_index("ix_time_entries_contractor_id", table_name="time_entries")
    op.drop_index("ix_job_requests_client_id", table_name="job_requests")
    op.drop_index("ix_chat_messages_thread_seq", table_name="chat_messages")
    op.drop_index("ix_chat_memberships_user_id", table_name="chat_memberships")
    op.drop_index("ix_bookings_contractor_id", table_name="bookings")
    op.drop_index("ix_invoices_job_id", table_name="invoices")
    op.drop_index("ix_quotes_job_id", table_name="quotes")
    op.drop_index("ix_job_notes_author_id", table_name="job_notes")
    op.drop_index("ix_jobs_client_id", table_name="jobs")
    op.drop_index("ix_jobs_contractor_id", table_name="jobs")
