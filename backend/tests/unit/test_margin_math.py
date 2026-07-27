"""Phase 33 — Margin math: unit tests for the pure revenue/margin module.

Pure unit tests (no DB, no async). Cover:
- discount_for / pre_tax_total / tax_for / document_total: the shared
  document math that invoice and quote response totals delegate to
- revenue_from: pre-tax revenue summation (D-13)
- resolve_anchor_revenue / combine_revenue_bases: invoices-win-outright
  resolution and basis mixing (D-01/D-03)
- missing_cost_data: the Pitfall-9 zero-cost signal (D-05/D-07)
- summarize_margin: margin dollars/percent, incomplete flags, rounding
"""

from __future__ import annotations

from decimal import Decimal

from app.features.finance.margin_math import (
    INCOMPLETE_NO_COST_DATA,
    INCOMPLETE_UNRATED_LABOR,
    REVENUE_BASIS_INVOICED,
    REVENUE_BASIS_MIXED,
    REVENUE_BASIS_NONE,
    REVENUE_BASIS_QUOTED,
    AnchorRevenue,
    DocumentAmounts,
    MarginFigures,
    MarginInputs,
    ResolvedRevenue,
    combine_revenue_bases,
    discount_for,
    document_total,
    margin_percent_for,
    missing_cost_data,
    pre_tax_total,
    resolve_anchor_revenue,
    revenue_from,
    summarize_margin,
    tax_for,
)

TAXED_DOCUMENT = DocumentAmounts(
    subtotal=Decimal("1000.00"),
    discount_type="percent",
    discount_value=Decimal("10"),
    tax_rate=Decimal("8.25"),
)

PLAIN_DOCUMENT = DocumentAmounts(
    subtotal=Decimal("100.00"),
    discount_type=None,
    discount_value=Decimal("0"),
    tax_rate=Decimal("0"),
)


def _figures(revenue, basis, cost, *, unrated_seconds=0, missing=False) -> MarginFigures:
    return summarize_margin(
        MarginInputs(
            revenue=ResolvedRevenue(total=revenue, basis=basis),
            cost=cost,
            unrated_seconds=unrated_seconds,
            has_missing_cost_data=missing,
        )
    )


# ---------------------------------------------------------------------------
# Document math — shared with invoice/quote response totals
# ---------------------------------------------------------------------------


def test_percent_discount_on_subtotal():
    """A 10% discount on a 1000.00 subtotal is exactly 100.00."""
    assert str(discount_for(TAXED_DOCUMENT)) == "100.00"


def test_fixed_discount_applies_verbatim():
    """A fixed 250.00 discount under the subtotal applies as-is."""
    amounts = DocumentAmounts(
        subtotal=Decimal("1000.00"),
        discount_type="fixed",
        discount_value=Decimal("250.00"),
        tax_rate=Decimal("0"),
    )
    assert str(discount_for(amounts)) == "250.00"


def test_fixed_discount_is_capped_at_subtotal():
    """A fixed discount can never exceed the subtotal it discounts."""
    amounts = DocumentAmounts(
        subtotal=Decimal("100.00"),
        discount_type="fixed",
        discount_value=Decimal("250.00"),
        tax_rate=Decimal("0"),
    )
    assert str(discount_for(amounts)) == "100.00"


def test_absent_discount_type_means_no_discount():
    """No discount_type yields a zero discount."""
    assert str(discount_for(PLAIN_DOCUMENT)) == "0.00"


def test_pre_tax_total_excludes_tax():
    """The D-13 revenue leg is subtotal minus discount, tax excluded."""
    assert str(pre_tax_total(TAXED_DOCUMENT)) == "900.00"


def test_tax_applies_to_discounted_subtotal():
    """8.25% tax on the discounted 900.00 is 74.25."""
    assert str(tax_for(TAXED_DOCUMENT)) == "74.25"


def test_document_total_matches_shipped_schema_math():
    """Discounted subtotal plus tax reproduces from_orm_with_totals exactly."""
    assert str(document_total(TAXED_DOCUMENT)) == "974.25"


def test_revenue_from_sums_pre_tax_totals():
    """Revenue across documents sums pre-tax legs: 900.00 + 100.00 = 1000.00."""
    assert str(revenue_from([TAXED_DOCUMENT, PLAIN_DOCUMENT])) == "1000.00"


# ---------------------------------------------------------------------------
# Revenue resolution — D-01/D-03 invoices win outright
# ---------------------------------------------------------------------------


def test_invoices_win_outright_over_a_larger_approved_quote():
    """Any invoiced total beats the quote entirely — never max(), never summed."""
    anchor = AnchorRevenue(
        invoiced_total=Decimal("500.00"),
        quoted_total=Decimal("9999.00"),
    )
    resolved = resolve_anchor_revenue(anchor)
    assert str(resolved.total) == "500.00"
    assert resolved.basis == REVENUE_BASIS_INVOICED


def test_approved_quote_is_the_fallback_without_invoices():
    """With no invoices, the approved quote total carries the quoted basis."""
    anchor = AnchorRevenue(invoiced_total=None, quoted_total=Decimal("800.00"))
    resolved = resolve_anchor_revenue(anchor)
    assert str(resolved.total) == "800.00"
    assert resolved.basis == REVENUE_BASIS_QUOTED


def test_no_revenue_documents_resolve_to_none_basis():
    """Neither invoices nor an approved quote means no revenue at all."""
    resolved = resolve_anchor_revenue(AnchorRevenue())
    assert resolved.total is None
    assert resolved.basis == REVENUE_BASIS_NONE


def test_uniform_invoiced_bases_stay_invoiced():
    """All-invoiced contributions combine to an invoiced basis."""
    assert combine_revenue_bases(["invoiced", "invoiced"]) == REVENUE_BASIS_INVOICED


