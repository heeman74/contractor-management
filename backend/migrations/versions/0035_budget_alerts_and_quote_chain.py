"""budget alerts and quote revision chain (Phase 34 foundation)

Revision ID: 0035_budget_alerts_quote_chain
Revises: 0034_cost_receipts
Create Date: 2026-07-28

Changes:
- dashboard_alerts: expand the alert_type CHECK constraint with the two budget
  alert types (budget_warning, budget_overrun) — unknown types stay rejected.
- budgets: add warning_fired_at / overrun_fired_at threshold-state columns
  (exactly-once firing per D-01; NULL = not fired, raising the total re-arms
  both per D-03).
- budgets: CHECK (total > 0) — D-10 allows any positive amount; a zero total
  would make percent-used undefined. The table is empty (Phase 30 shipped it
  dormant with no CRUD endpoints), so no backfill is possible or needed.
- budgets: partial unique indexes guaranteeing one active budget per project
  anchor and per trade-scope anchor (RESEARCH Open Question 2); the plan 34-02
  service returns a friendly 409, these indexes are the hard guarantee.
- quotes: revised_from_quote_id — parent pointer of a revision chain (BUDG-04),
  plus a lookup index.

No RLS or policy changes — the existing tenant_isolation_budgets /
tenant_isolation_quotes policies already cover the new columns.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0035_budget_alerts_quote_chain"
down_revision: str | None = "0034_cost_receipts"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("ALTER TABLE dashboard_alerts DROP CONSTRAINT dashboard_alerts_alert_type_check")
    op.execute("""
        ALTER TABLE dashboard_alerts
        ADD CONSTRAINT dashboard_alerts_alert_type_check
        CHECK (alert_type IN (
            'schedule_slip','rescheduling_suggestion','dependency_risk',
            'budget_warning','budget_overrun'
        ))
    """)

    op.execute("""
        ALTER TABLE budgets
        ADD COLUMN warning_fired_at TIMESTAMPTZ,
        ADD COLUMN overrun_fired_at TIMESTAMPTZ
    """)
    op.execute("ALTER TABLE budgets ADD CONSTRAINT budgets_total_positive_check CHECK (total > 0)")
    op.execute("""
        CREATE UNIQUE INDEX ux_budgets_active_project
        ON budgets (company_id, project_id)
        WHERE deleted_at IS NULL AND project_id IS NOT NULL
    """)
    op.execute("""
        CREATE UNIQUE INDEX ux_budgets_active_trade_scope
        ON budgets (company_id, trade_scope_id)
        WHERE deleted_at IS NULL AND trade_scope_id IS NOT NULL
    """)

    op.execute("""
        ALTER TABLE quotes
        ADD COLUMN revised_from_quote_id UUID REFERENCES quotes(id) ON DELETE SET NULL
    """)
    op.execute("CREATE INDEX ix_quotes_revised_from_quote_id ON quotes (revised_from_quote_id)")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_quotes_revised_from_quote_id")
    op.execute("ALTER TABLE quotes DROP COLUMN IF EXISTS revised_from_quote_id")

    op.execute("DROP INDEX IF EXISTS ux_budgets_active_trade_scope")
    op.execute("DROP INDEX IF EXISTS ux_budgets_active_project")
    op.execute("ALTER TABLE budgets DROP CONSTRAINT IF EXISTS budgets_total_positive_check")
    op.execute("""
        ALTER TABLE budgets
        DROP COLUMN IF EXISTS overrun_fired_at,
        DROP COLUMN IF EXISTS warning_fired_at
    """)

    op.execute("ALTER TABLE dashboard_alerts DROP CONSTRAINT dashboard_alerts_alert_type_check")
    op.execute("""
        ALTER TABLE dashboard_alerts
        ADD CONSTRAINT dashboard_alerts_alert_type_check
        CHECK (alert_type IN ('schedule_slip','rescheduling_suggestion','dependency_risk'))
    """)
