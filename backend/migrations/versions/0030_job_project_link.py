"""job_project_link: tie jobs to projects via nullable project_id FK

Revision ID: 0030_job_project_link
Revises: 0029_contracts_and_license
Create Date: 2026-07-24

Changes:
- ADD COLUMN jobs.project_id UUID NULL REFERENCES projects(id) ON DELETE SET NULL
  (deleting a project unlinks its jobs rather than deleting them)
- CREATE INDEX ix_jobs_project_id for project-scoped job lookups

Backward compatible — existing jobs simply have project_id NULL.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0030_job_project_link"
down_revision: str | None = "0029_contracts_and_license"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE jobs ADD COLUMN project_id UUID REFERENCES projects(id) ON DELETE SET NULL"
    )
    op.execute("CREATE INDEX ix_jobs_project_id ON jobs (project_id)")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_jobs_project_id")
    op.execute("ALTER TABLE jobs DROP COLUMN project_id")
