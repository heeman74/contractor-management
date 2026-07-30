"""quote line review state (Phase 37 foundation)

Revision ID: 0037_quote_line_review_state
Revises: 0036_ai_profitability_findings
Create Date: 2026-07-30

Changes:
- quote_line_items: adds `ai_origin` (server-owned provenance flag),
  `review_state` (unreviewed/accepted/edited — D-07 send gate reads this),
  `confidence_band` and `basis` (finance-gated, Phase 30 D-06 derived-cost
  fields), and `suggested_at` (when an AI suggestion run wrote this row).
- quotes: adds `ai_suggestion_payload` — the SC3 audit trail, the exact
  payload a suggestion set was validated against, written once per run.

The matching ORM columns and CHECK constraint expressions live in
app/features/quotes/models.py — both change together.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0037_quote_line_review_state"
down_revision: str | None = "0036_ai_profitability_findings"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Mirrors app.features.quotes.models.MAX_BASIS_LENGTH — the DB CHECK and the
# application constant are built from one module constant so they cannot diverge.
_MAX_BASIS_LENGTH = 200


def upgrade() -> None:
    op.execute("""
        ALTER TABLE quote_line_items
        ADD COLUMN ai_origin BOOLEAN NOT NULL DEFAULT false,
        ADD COLUMN review_state TEXT NOT NULL DEFAULT 'unreviewed',
        ADD COLUMN confidence_band TEXT NULL,
        ADD COLUMN basis TEXT NULL,
        ADD COLUMN suggested_at TIMESTAMPTZ NULL
    """)

    op.create_check_constraint(
        "quote_line_items_review_state_check",
        "quote_line_items",
        "review_state IN ('unreviewed','accepted','edited')",
    )
    op.create_check_constraint(
        "quote_line_items_confidence_band_check",
        "quote_line_items",
        "confidence_band IS NULL OR confidence_band IN ('high','medium','low')",
    )
    op.create_check_constraint(
        "quote_line_items_basis_length_check",
        "quote_line_items",
        f"basis IS NULL OR char_length(basis) <= {_MAX_BASIS_LENGTH}",
    )

    op.execute("ALTER TABLE quotes ADD COLUMN ai_suggestion_payload JSONB NULL")


def downgrade() -> None:
    op.drop_constraint("quote_line_items_basis_length_check", "quote_line_items")
    op.drop_constraint("quote_line_items_confidence_band_check", "quote_line_items")
    op.drop_constraint("quote_line_items_review_state_check", "quote_line_items")

    op.execute("""
        ALTER TABLE quote_line_items
        DROP COLUMN ai_origin,
        DROP COLUMN review_state,
        DROP COLUMN confidence_band,
        DROP COLUMN basis,
        DROP COLUMN suggested_at
    """)

    op.execute("ALTER TABLE quotes DROP COLUMN ai_suggestion_payload")
