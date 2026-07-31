"""Unit tests for the quote-planning system prompt (FINAI-03/04, D-09).

The prompt is half of the grounding contract: its bounds must equal the
values the DB CHECK and the create schema actually enforce, imported rather
than retyped (the 36-08 finding), and its rules must mandate exactly the
sigils, quantity discipline and labor wording the service validates against.
"""

from __future__ import annotations

from app.features.quotes.models import MAX_BASIS_LENGTH
from app.features.quotes.prompts.quote_planning_system import (
    BASIS_MAX_CHARS,
    DESCRIPTION_MAX_CHARS,
    QUOTE_PLANNING_SYSTEM_PROMPT,
    SUGGESTED_LINE_FIELDS,
)
from app.features.quotes.schemas import QuoteLineItemCreate


def _field_max_length(field_name: str) -> int:
    """The Field(max_length=...) constraint on one QuoteLineItemCreate field,
    read off the schema rather than retyped."""
    for constraint in QuoteLineItemCreate.model_fields[field_name].metadata:
        candidate = getattr(constraint, "max_length", None)
        if candidate is not None:
            return candidate
    raise AssertionError(f"{field_name} carries no max_length constraint")


def test_basis_bound_equals_model_constant():
    """The prompt's basis bound can never be looser than the DB CHECK it backs."""
    assert BASIS_MAX_CHARS == MAX_BASIS_LENGTH


def test_description_bound_equals_schema_max_length():
    """The prompt's description bound can never be looser than the create schema's."""
    assert _field_max_length("description") == DESCRIPTION_MAX_CHARS


def test_prompt_mandates_dollar_and_percent_sigils():
    assert '"$"' in QUOTE_PLANNING_SYSTEM_PROMPT
    assert '"%"' in QUOTE_PLANNING_SYSTEM_PROMPT


def test_prompt_confines_quantity_to_structured_field():
    sentence = (
        "Write the quantity ONLY in the structured quantity field, never inside the basis sentence"
    )
    assert sentence in QUOTE_PLANNING_SYSTEM_PROMPT


def test_prompt_carries_unburdened_labor_label():
    assert "unburdened" in QUOTE_PLANNING_SYSTEM_PROMPT


def test_output_schema_names_exactly_the_service_fields():
    """The output schema's keys are exactly what the service reads — no others."""
    assert SUGGESTED_LINE_FIELDS == (
        "item_type",
        "description",
        "quantity",
        "unit",
        "unit_price",
        "basis",
    )
    for field in SUGGESTED_LINE_FIELDS:
        assert f'"{field}"' in QUOTE_PLANNING_SYSTEM_PROMPT
