"""Phase 20 dependency engine: task_dependencies, project_zones, zone_id/start_date on tasks.

Revision ID: 0016
Revises: 0015
Create Date: 2026-03-22

Changes:
- Create project_zones table (named spatial zones within a project)
- Create task_dependencies table (edge table for task-to-task dependency links)
- ALTER TABLE tasks ADD COLUMN zone_id (FK to project_zones, SET NULL on delete)
- ALTER TABLE tasks ADD COLUMN start_date DATE
- Migrate existing depends_on JSONB data to task_dependencies rows (FS type)
- ALTER TABLE tasks DROP COLUMN depends_on
- Enable RLS and add set_updated_at triggers on new tables
- Create indexes for all FK lookup columns

NOTES:
- project_zones must be created before tasks.zone_id FK can be added
- task_dependencies must be truncated before tasks in the clean_tables fixture
- depends_on migration: for each task where depends_on != '[]', create FS edges
- ON DELETE CASCADE on task_dependencies.predecessor/successor FKs
- ON DELETE SET NULL on tasks.zone_id FK
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision: str = "0016"
down_revision: str | None = "0015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # project_zones — named spatial zones within a project
    #
    # Used for conflict detection: two tasks in the same zone on the same
    # day from different trade scopes = conflict.
    # UNIQUE(project_id, name): prevents duplicate zone names per project.
    # ON DELETE CASCADE: removing a project removes its zones.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE project_zones (
            id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id  UUID        NOT NULL REFERENCES companies(id),
            project_id  UUID        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            name        TEXT        NOT NULL,
            version     INTEGER     NOT NULL DEFAULT 1,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at  TIMESTAMPTZ,
            UNIQUE (project_id, name)
        )
        """)
    )

    # -------------------------------------------------------------------------
    # task_dependencies — edge table for task-to-task dependency links
    #
    # dependency_type: FS (finish-to-start) | SS (start-to-start) |
    #                  FF (finish-to-finish) | SE (start-to-end)
    # lag_days: positive = delay (lag), negative = overlap (lead)
    # UNIQUE(predecessor_task_id, successor_task_id): one edge per pair
    # Self-loop prevented by CHECK constraint
    # ON DELETE CASCADE: removing a task removes its dependency edges
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE task_dependencies (
            id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id           UUID        NOT NULL REFERENCES companies(id),
            predecessor_task_id  UUID        NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            successor_task_id    UUID        NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            dependency_type      TEXT        NOT NULL DEFAULT 'FS'
                                             CHECK (dependency_type IN ('FS','SS','FF','SE')),
            lag_days             INTEGER     NOT NULL DEFAULT 0,
            version              INTEGER     NOT NULL DEFAULT 1,
            created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at           TIMESTAMPTZ,
            UNIQUE (predecessor_task_id, successor_task_id),
            CHECK (predecessor_task_id != successor_task_id)
        )
        """)
    )

    # -------------------------------------------------------------------------
    # Add zone_id and start_date columns to tasks
    #
    # zone_id: nullable FK to project_zones — SET NULL on zone deletion
    # start_date: nullable DATE — task start date for conflict detection
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        ALTER TABLE tasks
            ADD COLUMN zone_id    UUID REFERENCES project_zones(id) ON DELETE SET NULL,
            ADD COLUMN start_date DATE
        """)
    )

    # -------------------------------------------------------------------------
    # Migrate existing depends_on JSONB data to task_dependencies rows
    #
    # For each task where depends_on is not empty, create FS edges:
    #   predecessor = each depends_on ID, successor = task.id
    # Uses the same company_id as the task.
    # Skips self-loops (predecessor = successor) as they violate CHECK.
    # Skips non-UUID values in the depends_on array silently.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        INSERT INTO task_dependencies (
            id, company_id, predecessor_task_id, successor_task_id,
            dependency_type, lag_days, version, created_at, updated_at
        )
        SELECT
            gen_random_uuid(),
            t.company_id,
            dep_id::UUID,
            t.id,
            'FS',
            0,
            1,
            now(),
            now()
        FROM tasks t,
             jsonb_array_elements_text(t.depends_on) AS dep_id
        WHERE t.depends_on IS NOT NULL
          AND t.depends_on != '[]'::jsonb
          AND dep_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
          AND dep_id::UUID != t.id
          AND EXISTS (SELECT 1 FROM tasks t2 WHERE t2.id = dep_id::UUID)
        ON CONFLICT DO NOTHING
        """)
    )

    # -------------------------------------------------------------------------
    # Drop depends_on column from tasks
    # The column has been fully migrated to task_dependencies rows above.
    # -------------------------------------------------------------------------
    op.execute(text("ALTER TABLE tasks DROP COLUMN depends_on"))

    # -------------------------------------------------------------------------
    # Row Level Security — standard tenant isolation (same pattern as 0015)
    # -------------------------------------------------------------------------
    for table in ["project_zones", "task_dependencies"]:
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
    for table in ["project_zones", "task_dependencies"]:
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
        text(
            "CREATE INDEX idx_task_dependencies_predecessor ON task_dependencies (predecessor_task_id)"
        )
    )
    op.execute(
        text(
            "CREATE INDEX idx_task_dependencies_successor ON task_dependencies (successor_task_id)"
        )
    )
    op.execute(text("CREATE INDEX idx_project_zones_project_id ON project_zones (project_id)"))
    op.execute(text("CREATE INDEX idx_tasks_zone_id ON tasks (zone_id)"))


def downgrade() -> None:
    # Drop triggers first
    for table in ["task_dependencies", "project_zones"]:
        op.execute(text(f"DROP TRIGGER IF EXISTS set_updated_at ON {table}"))

    # Re-add depends_on before dropping task_dependencies (restore migration)
    op.execute(text("ALTER TABLE tasks ADD COLUMN depends_on JSONB NOT NULL DEFAULT '[]'::jsonb"))

    # Restore depends_on data from task_dependencies (FS edges only)
    op.execute(
        text("""
        UPDATE tasks t
        SET depends_on = (
            SELECT jsonb_agg(td.predecessor_task_id::TEXT)
            FROM task_dependencies td
            WHERE td.successor_task_id = t.id
              AND td.dependency_type = 'FS'
              AND td.deleted_at IS NULL
        )
        WHERE EXISTS (
            SELECT 1 FROM task_dependencies td
            WHERE td.successor_task_id = t.id
              AND td.dependency_type = 'FS'
              AND td.deleted_at IS NULL
        )
        """)
    )

    # Drop indexes
    op.execute(text("DROP INDEX IF EXISTS idx_tasks_zone_id"))
    op.execute(text("DROP INDEX IF EXISTS idx_project_zones_project_id"))
    op.execute(text("DROP INDEX IF EXISTS idx_task_dependencies_successor"))
    op.execute(text("DROP INDEX IF EXISTS idx_task_dependencies_predecessor"))

    # Drop tables in reverse dependency order
    op.execute(text("DROP TABLE IF EXISTS task_dependencies"))

    # Drop zone_id before dropping project_zones
    op.execute(text("ALTER TABLE tasks DROP COLUMN IF EXISTS zone_id"))
    op.execute(text("ALTER TABLE tasks DROP COLUMN IF EXISTS start_date"))

    op.execute(text("DROP TABLE IF EXISTS project_zones"))
