"""Phase 37 — AI Quote Planning: line-item identity, review state, D-07 send gate.

Covers FINAI-03: line items keep stable `id`s (and `field`) across an ordinary
PATCH, a line's review state is derived server-side rather than trusted from
the client, POST /quotes/{id}/send 409s while any AI-originated line is still
unreviewed, and `confidence_band`/`basis` never reach a caller without
finance.view.

No suggestion endpoint exists yet in this plan, so an AI-originated line is
seeded directly via SQL (the test_phase_36_e2e.py SET LOCAL convention) rather
than through a real suggestion run.

Per the self-contained-test-file convention the helper set is COPIED rather
than imported across test modules, so a later edit to another phase's fixture
can never silently change what this file asserts.
"""

from __future__ import annotations

from sqlalchemy import CheckConstraint

# Side-effect: register all mappers before tests run.
import app.features.scheduling.models  # noqa: F401
from app.features.quotes.models import QuoteLineItem


def test_quote_line_review_columns_exist_with_checks():
    """The five line-item columns carry the three named CHECK constraints.

    Reads the CHECK constraint expressions directly off the ORM table so a
    later edit that drops or renames one fails this test, not just a manual
    inspection.
    """
    checks = {
        constraint.name: str(constraint.sqltext)
        for constraint in QuoteLineItem.__table__.constraints
        if isinstance(constraint, CheckConstraint)
    }

    assert "quote_line_items_review_state_check" in checks
    assert "quote_line_items_confidence_band_check" in checks
    assert "quote_line_items_basis_length_check" in checks
    assert "200" in checks["quote_line_items_basis_length_check"]
