"""Grounding validator for AI-authored text (FINAI D-05, SC3).

Every dollar and percent the model writes must already exist in the payload it was
given. That is only tractable if the payload's value set is CLOSED under everything
the prompt permits: callers precompute every citable delta as a named payload field
and the prompt forbids the model from computing anything. Validation is then pure
set membership — small, fast, exhaustively testable, with no false-accept surface.

Payload-shape agnostic on purpose: it carries no feature-package imports, so the
quote-planning feature reuses it unchanged.
"""

from __future__ import annotations

import re
from collections.abc import Iterator, Mapping, Sequence
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

# Money literals carry a leading "$"; the comma-grouped form is tried first and
# requires at least one group so "$3200" is not truncated to "$320".
MONEY_PATTERN = re.compile(r"-?\$\s?\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|-?\$\s?\d+(?:\.\d{1,2})?")
PERCENT_PATTERN = re.compile(r"-?\d+(?:\.\d+)?\s?%")

CENTS = Decimal("0.01")
PERCENT_PLACES = Decimal("0.1")
WHOLE_DOLLAR = Decimal("1")

_FIGURE_NOISE_PATTERN = re.compile(r"[$,%\s]")


@dataclass(frozen=True)
class CitedFigure:
    """One figure the model wrote, kept verbatim so a retry prompt can name it back."""

    literal: str
    value: Decimal
    is_percent: bool


@dataclass(frozen=True)
class GroundingResult:
    """The verdict on one piece of AI text, plus the offending literals verbatim."""

    ok: bool
    unmatched: tuple[str, ...]


def collect_allowed_values(payload: Mapping[str, object]) -> frozenset[Decimal]:
    """Every citable number in a nested payload, at any depth.

    Strings are skipped DELIBERATELY, and that is the only reason this stays both
    payload-shape agnostic and safe: callers pass money and percents as Decimal
    objects and serialize to JSON at the call site, so a project named "2026" can
    never make "$2,026" citable. bool is excluded for the same reason — it is an
    int subclass, and True must not become Decimal("1").
    """
    return frozenset(_citable_numbers_in(payload))


def extract_figures(text: str) -> tuple[CitedFigure, ...]:
    """Every dollar and percent literal in the text, in source order."""
    money = ((match, False) for match in MONEY_PATTERN.finditer(text))
    percent = ((match, True) for match in PERCENT_PATTERN.finditer(text))
    ordered = sorted([*money, *percent], key=lambda found: found[0].start())
    return tuple(
        CitedFigure(
            literal=match.group(),
            value=_normalized_value(match.group()),
            is_percent=is_percent,
        )
        for match, is_percent in ordered
    )


def matches_allowed(figure: CitedFigure, allowed: frozenset[Decimal]) -> bool:
    """Whether one cited figure is present in the allowed set under a shipped representation."""
    if figure.is_percent:
        return any(_matches_as_percent(figure.value, value) for value in allowed)
    return any(_matches_as_money(figure.value, value) for value in allowed)


def validate_grounding(text: str, allowed: frozenset[Decimal]) -> GroundingResult:
    """Reject text citing any figure absent from the allowed set (D-05).

    Text with no figures at all is grounded: a qualitative sentence cites nothing
    and therefore fabricates nothing.
    """
    unmatched = tuple(
        figure.literal for figure in extract_figures(text) if not matches_allowed(figure, allowed)
    )
    return GroundingResult(ok=not unmatched, unmatched=unmatched)


def _citable_numbers_in(node: object) -> Iterator[Decimal]:
    if isinstance(node, Mapping):
        for value in node.values():
            yield from _citable_numbers_in(value)
    elif _is_walkable_sequence(node):
        for item in node:
            yield from _citable_numbers_in(item)
    elif _is_citable_number(node):
        yield Decimal(node)


def _is_walkable_sequence(node: object) -> bool:
    return isinstance(node, Sequence) and not isinstance(node, str | bytes | bytearray)


def _is_citable_number(node: object) -> bool:
    if isinstance(node, bool):
        return False
    return isinstance(node, Decimal | int)


def _normalized_value(literal: str) -> Decimal:
    """The literal as a Decimal, sigils and separators stripped, sign preserved."""
    return Decimal(_FIGURE_NOISE_PATTERN.sub("", literal))


def _matches_as_percent(cited: Decimal, allowed_value: Decimal) -> bool:
    """format_alert_percent drops a trailing ".0", so percents compare at one decimal."""
    return allowed_value.quantize(PERCENT_PLACES) == cited.quantize(PERCENT_PLACES)


def _matches_as_money(cited: Decimal, allowed_value: Decimal) -> bool:
    """Money compares to the cent, or to the whole dollar the model naturally writes.

    The whole-dollar clause is a deliberate loosening: format_alert_money renders
    Decimal("10000.00") as "$10,000", and a model given Decimal("3200.41") will
    write "$3,200". It is one-directional — a cited cents figure never matches a
    whole-dollar payload value.
    """
    if allowed_value.quantize(CENTS) == cited.quantize(CENTS):
        return True
    return allowed_value.quantize(WHOLE_DOLLAR, rounding=ROUND_HALF_UP) == cited
