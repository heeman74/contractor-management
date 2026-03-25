"""Create v3.0 project data model tables.

Revision ID: 0015
Revises: 0014
Create Date: 2026-03-20

Changes:
- Create trade_catalog table (company-configurable trade type reference)
- Create projects table with 6-state status machine and JSONB status_history
- Create trade_scopes table (one trade per scope, nullable contractor)
- Create tasks table with full construction task fields (materials, dependencies)
- Create task_attachments table (photo/video/document per task)
- Create user_trade_specialties table (contractor specialty join table)
- Enable RLS with tenant_isolation policy on all 6 tables
- Add set_updated_at trigger to all 6 tables
- Create indexes for all FK lookup columns
- Data migration: seed trade_catalog from Jobs.trade_type + Companies.trade_types

NOTES:
- All 6 tables use company_id FK for tenant isolation (same pattern as 0011)
- RLS policies use app.current_company_id ContextVar set by TenantMiddleware
- trade_catalog UNIQUE(company_id, name): prevents duplicate trade names per company
- user_trade_specialties UNIQUE(user_id, trade_catalog_id): prevents duplicate specialties
- ON CONFLICT DO NOTHING in data migration: idempotent if run multiple times
- Jobs.trade_type and Companies.trade_types remain for backward compatibility
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision: str = "0015"
down_revision: str | None = "0014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # trade_catalog — company-configurable reference table for trade types
    #
    # UNIQUE(company_id, name): prevents duplicate trade names per company.
    # color: hex color code for visual coding of trades (default grey).
    # Data migration below will seed this from Jobs.trade_type and Companies.trade_types.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE trade_catalog (
            id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id  UUID        NOT NULL REFERENCES companies(id),
            name        TEXT        NOT NULL,
            color       TEXT        NOT NULL DEFAULT '#9E9E9E',
            version     INTEGER     NOT NULL DEFAULT 1,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at  TIMESTAMPTZ,
            UNIQUE (company_id, name)
        )
        """)
    )

    # -------------------------------------------------------------------------
    # projects — top-level project entity with 6-state status machine
    #
    # status machine: draft -> planning -> active -> on_hold -> complete -> archived
    # Semi-automatic transitions: Draft->Planning when first scope added (service layer),
    # Planning->Active when first task started (service layer).
    # status_history: JSONB array [{status, changed_at, changed_by}] for audit trail.
    # client_id: nullable FK — reuses CRM users table.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE projects (
            id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id        UUID        NOT NULL REFERENCES companies(id),
            name              TEXT        NOT NULL,
            description       TEXT,
            address           TEXT,
            client_id         UUID        REFERENCES users(id),
            target_start_date DATE,
            target_end_date   DATE,
            status            TEXT        NOT NULL DEFAULT 'draft'
                                          CHECK (status IN (
                                            'draft','planning','active','on_hold','complete','archived'
                                          )),
            status_history    JSONB       NOT NULL DEFAULT '[]'::jsonb,
            version           INTEGER     NOT NULL DEFAULT 1,
            created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at        TIMESTAMPTZ
        )
        """)
    )

    # -------------------------------------------------------------------------
    # trade_scopes — one trade per scope on a project
    #
    # One contractor per scope. If two electricians needed, create two scopes.
    # contractor_id nullable — GC can assign later.
    # trade_catalog_id nullable — null when ad-hoc trade is used.
    # status_override: when True, GC manually set status (overrides computed value).
    # ON DELETE CASCADE: removing a project removes its scopes.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE trade_scopes (
            id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id       UUID        NOT NULL REFERENCES companies(id),
            project_id       UUID        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            trade_catalog_id UUID        REFERENCES trade_catalog(id),
            trade_name       TEXT        NOT NULL,
            trade_color      TEXT        NOT NULL DEFAULT '#9E9E9E',
            contractor_id    UUID        REFERENCES users(id),
            status           TEXT        NOT NULL DEFAULT 'not_started'
                                         CHECK (status IN (
                                           'not_started','in_progress','complete','approved'
                                         )),
            status_override  BOOLEAN     NOT NULL DEFAULT false,
            sort_order       INTEGER     NOT NULL DEFAULT 0,
            version          INTEGER     NOT NULL DEFAULT 1,
            created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at       TIMESTAMPTZ
        )
        """)
    )

    # -------------------------------------------------------------------------
    # tasks — individual work items within a trade scope
    #
    # Full construction task fields for v3.0 project management.
    # materials_needed: JSONB array [{name, quantity, unit}] — structured list.
    # depends_on: JSONB array of task IDs for intra-scope dependencies.
    # Cross-trade dependencies are a separate edge table in Phase 20.
    # Blocked status is auto-computed from unresolved depends_on (Phase 20 engine).
    # ON DELETE CASCADE: removing a scope removes its tasks.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE tasks (
            id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id       UUID        NOT NULL REFERENCES companies(id),
            trade_scope_id   UUID        NOT NULL REFERENCES trade_scopes(id) ON DELETE CASCADE,
            title            TEXT        NOT NULL,
            description      TEXT,
            status           TEXT        NOT NULL DEFAULT 'not_started'
                                         CHECK (status IN (
                                           'not_started','in_progress','complete','blocked'
                                         )),
            sort_order       INTEGER     NOT NULL DEFAULT 0,
            priority         TEXT        NOT NULL DEFAULT 'medium'
                                         CHECK (priority IN ('low','medium','high','urgent')),
            estimated_hours  NUMERIC(6,2),
            estimated_cost   NUMERIC(10,2),
            due_date         DATE,
            photo_required   BOOLEAN     NOT NULL DEFAULT false,
            assigned_to      UUID        REFERENCES users(id),
            materials_needed JSONB       NOT NULL DEFAULT '[]'::jsonb,
            depends_on       JSONB       NOT NULL DEFAULT '[]'::jsonb,
            version          INTEGER     NOT NULL DEFAULT 1,
            created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at       TIMESTAMPTZ
        )
        """)
    )

    # -------------------------------------------------------------------------
    # task_attachments — photo/video/document attachments per task
    #
    # Separate from existing `attachments` table (linked to JobNote) —
    # different attachment_type set (includes 'video'), independent lifecycle.
    # local_path: device-local path for mobile offline access.
    # ON DELETE CASCADE: removing a task removes its attachments.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE task_attachments (
            id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id      UUID        NOT NULL REFERENCES companies(id),
            task_id         UUID        NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            attachment_type TEXT        NOT NULL
                                        CHECK (attachment_type IN ('photo','video','document')),
            remote_url      TEXT,
            local_path      TEXT,
            caption         TEXT,
            sort_order      INTEGER     NOT NULL DEFAULT 0,
            version         INTEGER     NOT NULL DEFAULT 1,
            created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at      TIMESTAMPTZ
        )
        """)
    )

    # -------------------------------------------------------------------------
    # user_trade_specialties — join table for contractor trade specialties
    #
    # UNIQUE(user_id, trade_catalog_id): prevents duplicate specialty entries.
    # Not a JSONB array on User — must be queryable for contractor matching
    # (when GC assigns a scope, matching-trade contractors appear first).
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE user_trade_specialties (
            id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id       UUID        NOT NULL REFERENCES companies(id),
            user_id          UUID        NOT NULL REFERENCES users(id),
            trade_catalog_id UUID        NOT NULL REFERENCES trade_catalog(id),
            version          INTEGER     NOT NULL DEFAULT 1,
            created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at       TIMESTAMPTZ,
            UNIQUE (user_id, trade_catalog_id)
        )
        """)
    )

    # -------------------------------------------------------------------------
    # Indexes for efficient FK lookups
    # -------------------------------------------------------------------------
    op.execute(text("CREATE INDEX idx_projects_company_id ON projects (company_id)"))
    op.execute(text("CREATE INDEX idx_projects_client_id ON projects (client_id)"))
    op.execute(text("CREATE INDEX idx_projects_status ON projects (status)"))
    op.execute(text("CREATE INDEX idx_trade_catalog_company_id ON trade_catalog (company_id)"))
    op.execute(text("CREATE INDEX idx_trade_scopes_project_id ON trade_scopes (project_id)"))
    op.execute(text("CREATE INDEX idx_trade_scopes_contractor_id ON trade_scopes (contractor_id)"))
    op.execute(text("CREATE INDEX idx_tasks_trade_scope_id ON tasks (trade_scope_id)"))
    op.execute(text("CREATE INDEX idx_tasks_assigned_to ON tasks (assigned_to)"))
    op.execute(text("CREATE INDEX idx_task_attachments_task_id ON task_attachments (task_id)"))
    op.execute(
        text("CREATE INDEX idx_user_trade_specialties_user_id ON user_trade_specialties (user_id)")
    )
    op.execute(
        text(
            "CREATE INDEX idx_user_trade_specialties_trade_id ON user_trade_specialties (trade_catalog_id)"
        )
    )

    # -------------------------------------------------------------------------
    # Row Level Security — standard tenant isolation (same pattern as 0011)
    #
    # app.current_company_id is set by TenantMiddleware (tenant.py after_begin event)
    # The appuser DB role is NOBYPASSRLS — RLS policies enforce tenant isolation
    # -------------------------------------------------------------------------
    for table in [
        "trade_catalog",
        "projects",
        "trade_scopes",
        "tasks",
        "task_attachments",
        "user_trade_specialties",
    ]:
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
    # set_updated_at() function was created in migration 0002 — just create triggers
    # -------------------------------------------------------------------------
    for table in [
        "trade_catalog",
        "projects",
        "trade_scopes",
        "tasks",
        "task_attachments",
        "user_trade_specialties",
    ]:
        op.execute(
            text(f"""
            CREATE TRIGGER set_updated_at
                BEFORE UPDATE ON {table}
                FOR EACH ROW EXECUTE FUNCTION set_updated_at()
            """)
        )

    # -------------------------------------------------------------------------
    # Data migration — seed trade_catalog from existing free-text trade types
    #
    # Sources:
    #   1. jobs.trade_type: free-text string per job
    #   2. companies.trade_types: PostgreSQL ARRAY of strings
    #
    # ON CONFLICT DO NOTHING: idempotent — safe to run twice.
    # '#9E9E9E' default color: GCs can customize after migration.
    # Both sources are UNION'd and DISTINCT'd to avoid duplicate inserts.
    # Jobs.trade_type and Companies.trade_types remain (backward compat — not dropped).
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        INSERT INTO trade_catalog (id, company_id, name, color, version, created_at, updated_at)
        SELECT
            gen_random_uuid(),
            company_id,
            trade_name,
            '#9E9E9E',
            1,
            now(),
            now()
        FROM (
            SELECT DISTINCT company_id, trade_type AS trade_name
            FROM jobs
            WHERE trade_type IS NOT NULL AND trade_type != ''
            UNION
            SELECT DISTINCT id AS company_id, ut.trade_name
            FROM companies, unnest(trade_types) AS ut(trade_name)
            WHERE trade_types IS NOT NULL AND array_length(trade_types, 1) > 0
        ) AS unique_trades
        ON CONFLICT DO NOTHING
        """)
    )


def downgrade() -> None:
    # Drop triggers first (tables may not have triggers if upgrade was partial)
    for table in [
        "user_trade_specialties",
        "task_attachments",
        "tasks",
        "trade_scopes",
        "projects",
        "trade_catalog",
    ]:
        op.execute(text(f"DROP TRIGGER IF EXISTS set_updated_at ON {table}"))

    # Drop tables in reverse dependency order
    op.execute(text("DROP TABLE IF EXISTS user_trade_specialties"))
    op.execute(text("DROP TABLE IF EXISTS task_attachments"))
    op.execute(text("DROP TABLE IF EXISTS tasks"))
    op.execute(text("DROP TABLE IF EXISTS trade_scopes"))
    op.execute(text("DROP TABLE IF EXISTS projects"))
    op.execute(text("DROP TABLE IF EXISTS trade_catalog"))
