"""Phase 32 — Labor derivation: unit tests for the pure rate-resolution module.

Pure unit tests (no DB, no async). Cover:
- work_date_for: UTC work-day convention, timezone-aware requirement
- resolve_rate_row_for_work_date: boundary inclusivity, future-dated exclusion,
  created_at tie-break, empty history
- session_labor_cost: Decimal math with ROUND_HALF_UP cent quantization
- summarize_labor: rated/unrated accounting, per-session quantization
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal
from zoneinfo import ZoneInfo

import pytest
from app.features.finance.labor_derivation import (
    LaborTotals,
    WorkSession,
    resolve_rate_row_for_work_date,
    session_labor_cost,
    summarize_labor,
    work_date_for,
)


@dataclass(frozen=True)
class _Rate:
    effective_from: date
    created_at: datetime
    hourly_cost: Decimal


def _rate(effective_from: date, created_hour: int, hourly_cost: str) -> _Rate:
    return _Rate(
        effective_from=effective_from,
        created_at=datetime(2026, 1, 1, created_hour, 0, tzinfo=UTC),
        hourly_cost=Decimal(hourly_cost),
    )


# ---------------------------------------------------------------------------
# work_date_for — UTC work-day convention
# ---------------------------------------------------------------------------


def test_utc_work_day_convention():
    """A late-evening Vancouver clock-in maps to the next UTC calendar date."""
    clocked_in = datetime(2026, 5, 1, 23, 30, tzinfo=ZoneInfo("America/Vancouver"))
    assert work_date_for(clocked_in) == date(2026, 5, 2)


def test_utc_clock_in_keeps_same_date():
    """A UTC clock-in uses its own calendar date."""
    assert work_date_for(datetime(2026, 5, 1, 10, 0, tzinfo=UTC)) == date(2026, 5, 1)


def test_naive_datetime_rejected():
    """Naive datetimes are refused — the convention requires tz-aware input."""
    with pytest.raises(ValueError, match="clocked_in_at must be timezone-aware"):
        work_date_for(datetime(2026, 5, 1, 10, 0))


# ---------------------------------------------------------------------------
# resolve_rate_row_for_work_date — effective-dated lookup
# ---------------------------------------------------------------------------


def test_empty_history_resolves_to_none():
    """No rate rows means the work day is unrated."""
    assert resolve_rate_row_for_work_date([], date(2026, 5, 1)) is None


def test_boundary_date_is_inclusive():
    """A rate effective on the work day itself covers that day."""
    rate = _rate(date(2026, 5, 1), 9, "30.00")
    assert resolve_rate_row_for_work_date([rate], date(2026, 5, 1)) is rate


def test_future_dated_rate_is_ignored():
    """A rate effective after the work day does not cover it."""
    rate = _rate(date(2026, 5, 2), 9, "30.00")
    assert resolve_rate_row_for_work_date([rate], date(2026, 5, 1)) is None


def test_latest_effective_rate_at_or_before_work_date_wins():
    """Each work day resolves to the most recent rate effective on or before it."""
    may_rate = _rate(date(2026, 5, 1), 9, "30.00")
    june_rate = _rate(date(2026, 6, 1), 9, "40.00")
    rates = [may_rate, june_rate]
    assert resolve_rate_row_for_work_date(rates, date(2026, 5, 15)) is may_rate
    assert resolve_rate_row_for_work_date(rates, date(2026, 6, 10)) is june_rate


def test_duplicate_effective_from_tie_break_uses_latest_created():
    """Among rows sharing an effective_from, the latest created_at wins."""
    earlier = _rate(date(2026, 5, 1), 9, "30.00")
    later = _rate(date(2026, 5, 1), 11, "35.00")
    resolved = resolve_rate_row_for_work_date([earlier, later], date(2026, 5, 5))
    assert resolved is later
    assert resolved.hourly_cost == Decimal("35.00")


# ---------------------------------------------------------------------------
# session_labor_cost — Decimal money math
# ---------------------------------------------------------------------------


def test_full_day_session_cost():
    """8 hours at $30/hour costs exactly $240.00."""
    assert session_labor_cost(28800, Decimal("30.00")) == Decimal("240.00")


def test_one_second_session_rounds_half_up():
    """1s at $45/hour is $0.0125, which rounds half-up to $0.01."""
    assert session_labor_cost(1, Decimal("45.00")) == Decimal("0.01")


def test_rounding_is_half_up():
    """5s at $45/hour is $0.0625 — ROUND_HALF_UP yields $0.06, not banker's $0.06."""
    assert session_labor_cost(5, Decimal("45.00")) == Decimal("0.06")


# ---------------------------------------------------------------------------
# summarize_labor — rated/unrated accounting
# ---------------------------------------------------------------------------

_EIGHT_HOURS = 28800
_FOUR_HOURS = 14400


def _session(contractor_id: uuid.UUID, clocked_in: datetime, seconds: int) -> WorkSession:
    return WorkSession(
        contractor_id=contractor_id,
        clocked_in_at=clocked_in,
        duration_seconds=seconds,
    )


def test_summarize_labor_splits_rated_and_unrated():
    """A rated 8h session is costed; a 4h session with no covering rate is unrated."""
    rated_worker = uuid.uuid4()
    unrated_worker = uuid.uuid4()
    sessions = [
        _session(rated_worker, datetime(2026, 5, 10, 8, 0, tzinfo=UTC), _EIGHT_HOURS),
        _session(unrated_worker, datetime(2026, 5, 10, 8, 0, tzinfo=UTC), _FOUR_HOURS),
    ]
    rates = {rated_worker: [_rate(date(2026, 5, 1), 9, "30.00")]}
    totals = summarize_labor(sessions, rates)
    assert totals == LaborTotals(
        total=Decimal("240.00"),
        rated_seconds=_EIGHT_HOURS,
        unrated_seconds=_FOUR_HOURS,
    )


def test_summarize_labor_empty_inputs():
    """No sessions means a zero total and zero seconds either way."""
    assert summarize_labor([], {}) == LaborTotals(
        total=Decimal("0.00"),
        rated_seconds=0,
        unrated_seconds=0,
    )


def test_summarize_labor_quantizes_per_session():
    """Two 1s sessions at $45 sum their quantized cents ($0.02), not the raw total."""
    worker = uuid.uuid4()
    sessions = [
        _session(worker, datetime(2026, 5, 10, 8, 0, tzinfo=UTC), 1),
        _session(worker, datetime(2026, 5, 10, 9, 0, tzinfo=UTC), 1),
    ]
    rates = {worker: [_rate(date(2026, 5, 1), 9, "45.00")]}
    assert summarize_labor(sessions, rates).total == Decimal("0.02")
