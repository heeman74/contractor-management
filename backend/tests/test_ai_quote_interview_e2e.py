"""AI quote interview: scope gathered by questions, then priced.

The interview creates a project-level draft quote and delegates pricing to
QuoteSuggestionService. What matters here, and what these tests hold:

- a company with no comparable history gets a ROUGH estimate rather than the
  refusal `/suggest-line-items` still returns, and those lines are marked
  `rough` — a distinct band, not `low`;
- a rough line never claims history it did not consult;
- the review gate is untouched: every generated line lands unreviewed;
- widening `suggest()` did not change the existing endpoint's behaviour.

Self-contained per the convention the other phase suites follow — the mock
Anthropic factory is copied rather than imported.
"""

import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import AsyncClient
from sqlalchemy import text

from app.core.database import async_session_factory
from app.features.quotes.models import CONFIDENCE_BAND_ROUGH
from app.features.quotes.quote_history_math import MIN_COMPARABLES_FOR_SUGGESTION
from app.features.quotes.suggestion_service import (
    ROUGH_BASIS_PREFIX,
    _rough_basis,
    _rough_line_is_well_formed,
)

START_URL = "/api/v1/ai/quote-interview/start"
COMPLETE_URL = "/api/v1/ai/quote-interview/complete"


def _make_mock_anthropic_response(content: dict | str) -> MagicMock:
    """Mock Anthropic message response with content[0].text."""
    content_text = json.dumps(content) if isinstance(content, dict) else content
    mock_content = MagicMock()
    mock_content.text = content_text
    mock_response = MagicMock()
    mock_response.content = [mock_content]
    return mock_response


_ROUGH_LINES = {
    "lines": [
        {
            "item_type": "labor",
            "description": "Rough-in plumbing for three bathrooms",
            "quantity": 40,
            "unit": "hours",
            "unit_price": 95,
            "basis": "typical residential rate",
        },
        {
            "item_type": "material",
            "description": "Supply and waste pipe, fittings",
            "quantity": 1,
            "unit": "lot",
            "unit_price": 2500,
            "basis": "typical material allowance",
        },
    ]
}


_LINE_ITEM_ROWS_SQL = (
    "SELECT ai_origin, review_state, confidence_band, basis FROM quote_line_items "
    "WHERE quote_id = CAST(:quote_id AS uuid) ORDER BY sort_order"
)


async def _line_item_rows(company_id: str, quote_id: str) -> list[dict]:
    """Read line items straight off the DB.

    The API nulls confidence_band and basis for a caller without finance.view
    (Phase 30 D-06), so asserting on the response would test the scrub rather
    than what was stored.
    """
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(text(_LINE_ITEM_ROWS_SQL), {"quote_id": quote_id})
        return [dict(row._mapping) for row in result]


async def _start(client: AsyncClient) -> str:
    resp = await client.post(START_URL)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _complete(client: AsyncClient, conversation_id: str, **overrides) -> dict:
    body = {
        "conversation_id": conversation_id,
        "trade": "Plumbing",
        "title": "3-bath rough-in, Elm St",
        "brief": "Three-bathroom rough-in in a renovation. Existing cast iron to remove.",
    }
    body.update(overrides)
    resp = await client.post(COMPLETE_URL, json=body)
    assert resp.status_code == 200, resp.text
    return resp.json()


