"""force row level security on every table that only enabled it

Revision ID: 0041_force_rls_missing_tables
Revises: 0040_password_reset_tokens
Create Date: 2026-09-28

ENABLE ROW LEVEL SECURITY does not apply policies to the table's owner. The
app connects as the same role that runs migrations, so it owns every table:
on a table that is merely ENABLEd, tenant_isolation is skipped and rows from
every company are visible. Verified on a live database — two rows under
different company_ids, the app role scoped to one company read both; after
FORCE it read one.

Most tables already pair ENABLE with FORCE, but the set that does not has
drifted between databases (the dev and test databases were each missing a
different pair). So this repairs whatever is unforced at migration time
rather than naming tables, which also covers databases we cannot inspect
from here, such as production.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0041_force_rls_missing_tables"
down_revision: str | None = "0040_password_reset_tokens"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        DO $$
        DECLARE target record;
        BEGIN
            FOR target IN
                SELECT c.relname
                FROM pg_class c
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public'
                  AND c.relkind = 'r'
                  AND c.relrowsecurity
                  AND NOT c.relforcerowsecurity
            LOOP
                EXECUTE format(
                    'ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', target.relname
                );
            END LOOP;
        END $$;
        """
    )


def downgrade() -> None:
    """Deliberately not reversed.

    The pre-upgrade state was a tenant-isolation hole, and it differed per
    database, so there is no correct set of tables to un-force.
    """
