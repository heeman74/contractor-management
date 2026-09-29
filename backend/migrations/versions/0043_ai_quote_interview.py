"""ai quote interview: new conversation type and an ungrounded confidence band

Revision ID: 0043_ai_quote_interview
Revises: 0042_fix_overquoted_defaults
Create Date: 2026-09-29

Two CHECK constraints widen to admit the AI quote interview:

- ``ai_conversations.conv_type`` gains ``quote_interview``, a third kind
  alongside intake and interview.
- ``quote_line_items.confidence_band`` gains ``rough``.

``rough`` is deliberately not a fourth rung below ``low``. high/medium/low are
computed from comparable count and spread (Phase 37 D-05); ``rough`` means no
comparables existed and the figure is the model's own estimate. Keeping it a
separate value lets the UI and any future send policy distinguish "weakly
grounded" from "not grounded at all", which collapsing it into ``low`` would
destroy.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0043_ai_quote_interview"
down_revision: str | None = "0042_fix_overquoted_defaults"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("ALTER TABLE ai_conversations DROP CONSTRAINT ai_conversations_conv_type_check")
    op.execute(
        "ALTER TABLE ai_conversations ADD CONSTRAINT ai_conversations_conv_type_check "
        "CHECK (conv_type IN ('intake','interview','quote_interview'))"
    )
    op.execute(
        "ALTER TABLE quote_line_items DROP CONSTRAINT quote_line_items_confidence_band_check"
    )
    op.execute(
        "ALTER TABLE quote_line_items ADD CONSTRAINT quote_line_items_confidence_band_check "
        "CHECK (confidence_band IS NULL OR confidence_band IN ('high','medium','low','rough'))"
    )


def downgrade() -> None:
    # Rows carrying the widened values would violate the narrowed constraint, so
    # retire them first rather than letting the ALTER fail. A rough line loses
    # its band and reads as ungraded, which is the closest honest equivalent.
    op.execute("UPDATE quote_line_items SET confidence_band = NULL WHERE confidence_band = 'rough'")
    op.execute(
        "UPDATE ai_conversations SET status = 'abandoned' WHERE conv_type = 'quote_interview'"
    )
    op.execute("DELETE FROM ai_conversations WHERE conv_type = 'quote_interview'")
    op.execute(
        "ALTER TABLE quote_line_items DROP CONSTRAINT quote_line_items_confidence_band_check"
    )
    op.execute(
        "ALTER TABLE quote_line_items ADD CONSTRAINT quote_line_items_confidence_band_check "
        "CHECK (confidence_band IS NULL OR confidence_band IN ('high','medium','low'))"
    )
    op.execute("ALTER TABLE ai_conversations DROP CONSTRAINT ai_conversations_conv_type_check")
    op.execute(
        "ALTER TABLE ai_conversations ADD CONSTRAINT ai_conversations_conv_type_check "
        "CHECK (conv_type IN ('intake','interview'))"
    )