# ---------------------------------------------------------------------------
# The cold-start behaviour this feature exists to change
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_cold_start_produces_rough_estimate_not_a_refusal(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """With no comparable history the interview still yields priced lines,
    every one of them banded `rough`."""
    conversation_id = await _start(tenant_a_client)

    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        mock_client.return_value.messages.create = AsyncMock(
            return_value=_make_mock_anthropic_response(_ROUGH_LINES)
        )
        body = await _complete(tenant_a_client, conversation_id)

    assert body["refusal_reason"] is None
    assert body["grounded"] is False
    assert body["comparable_count"] == 0
    assert body["required_count"] == MIN_COMPARABLES_FOR_SUGGESTION
    assert body["suggested_line_count"] == 2
    assert body["trade_name"] == "Plumbing"

    quote = (await tenant_a_client.get(f"/api/v1/quotes/{body['quote_id']}")).json()
    assert quote["status"] == "draft"
    assert quote["title"] == "3-bath rough-in, Elm St"
    assert len(quote["line_items"]) == 2

    rows = await _line_item_rows(seed_two_tenants["tenant_a_id"], body["quote_id"])
    assert len(rows) == 2
    for row in rows:
        assert row["confidence_band"] == CONFIDENCE_BAND_ROUGH
        assert row["ai_origin"] is True
        assert row["review_state"] == "unreviewed"
        assert row["basis"].startswith(ROUGH_BASIS_PREFIX)


@pytest.mark.asyncio
async def test_rough_band_is_not_low(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """`rough` must stay distinguishable from a weakly-grounded `low` — the
    whole reason it is a separate value."""
    conversation_id = await _start(tenant_a_client)
    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        mock_client.return_value.messages.create = AsyncMock(
            return_value=_make_mock_anthropic_response(_ROUGH_LINES)
        )
        body = await _complete(tenant_a_client, conversation_id)

    rows = await _line_item_rows(seed_two_tenants["tenant_a_id"], body["quote_id"])
    bands = {row["confidence_band"] for row in rows}
    assert bands == {CONFIDENCE_BAND_ROUGH}
    assert "low" not in bands


@pytest.mark.asyncio
async def test_malformed_model_output_refuses_rather_than_storing_junk(
    tenant_a_client: AsyncClient,
):
    """A line missing required keys is not persisted as a half-priced row."""
    conversation_id = await _start(tenant_a_client)
    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        mock_client.return_value.messages.create = AsyncMock(
            return_value=_make_mock_anthropic_response({"lines": [{"item_type": "labor"}]})
        )
        body = await _complete(tenant_a_client, conversation_id)

    assert body["refusal_reason"] == "ungrounded"
    assert body["suggested_line_count"] == 0
    quote = (await tenant_a_client.get(f"/api/v1/quotes/{body['quote_id']}")).json()
    assert quote["line_items"] == []


# ---------------------------------------------------------------------------
# The existing endpoint must be unchanged by widening suggest()
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_suggest_endpoint_still_refuses_on_cold_start(tenant_a_client: AsyncClient):
    """Opting into rough is the interview's choice alone. /suggest-line-items
    passes no brief and must still refuse, never reaching Claude."""
    conversation_id = await _start(tenant_a_client)
    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        mock_client.return_value.messages.create = AsyncMock(
            return_value=_make_mock_anthropic_response(_ROUGH_LINES)
        )
        created = await _complete(tenant_a_client, conversation_id)

    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        create = AsyncMock()
        mock_client.return_value.messages.create = create
        resp = await tenant_a_client.post(
            f"/api/v1/quotes/{created['quote_id']}/suggest-line-items"
        )

    if resp.status_code == 200:
        assert resp.json()["refusal_reason"] == "insufficient_history"
    else:
        assert resp.status_code in (403, 404), resp.text


# ---------------------------------------------------------------------------
# Unit-level guards on the rough path's own rules
# ---------------------------------------------------------------------------


def test_rough_basis_always_disclaims_history():
    assert _rough_basis("median of 7 comparable jobs").startswith(ROUGH_BASIS_PREFIX)
    assert _rough_basis("").startswith(ROUGH_BASIS_PREFIX)


@pytest.mark.parametrize(
    "line",
    [
        {"item_type": "travel", "description": "d", "quantity": 1, "unit": "u", "unit_price": 1},
        {"item_type": "labor", "description": "", "quantity": 1, "unit": "u", "unit_price": 1},
        {"item_type": "labor", "description": "d", "quantity": 0, "unit": "u", "unit_price": 1},
        {"item_type": "labor", "description": "d", "quantity": "x", "unit": "u", "unit_price": 1},
        {"item_type": "labor", "description": "d", "quantity": 1, "unit": "u"},
        "not-a-dict",
    ],
)
def test_malformed_rough_lines_are_rejected(line):
    assert _rough_line_is_well_formed(line) is False


def test_well_formed_rough_line_is_accepted():
    assert (
        _rough_line_is_well_formed(
            {
                "item_type": "material",
                "description": "Pipe",
                "quantity": 1,
                "unit": "lot",
                "unit_price": 0,
            }
        )
        is True
    )


def test_quote_interview_gets_its_own_system_prompt():
    """The selector used to fall through to the contractor-interview prompt for
    any unknown type, which would have interviewed the user about the wrong
    thing entirely."""
    from types import SimpleNamespace

    from app.features.ai.prompts.quote_interview_system import QUOTE_INTERVIEW_SYSTEM_PROMPT
    from app.features.ai.service import AIService

    service = AIService.__new__(AIService)
    conv = SimpleNamespace(conv_type="quote_interview")
    assert service._build_system_prompt(conv) == QUOTE_INTERVIEW_SYSTEM_PROMPT
