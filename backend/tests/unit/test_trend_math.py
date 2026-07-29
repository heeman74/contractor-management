"""Phase 35 — Trend math: unit tests for the pure monthly-bucketing module.

Pure unit tests (no DB, no async, no fixtures beyond module-level builders). Cover:
- month_key / month_edge / dense_month_keys: the D-02 bucket semantics
- per-record-kind landing rules (cost entry, work session, invoice, approved quote)
- as-of D-01 revenue REPLAY: revenue is resolved per bucket, never accumulated
- the D-14 project-level fallback quote
- window_slice: slices buckets, never records (Pitfall 2)
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, replace
from datetime import UTC, date, datetime
from decimal import Decimal

from app.features.finance.labor_derivation import WorkSession
from app.features.finance.margin_math import (
    REVENUE_BASIS_INVOICED,
    REVENUE_BASIS_NONE,
    REVENUE_BASIS_QUOTED,
    DocumentAmounts,
    RevenueAnchor,
)
from app.features.finance.trend_math import (
    DEFAULT_TREND_WINDOW,
    TREND_WINDOW_3M,
    TREND_WINDOW_12M,
    TREND_WINDOW_ALL,
    DatedCost,
    DatedDocument,
    TrendInputs,
    dense_month_keys,
    month_edge,
    month_key,
    trend_buckets,
    window_slice,
)

CONTRACTOR_ID = uuid.UUID("11111111-1111-1111-1111-111111111111")
JOB_ANCHOR = RevenueAnchor(job_id=uuid.UUID("22222222-2222-2222-2222-222222222222"))
OTHER_ANCHOR = RevenueAnchor(job_id=uuid.UUID("33333333-3333-3333-3333-333333333333"))
TODAY = date(2026, 4, 15)
HOURLY_COST = Decimal("50.00")
EIGHT_HOURS_IN_SECONDS = 8 * 60 * 60


@dataclass(frozen=True)
class _Rate:
    effective_from: date
    created_at: datetime
    hourly_cost: Decimal


def _rates(effective_from: date = date(2026, 1, 1)) -> dict[uuid.UUID, list[_Rate]]:
    return {
        CONTRACTOR_ID: [
            _Rate(
                effective_from=effective_from,
                created_at=datetime(2026, 1, 1, tzinfo=UTC),
                hourly_cost=HOURLY_COST,
            )
        ]
    }


def _amounts(subtotal: str) -> DocumentAmounts:
    return DocumentAmounts(
        subtotal=Decimal(subtotal),
        discount_type=None,
        discount_value=Decimal("0"),
        tax_rate=Decimal("0"),
    )


def _document(
    effective_date: date, subtotal: str, anchor: RevenueAnchor = JOB_ANCHOR
) -> DatedDocument:
    return DatedDocument(anchor=anchor, amounts=_amounts(subtotal), effective_date=effective_date)


def _session(clocked_in: datetime) -> WorkSession:
    return WorkSession(
        contractor_id=CONTRACTOR_ID,
        clocked_in_at=clocked_in,
        duration_seconds=EIGHT_HOURS_IN_SECONDS,
        job_id=JOB_ANCHOR.job_id,
    )


def _inputs(**overrides) -> TrendInputs:
    base = TrendInputs(
        costs=(),
        sessions=(),
        rates_by_contractor=_rates(),
        invoices=(),
        quotes=(),
        fallback_quote=None,
        today=TODAY,
    )
    return replace(base, **overrides)


def _full_inputs() -> TrendInputs:
    """January quote, February labor, March invoice — one record of each kind per month."""
    return _inputs(
        costs=(
            DatedCost(amount=Decimal("100.00"), incurred_date=date(2026, 1, 15)),
            DatedCost(amount=Decimal("250.00"), incurred_date=date(2026, 3, 5)),
        ),
        sessions=(_session(datetime(2026, 2, 10, 15, 0, tzinfo=UTC)),),
        invoices=(_document(date(2026, 3, 20), "1000.00"),),
        quotes=(_document(date(2026, 1, 10), "800.00"),),
    )


def _by_month(inputs: TrendInputs) -> dict[str, object]:
    return {bucket.month: bucket for bucket in trend_buckets(inputs)}


# ---------------------------------------------------------------------------
# Bucket keys and edges — the D-02 semantics
# ---------------------------------------------------------------------------


def test_month_key_is_year_dash_month():
    assert month_key(date(2026, 3, 5)) == "2026-03"


def test_month_edge_is_the_inclusive_last_calendar_day():
    assert month_edge("2026-02") == date(2026, 2, 28)
    assert month_edge("2024-02") == date(2024, 2, 29)
    assert month_edge("2026-12") == date(2026, 12, 31)


def test_dense_month_keys_span_year_boundaries_without_gaps():
    assert dense_month_keys(date(2025, 11, 30), date(2026, 2, 1)) == [
        "2025-11",
        "2025-12",
        "2026-01",
        "2026-02",
    ]


def test_buckets_are_dense_from_first_record_month_through_today():
    assert [bucket.month for bucket in trend_buckets(_full_inputs())] == [
        "2026-01",
        "2026-02",
        "2026-03",
        "2026-04",
    ]


# ---------------------------------------------------------------------------
# Per-record-kind landing rules
# ---------------------------------------------------------------------------


def test_dense_months_carry_forward_cumulative_cost():
    buckets = _by_month(_full_inputs())
    assert buckets["2026-01"].cost == Decimal("100.00")
    assert buckets["2026-02"].cost == Decimal("500.00")
    assert buckets["2026-03"].cost == Decimal("750.00")
    assert buckets["2026-04"].cost == Decimal("750.00")


def test_cost_entry_on_the_month_edge_lands_in_that_bucket():
    """The edge is inclusive: a Jan 31 entry counts in the January bucket."""
    inputs = _inputs(costs=(DatedCost(amount=Decimal("40.00"), incurred_date=date(2026, 1, 31)),))
    assert _by_month(inputs)["2026-01"].cost == Decimal("40.00")


def test_work_session_lands_by_utc_work_date():
    """A late-evening Vancouver clock-in costs into the NEXT UTC day's month (Phase 32)."""
    clocked_in = datetime(2026, 1, 31, 23, 30, tzinfo=UTC).astimezone(UTC)
    inputs = _inputs(sessions=(_session(clocked_in),))
    buckets = _by_month(inputs)
    assert buckets["2026-01"].cost == Decimal("400.00")
    assert buckets["2026-04"].cost == Decimal("400.00")


