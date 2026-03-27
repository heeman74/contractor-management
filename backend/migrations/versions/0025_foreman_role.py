"""Foreman role: project_assignments and project_status_updates tables with RLS

Revision ID: 0025_foreman_role
Revises: 0024_ai_checklists_and_alerts
Create Date: 2026-03-26

Changes:
- CREATE TABLE project_assignments — foreman-to-project assignment mapping
- CREATE TABLE project_status_updates — daily site status reports by foremen
- RLS policies on both tables (tenant isolation via app.current_company_id)
- Partial unique index on project_assignments for active (non-deleted) records
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

# revision identifiers, used by Alembic.
revision: str = "0025_foreman_role"
down_revision: str | None = "0024_ai_checklists_and_alerts"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -----------------------------------------------------------------------
    # 1. CREATE TABLE project_assignments
    # -----------------------------------------------------------------------
    op.execute("""
        CREATE TABLE project_assignments (
            id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id  UUID NOT NULL REFERENCES companies(id),
            project_id  UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            role        TEXT NOT NULL CHECK (role IN ('foreman', 'lead', 'inspector')),
            assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            version     INTEGER NOT NULL DEFAULT 1,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at  TIMESTAMPTZ
        )
    """)

    # Partial unique index: one active assignment per (company, project, user, role)
    op.execute("""
        CREATE UNIQUE INDEX uq_project_assignments_active
        ON project_assignments (company_id, project_id, user_id, role)
        WHERE deleted_at IS NULL
    """)

    # RLS for project_assignments
    op.execute("ALTER TABLE project_assignments ENABLE ROW LEVEL SECURITY")
    op.execute("""
        CREATE POLICY project_assignments_tenant_isolation
        ON project_assignments
        USING (company_id = current_setting('app.current_company_id')::uuid)
    """)

    # -----------------------------------------------------------------------
    # 2. CREATE TABLE project_status_updates
    # -----------------------------------------------------------------------
    op.execute("""
        CREATE TABLE project_status_updates (
            id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id          UUID NOT NULL REFERENCES companies(id),
            project_id          UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            author_id           UUID NOT NULL REFERENCES users(id),
            status_text         TEXT NOT NULL,
            weather_conditions  TEXT,
            workers_on_site     INTEGER,
            safety_incidents    INTEGER NOT NULL DEFAULT 0,
            blockers            TEXT,
            photos              JSONB NOT NULL DEFAULT '[]'::jsonb,
            report_date         DATE NOT NULL DEFAULT CURRENT_DATE,
            version             INTEGER NOT NULL DEFAULT 1,
            created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at          TIMESTAMPTZ
        )
    """)

    # Index for efficient queries by project + date
    op.execute("""
        CREATE INDEX ix_project_status_updates_project_date
        ON project_status_updates (project_id, report_date DESC)
    """)

    # RLS for project_status_updates
    op.execute("ALTER TABLE project_status_updates ENABLE ROW LEVEL SECURITY")
    op.execute("""
        CREATE POLICY project_status_updates_tenant_isolation
        ON project_status_updates
        USING (company_id = current_setting('app.current_company_id')::uuid)
    """)


def downgrade() -> None:
    # Drop tables
    op.execute("DROP TABLE IF EXISTS project_status_updates CASCADE")
    op.execute("DROP TABLE IF EXISTS project_assignments CASCADE")

