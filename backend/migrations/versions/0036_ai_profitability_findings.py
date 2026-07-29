"""ai profitability findings (Phase 36 foundation)

Revision ID: 0036_ai_profitability_findings
Revises: 0035_budget_alerts_quote_chain
Create Date: 2026-07-29

Changes:
- dashboard_alerts: expand the alert_type CHECK constraint with 'ai_profitability'
  so AI profitability findings can publish a dashboard alert. The matching ORM
  CheckConstraint literal lives in app/features/dashboard/models.py and the
  constant in app/features/dashboard/alert_types.py — all three change together.
- ai_profitability_findings: one row per published AI profitability finding, with
  the SC3 audit trail in `payload` (the exact aggregates the narrative text was
  grounded against).
- ux_ai_profitability_findings_open: partial unique index on (company_id,
  fingerprint) restricted to open rows — this is what makes the nightly re-run an
  idempotent upsert, and what lets a resolved finding recur as a fresh row.
- Three length CHECKs (alert_summary/corrective_action <= 280, narrative <= 600):
  the DB half of the UI-SPEC length contract. Over-length text is REJECTED, never
  silently truncated.
- RLS: ENABLE + FORCE + tenant_isolation policy + appuser grant (the 0032 block).
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0036_ai_profitability_findings"
down_revision: str | None = "0035_budget_alerts_quote_chain"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("ALTER TABLE dashboard_alerts DROP CONSTRAINT dashboard_alerts_alert_type_check")
    op.execute("""
        ALTER TABLE dashboard_alerts
        ADD CONSTRAINT dashboard_alerts_alert_type_check
        CHECK (alert_type IN (
            'schedule_slip','rescheduling_suggestion','dependency_risk',
            'budget_warning','budget_overrun','ai_profitability'
        ))
    """)

    op.execute("""
        CREATE TABLE ai_profitability_findings (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            version INTEGER NOT NULL DEFAULT 1,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at TIMESTAMPTZ,
            company_id UUID NOT NULL REFERENCES companies(id),
            project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            signal TEXT NOT NULL,
            severity_band TEXT NOT NULL,
            fingerprint TEXT NOT NULL,
            narrative TEXT NOT NULL,
            corrective_action TEXT NOT NULL,
            alert_summary TEXT NOT NULL,
            revenue_basis TEXT NOT NULL,
            labor_included BOOLEAN NOT NULL DEFAULT false,
            payload JSONB NOT NULL,
            dashboard_alert_id UUID REFERENCES dashboard_alerts(id) ON DELETE SET NULL,
            alerted_at TIMESTAMPTZ,
            resolved_at TIMESTAMPTZ,
            found_on DATE NOT NULL,
            last_confirmed_on DATE NOT NULL,
            CONSTRAINT ai_profitability_findings_signal_check
                CHECK (signal IN ('negative_margin','quote_gap','margin_decline')),
            CONSTRAINT ai_profitability_findings_band_check
                CHECK (severity_band IN ('warning','critical')),
            CONSTRAINT ai_profitability_findings_alert_summary_length_check
                CHECK (char_length(alert_summary) <= 280),
            CONSTRAINT ai_profitability_findings_action_length_check
                CHECK (char_length(corrective_action) <= 280),
            CONSTRAINT ai_profitability_findings_narrative_length_check
                CHECK (char_length(narrative) <= 600)
        )
    """)

    op.execute("""
        CREATE UNIQUE INDEX ux_ai_profitability_findings_open
        ON ai_profitability_findings (company_id, fingerprint)
        WHERE deleted_at IS NULL AND resolved_at IS NULL
    """)
    op.execute("""
        CREATE INDEX ix_ai_profitability_findings_company_id
        ON ai_profitability_findings (company_id)
    """)
    op.execute("""
        CREATE INDEX ix_ai_profitability_findings_project_id
        ON ai_profitability_findings (project_id)
    """)
    op.execute("""
        CREATE INDEX ix_ai_profitability_findings_latest
        ON ai_profitability_findings (company_id, project_id, created_at DESC)
    """)

    op.execute("ALTER TABLE ai_profitability_findings ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE ai_profitability_findings FORCE ROW LEVEL SECURITY")
    op.execute("""
        CREATE POLICY tenant_isolation_ai_profitability_findings
        ON ai_profitability_findings
        USING (company_id = current_setting('app.current_company_id')::uuid)
    """)
    op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ai_profitability_findings TO appuser")


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS ai_profitability_findings")

    op.execute("ALTER TABLE dashboard_alerts DROP CONSTRAINT dashboard_alerts_alert_type_check")
    op.execute("""
        ALTER TABLE dashboard_alerts
        ADD CONSTRAINT dashboard_alerts_alert_type_check
        CHECK (alert_type IN (
            'schedule_slip','rescheduling_suggestion','dependency_risk',
            'budget_warning','budget_overrun'
        ))
    """)