def test_unrated_labor_carries_the_incomplete_flag_into_the_bucket():
    """A session before any effective rate is unrated, and the bucket says so."""
    inputs = _inputs(
        sessions=(_session(datetime(2026, 2, 10, 15, 0, tzinfo=UTC)),),
        rates_by_contractor=_rates(effective_from=date(2026, 12, 1)),
        invoices=(_document(date(2026, 1, 5), "1000.00"),),
    )
    february = _by_month(inputs)["2026-02"]
    assert february.cost == Decimal("0.00")
    assert february.margin.incomplete is True


def test_invoice_revenue_lands_in_buckets_on_or_after_its_issue_date():
    buckets = _by_month(_inputs(invoices=(_document(date(2026, 3, 20), "1000.00"),)))
    assert buckets["2026-03"].margin.revenue == Decimal("1000.00")
    assert buckets["2026-03"].margin.revenue_basis == REVENUE_BASIS_INVOICED


def test_quote_without_approved_at_buckets_by_created_at():
    """Pitfall 4: an approved quote with no approved_at is dated by created_at, never dropped."""
    created_at_date = date(2026, 2, 3)
    buckets = _by_month(_inputs(quotes=(_document(created_at_date, "800.00"),)))
    assert buckets["2026-02"].margin.revenue == Decimal("800.00")
    assert buckets["2026-02"].margin.revenue_basis == REVENUE_BASIS_QUOTED


# ---------------------------------------------------------------------------
# Revenue is RESOLVED per bucket, never accumulated (D-01)
# ---------------------------------------------------------------------------


def test_invoice_supersedes_quote_at_the_same_anchor_instead_of_summing():
    buckets = _by_month(_full_inputs())
    assert buckets["2026-01"].margin.revenue == Decimal("800.00")
    assert buckets["2026-02"].margin.revenue == Decimal("800.00")
    assert buckets["2026-03"].margin.revenue == Decimal("1000.00")
    assert buckets["2026-03"].margin.revenue_basis == REVENUE_BASIS_INVOICED


def test_revenue_across_distinct_anchors_sums_and_mixes_basis():
    inputs = _inputs(
        invoices=(_document(date(2026, 3, 1), "1000.00"),),
        quotes=(_document(date(2026, 3, 1), "500.00", anchor=OTHER_ANCHOR),),
    )
    march = _by_month(inputs)["2026-03"]
    assert march.margin.revenue == Decimal("1500.00")
    assert march.margin.revenue_basis == "mixed"


def test_project_fallback_quote_applies_only_when_no_anchor_resolved():
    inputs = _inputs(
        invoices=(_document(date(2026, 3, 1), "1000.00"),),
        fallback_quote=_document(date(2026, 1, 1), "9000.00"),
    )
    buckets = _by_month(inputs)
    assert buckets["2026-01"].margin.revenue == Decimal("9000.00")
    assert buckets["2026-03"].margin.revenue == Decimal("1000.00")


def test_final_bucket_matches_the_all_time_resolution():
    """The reconciliation guarantee: at today's edge the trend equals the shipped rollup."""
    inputs = _full_inputs()
    final = trend_buckets(inputs)[-1]
    assert final.month == month_key(inputs.today)
    assert final.cost == Decimal("750.00")
    assert final.margin.revenue == Decimal("1000.00")
    assert final.margin.margin == Decimal("250.00")


def test_absent_revenue_yields_none_not_zero():
    inputs = _inputs(costs=(DatedCost(amount=Decimal("100.00"), incurred_date=date(2026, 1, 15)),))
    january = _by_month(inputs)["2026-01"]
    assert january.margin.revenue is None
    assert january.margin.margin is None
    assert january.margin.revenue_basis == REVENUE_BASIS_NONE


def test_empty_inputs_produce_no_buckets():
    assert trend_buckets(_inputs()) == []


# ---------------------------------------------------------------------------
# window_slice — slices buckets, never records (Pitfall 2)
# ---------------------------------------------------------------------------


def test_window_slice_returns_the_last_n_buckets():
    buckets = trend_buckets(_full_inputs())
    assert [bucket.month for bucket in window_slice(buckets, TREND_WINDOW_3M)] == [
        "2026-02",
        "2026-03",
        "2026-04",
    ]


def test_window_slice_returns_identical_values_for_shared_months():
    buckets = trend_buckets(_full_inputs())
    narrow = {bucket.month: bucket for bucket in window_slice(buckets, TREND_WINDOW_3M)}
    wide = {bucket.month: bucket for bucket in window_slice(buckets, TREND_WINDOW_12M)}
    shared = narrow.keys() & wide.keys()
    assert shared
    assert all(narrow[month] == wide[month] for month in shared)


def test_window_slice_all_returns_every_bucket():
    buckets = trend_buckets(_full_inputs())
    assert window_slice(buckets, TREND_WINDOW_ALL) == buckets
    assert DEFAULT_TREND_WINDOW == TREND_WINDOW_12M
