"""job_manager: assign a project manager to a job via nullable manager_id FK

Revision ID: 0031_job_manager
Revises: 0030_job_project_link
Create Date: 2026-07-24

Changes:
- ADD COLUMN jobs.manager_id UUID NULL REFERENCES users(id) ON DELETE SET NULL
  (a job's assigned project manager, alongside the existing contractor_id)
- CREATE INDEX ix_jobs_manager_id for manager-scoped job lookups

Backward compatible — existing jobs simply have manager_id NULL.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0031_job_manager"
down_revision: str | None = "0030_job_project_link"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE jobs ADD COLUMN manager_id UUID REFERENCES users(id) ON DELETE SET NULL"
    )
    op.execute("CREATE INDEX ix_jobs_manager_id ON jobs (manager_id)")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_jobs_manager_id")
    op.execute("ALTER TABLE jobs DROP COLUMN manager_id")
