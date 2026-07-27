"""Pure rate-resolution and labor-cost math for the finance domain (COST-04/COST-05).

Work day convention: the UTC calendar date of `clocked_in_at`. `users.timezone`
exists but is a display-only field defaulting to 'UTC' and is deliberately NOT used —
derivation and every surface that explains a labor figure use the same UTC date so
the number is reproducible. Rate rule: the rate for a work day is the row with the
greatest effective_from <= work day; among rows sharing that effective_from, the
latest created_at wins. No qualifying row means the session's seconds are unrated.

This module is deliberately DB-free: no SQLAlchemy, no FastAPI, no repositories.
It is the single source of the effective-dated rate rule for the whole phase.
"""

from __future__ import annotations

import uuid
from bisect import bisect_right
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import ROUND_HALF_UP, Decimal
from typing import Protocol

SECONDS_PER_HOUR = Decimal("3600")
CENTS = Decimal("0.01")
ZERO_MONEY = Decimal("0.00")


class EffectiveDatedRate(Protocol):
    """Anything carrying an effective date, a creation timestamp, and an hourly cost.

    Satisfied by the LaborRate ORM model and by test doubles alike, so the
    resolution rule never needs a database.
    """

    effective_from: date
    created_at: datetime
    hourly_cost: Decimal


@dataclass(frozen=True)
class WorkSession:
    """A completed, clocked-out block of tracked time eligible for costing."""

    contractor_id: uuid.UUID
    clocked_in_at: datetime
    duration_seconds: int


@dataclass(frozen=True)
class LaborTotals:
    """Derived labor cost plus the honest accounting of what could not be costed."""

    total: Decimal
    rated_seconds: int
    unrated_seconds: int


def work_date_for(clocked_in_at: datetime) -> date:
    """UTC calendar date of a clock-in — the canonical work day for rate lookup."""
    if clocked_in_at.tzinfo is None:
        raise ValueError("clocked_in_at must be timezone-aware")
    return clocked_in_at.astimezone(UTC).date()


def resolve_rate_row_for_work_date[RateT: EffectiveDatedRate](
    sorted_rates: Sequence[RateT], work_date: date
) -> RateT | None:
    """Latest rate effective on or before the work day, or None when uncovered.

    `sorted_rates` MUST be pre-sorted ascending by (effective_from, created_at).
    The ascending sort makes the last row at a shared effective_from the latest
    created_at, which IS the tie-break rule.
    """
    index = bisect_right(sorted_rates, work_date, key=lambda rate: rate.effective_from)
    return sorted_rates[index - 1] if index else None


def session_labor_cost(duration_seconds: int, hourly_cost: Decimal) -> Decimal:
    """Cost of one session, quantized to cents half-up (per session, never at the end)."""
    hours = Decimal(duration_seconds) / SECONDS_PER_HOUR
    return (hours * hourly_cost).quantize(CENTS, rounding=ROUND_HALF_UP)


def summarize_labor[RateT: EffectiveDatedRate](
    sessions: Iterable[WorkSession],
    rates_by_contractor: dict[uuid.UUID, Sequence[RateT]],
) -> LaborTotals:
    """Total rated labor cost plus rated/unrated second counts across sessions."""
    total = ZERO_MONEY
    rated_seconds = 0
    unrated_seconds = 0
    for session in sessions:
        rates = rates_by_contractor.get(session.contractor_id, ())
        rate = resolve_rate_row_for_work_date(rates, work_date_for(session.clocked_in_at))
        if rate is None:
            unrated_seconds += session.duration_seconds
        else:
            total += session_labor_cost(session.duration_seconds, rate.hourly_cost)
            rated_seconds += session.duration_seconds
    return LaborTotals(
        total=total.quantize(CENTS),
        rated_seconds=rated_seconds,
        unrated_seconds=unrated_seconds,
    )
