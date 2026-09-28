"""repair the four column defaults that were quoted twice

Revision ID: 0042_fix_overquoted_defaults
Revises: 0041_force_rls_missing_tables
Create Date: 2026-09-28

0022 declared these with an inner-quoted server_default. SQLAlchemy quotes a
plain string itself, so the inner quotes survived into the DDL and the stored
default became the literal text 'medium', apostrophes included.

Every one of them then violated its own CHECK constraint, so any INSERT that
omitted the column failed outright:

    new row for relation "site_walk_flags" violates check constraint
    "site_walk_flags_severity_check"

Elsewhere the codebase passes the bare word and is unaffected; these four
columns are the whole of it, confirmed against information_schema.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0042_fix_overquoted_defaults"
down_revision: str | None = "0041_force_rls_missing_tables"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# (table, column, intended default)
FIXES = (
    ("site_walk_flags", "severity", "medium"),
    ("site_walk_flags", "status", "open"),
    ("punch_list_items", "priority", "medium"),
    ("punch_list_items", "status", "open"),
)

_BROKEN = "'''{value}'''"


def upgrade() -> None:
    for table, column, value in FIXES:
        op.execute(f"ALTER TABLE {table} ALTER COLUMN {column} SET DEFAULT '{value}'")
    # No data repair is needed or possible. The CHECK constraint rejected the
    # quoted value, so no row was ever stored with it — and after 0041 these
    # tables FORCE row level security, so a migration-time UPDATE would fail on
    # the unset app.current_company_id anyway.


def downgrade() -> None:
    for table, column, value in FIXES:
        broken = _BROKEN.format(value=value)
        op.execute(f"ALTER TABLE {table} ALTER COLUMN {column} SET DEFAULT {broken}")
