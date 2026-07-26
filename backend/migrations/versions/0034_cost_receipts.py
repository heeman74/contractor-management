"""cost_receipts: receipt attachments for cost entries (D-04)

Revision ID: 0034_cost_receipts
Revises: 0033_project_quotes
Create Date: 2026-07-26

Changes:
- CREATE TABLE cost_receipts — a tenant-scoped, zero-to-many receipt attachment
  on a cost_entries row (Phase 31 D-04). Upload/serve endpoints land in Plan
  31-02; this migration only creates the table + RLS, mirroring 0032's block
  for the sibling finance tables.
- ENABLE + FORCE RLS with a tenant_isolation_cost_receipts policy, plus
  GRANT SELECT/INSERT/UPDATE/DELETE TO appuser, matching 0032's pattern exactly.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0034_cost_receipts"
down_revision: str | None = "0033_project_quotes"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE cost_receipts (
            id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id     UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            version        INTEGER NOT NULL DEFAULT 1,
            created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at     TIMESTAMPTZ,
            cost_entry_id  UUID NOT NULL REFERENCES cost_entries(id) ON DELETE CASCADE,
            remote_url     TEXT,
            caption        TEXT
        )
    """)
    op.execute("CREATE INDEX ix_cost_receipts_cost_entry_id ON cost_receipts (cost_entry_id)")

    op.execute("ALTER TABLE cost_receipts ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE cost_receipts FORCE ROW LEVEL SECURITY")
    op.execute("""
        CREATE POLICY tenant_isolation_cost_receipts
        ON cost_receipts
        USING (company_id = current_setting('app.current_company_id')::uuid)
        WITH CHECK (company_id = current_setting('app.current_company_id')::uuid)
    """)
    op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON cost_receipts TO appuser")


def downgrade() -> None:
    op.execute("DROP POLICY IF EXISTS tenant_isolation_cost_receipts ON cost_receipts")
    op.execute("DROP TABLE IF EXISTS cost_receipts CASCADE")
