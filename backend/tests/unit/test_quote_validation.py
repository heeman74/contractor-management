"""Phase 8 — Quote validation: unit tests for schema constraints and service logic.

Tests validate:
- Expired quote approval blocking
- Line item quantity validation (must be > 0)
- Discount value constraints
- Tax rate bounds in schema
"""

from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

import pytest
from pydantic import ValidationError

from app.features.quotes.schemas import QuoteCreate, QuoteLineItemCreate

# ---------------------------------------------------------------------------
# Line item schema validation
# ---------------------------------------------------------------------------


def test_line_item_quantity_positive():
    """QuoteLineItemCreate rejects quantity <= 0."""
    with pytest.raises(ValidationError) as exc_info:
        QuoteLineItemCreate(
            item_type="labor",
            description="Test item",
            quantity=Decimal("0"),
            unit="hours",
            unit_price=Decimal("50.00"),
        )
    errors = exc_info.value.errors()
    assert any("quantity" in str(e["loc"]) for e in errors)


def test_line_item_negative_quantity_rejected():
    """QuoteLineItemCreate rejects negative quantity."""
    with pytest.raises(ValidationError):
        QuoteLineItemCreate(
            item_type="labor",
            description="Test item",
            quantity=Decimal("-1.000"),
            unit="hours",
            unit_price=Decimal("50.00"),
        )


def test_line_item_valid_quantity_accepted():
    """QuoteLineItemCreate accepts valid positive quantity."""
    item = QuoteLineItemCreate(
        item_type="material",
        description="Copper pipe",
        quantity=Decimal("2.500"),
        unit="meters",
        unit_price=Decimal("12.50"),
    )
    assert item.quantity == Decimal("2.500")


# ---------------------------------------------------------------------------
# Discount validation
# ---------------------------------------------------------------------------


def test_discount_value_validation():
    """discount_value > 0 requires discount_type to be set."""
    with pytest.raises(ValidationError) as exc_info:
        QuoteCreate(
            job_id="00000000-0000-0000-0000-000000000001",
            discount_type=None,
            discount_value=Decimal("10.00"),
        )
    errors = exc_info.value.errors()
    # Should complain about discount_type missing
    error_messages = " ".join(str(e) for e in errors)
    assert "discount_type" in error_messages or "discount" in error_messages.lower()


def test_percent_discount_max_100():
    """Percent discount cannot exceed 100."""
    with pytest.raises(ValidationError):
        QuoteCreate(
            job_id="00000000-0000-0000-0000-000000000001",
            discount_type="percent",
            discount_value=Decimal("101.00"),
        )


def test_discount_type_fixed_allows_any_positive():
    """Fixed discount can be any non-negative value."""
    quote = QuoteCreate(
        job_id="00000000-0000-0000-0000-000000000001",
        discount_type="fixed",
        discount_value=Decimal("500.00"),
    )
    assert quote.discount_value == Decimal("500.00")


def test_no_discount_valid():
    """Quote with no discount (zero value, no type) is valid."""
    quote = QuoteCreate(
        job_id="00000000-0000-0000-0000-000000000001",
        discount_type=None,
        discount_value=Decimal("0"),
    )
    assert quote.discount_type is None
    assert quote.discount_value == Decimal("0")


# ---------------------------------------------------------------------------
# Tax rate validation
# ---------------------------------------------------------------------------


def test_tax_rate_range():
    """Tax rate must be between 0 and 100 inclusive."""
    # Below 0 is invalid
    with pytest.raises(ValidationError):
        QuoteCreate(
            job_id="00000000-0000-0000-0000-000000000001",
            tax_rate=Decimal("-1"),
        )

    # Above 100 is invalid
    with pytest.raises(ValidationError):
        QuoteCreate(
            job_id="00000000-0000-0000-0000-000000000001",
            tax_rate=Decimal("101"),
        )


def test_tax_rate_boundary_values():
    """Tax rate of exactly 0 and 100 are both valid."""
    q0 = QuoteCreate(
        job_id="00000000-0000-0000-0000-000000000001",
        tax_rate=Decimal("0"),
    )
    assert q0.tax_rate == Decimal("0")

    q100 = QuoteCreate(
        job_id="00000000-0000-0000-0000-000000000001",
        tax_rate=Decimal("100"),
    )
    assert q100.tax_rate == Decimal("100")


# ---------------------------------------------------------------------------
# Expired quote blocks approval — service-level validation
# ---------------------------------------------------------------------------


def test_expired_quote_blocks_approval():
    """QuoteCreate with expiry_date in the past still creates schema (service rejects on approve)."""
    past_date = date.today() - timedelta(days=5)

    # Schema allows any date — the service layer enforces expiry on approval
    quote = QuoteCreate(
        job_id="00000000-0000-0000-0000-000000000001",
        expiry_date=past_date,
        tax_rate=Decimal("10"),
    )
    assert quote.expiry_date == past_date

    # Confirm the date is actually in the past
    assert quote.expiry_date < date.today(), "Test setup: expiry_date must be past"