def test_invoiced_and_quoted_bases_combine_to_mixed():
    """Different real bases combine to mixed."""
    assert combine_revenue_bases(["invoiced", "quoted"]) == REVENUE_BASIS_MIXED


def test_none_basis_never_mixes():
    """A none entry is ignored — one quoted contributor stays quoted."""
    assert combine_revenue_bases(["quoted", "none"]) == REVENUE_BASIS_QUOTED


def test_empty_or_all_none_bases_combine_to_none():
    """No contributors (or only none entries) combine to none."""
    assert combine_revenue_bases([]) == REVENUE_BASIS_NONE
    assert combine_revenue_bases(["none"]) == REVENUE_BASIS_NONE


# ---------------------------------------------------------------------------
# missing_cost_data — D-05/D-07 zero-cost signal
# ---------------------------------------------------------------------------


def test_zero_cost_with_revenue_is_missing_cost_data():
    """Revenue with no cost at all is the Pitfall-9 data-quality problem."""
    assert missing_cost_data(cost=Decimal("0.00"), revenue=Decimal("2000.00")) is True


def test_any_cost_with_revenue_is_not_missing():
    """Even a small cost entry means cost data exists."""
    assert missing_cost_data(cost=Decimal("10.00"), revenue=Decimal("2000.00")) is False


def test_zero_cost_without_revenue_is_not_missing():
    """D-07: absent revenue is not a data-quality problem."""
    assert missing_cost_data(cost=Decimal("0.00"), revenue=None) is False


def test_zero_cost_with_zero_revenue_is_not_missing():
    """Zero revenue means there is nothing a missing cost could distort."""
    assert missing_cost_data(cost=Decimal("0.00"), revenue=Decimal("0.00")) is False


# ---------------------------------------------------------------------------
# summarize_margin — dollars, percent, and honesty flags
# ---------------------------------------------------------------------------


def test_invoiced_happy_path_margin_and_percent():
    """Revenue 20000.00 against cost 15800.00 yields 4200.00 at 21.0%."""
    figures = _figures(Decimal("20000.00"), REVENUE_BASIS_INVOICED, Decimal("15800.00"))
    assert str(figures.revenue) == "20000.00"
    assert figures.revenue_basis == REVENUE_BASIS_INVOICED
    assert str(figures.margin) == "4200.00"
    assert str(figures.margin_percent) == "21.0"
    assert figures.incomplete is False
    assert figures.incomplete_reasons == ()


def test_negative_margin_is_a_real_figure():
    """Costs above revenue produce a negative margin, never a clamped zero."""
    figures = _figures(Decimal("4200.00"), REVENUE_BASIS_INVOICED, Decimal("4550.00"))
    assert str(figures.margin) == "-350.00"
    assert str(figures.margin_percent) == "-8.3"


def test_zero_revenue_with_invoices_has_no_percent():
    """A zeroed-out invoice keeps the dollar margin but drops the percent."""
    figures = _figures(Decimal("0.00"), REVENUE_BASIS_INVOICED, Decimal("100.00"))
    assert str(figures.margin) == "-100.00"
    assert figures.margin_percent is None
    assert figures.incomplete is False


def test_no_revenue_source_is_absent_but_never_flagged():
    """D-07: no invoice and no approved quote means no margin, not bad data."""
    figures = _figures(None, REVENUE_BASIS_NONE, Decimal("0.00"), unrated_seconds=7200)
    assert figures.revenue is None
    assert figures.margin is None
    assert figures.margin_percent is None
    assert figures.incomplete is False
    assert figures.incomplete_reasons == ()


def test_unrated_labor_flags_without_suppressing_the_margin():
    """D-06: the partial margin still shows beside the unrated-labor flag."""
    figures = _figures(
        Decimal("1000.00"),
        REVENUE_BASIS_INVOICED,
        Decimal("400.00"),
        unrated_seconds=3600,
    )
    assert figures.incomplete is True
    assert figures.incomplete_reasons == (INCOMPLETE_UNRATED_LABOR,)
    assert str(figures.margin) == "600.00"


def test_keystone_zero_cost_with_revenue_is_flagged_no_cost_data():
    """Pitfall 9 keystone: a fabricated 100% margin must carry the flag."""
    figures = _figures(
        Decimal("2000.00"),
        REVENUE_BASIS_INVOICED,
        Decimal("0.00"),
        missing=True,
    )
    assert str(figures.margin) == "2000.00"
    assert str(figures.margin_percent) == "100.0"
    assert figures.incomplete is True
    assert figures.incomplete_reasons == (INCOMPLETE_NO_COST_DATA,)


def test_both_incomplete_reasons_keep_a_fixed_order():
    """Unrated labor always precedes no-cost-data in the reasons tuple."""
    figures = _figures(
        Decimal("1000.00"),
        REVENUE_BASIS_INVOICED,
        Decimal("0.00"),
        unrated_seconds=3600,
        missing=True,
    )
    assert figures.incomplete_reasons == (
        INCOMPLETE_UNRATED_LABOR,
        INCOMPLETE_NO_COST_DATA,
    )


def test_percent_rounds_half_up_to_one_decimal():
    """A third of revenue as margin serializes as 33.3, one decimal place."""
    figures = _figures(Decimal("3000.00"), REVENUE_BASIS_INVOICED, Decimal("2000.00"))
    assert str(figures.margin_percent) == "33.3"


def test_margin_percent_for_returns_none_at_zero_revenue():
    """Division by zero revenue is never attempted."""
    assert margin_percent_for(Decimal("-100.00"), Decimal("0.00")) is None
