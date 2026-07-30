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

import pytest
from httpx import AsyncClient
from sqlalchemy import CheckConstraint, text

# Side-effect: register all mappers before tests run.
import app.features.scheduling.models  # noqa: F401
from app.core.database import async_session_factory
from app.features.quotes.models import QuoteLineItem
from app.features.quotes.service import UNREVIEWED_AI_LINES_DETAIL

_QUOTES_URL = "/api/v1/quotes/"

_MARK_AI_ORIGIN_SQL = (
    "UPDATE quote_line_items SET ai_origin = true, review_state = 'unreviewed', "
    "confidence_band = 'high', basis = :basis WHERE id = CAST(:id AS uuid)"
)

_LINE_ITEM_ROWS_SQL = (
    "SELECT ai_origin, review_state, confidence_band, basis FROM quote_line_items "
    "WHERE quote_id = CAST(:quote_id AS uuid) ORDER BY sort_order"
)


def _line_item(
    description: str = "Test work",
    quantity: str = "1.000",
    unit_price: str = "100.00",
    sort_order: int = 0,
    item_id: str | None = None,
) -> dict:
    """A minimal labor line item body for POST/PATCH /quotes."""
    item: dict = {
        "item_type": "labor",
        "description": description,
        "quantity": quantity,
        "unit": "hr",
        "unit_price": unit_price,
        "sort_order": sort_order,
    }
    if item_id is not None:
        item["id"] = item_id
    return item


async def _create_job(client: AsyncClient) -> str:
    """Create a minimal job in 'quote' status."""
    resp = await client.post(
        "/api/v1/jobs/",
        json={
            "description": "Phase 37 E2E Test Job",
            "trade_type": "electrical",
            "priority": "medium",
        },
    )
    assert resp.status_code == 201, f"Job creation failed: {resp.text}"
    return resp.json()["id"]


async def _create_quote(client: AsyncClient, job_id: str, line_items: list[dict]) -> dict:
    """Create a draft quote for the given job with the given line items."""
    resp = await client.post(
        _QUOTES_URL,
        json={"job_id": job_id, "tax_rate": "0", "line_items": line_items},
    )
    assert resp.status_code == 201, f"Quote creation failed: {resp.text}"
    return resp.json()


async def _patch_quote(client: AsyncClient, quote_id: str, line_items: list[dict]) -> dict:
    """PATCH a draft quote's line items."""
    resp = await client.patch(f"{_QUOTES_URL}{quote_id}", json={"line_items": line_items})
    assert resp.status_code == 200, f"PATCH failed: {resp.text}"
    return resp.json()


async def _get_quote(client: AsyncClient, quote_id: str) -> dict:
    resp = await client.get(f"{_QUOTES_URL}{quote_id}")
    assert resp.status_code == 200, resp.text
    return resp.json()


async def _create_project_quote(client: AsyncClient, line_items: list[dict]) -> dict:
    """Create a project-level draft quote (no job_id, no trade_scope_id)."""
    resp = await client.post(
        _QUOTES_URL,
        json={"title": "Phase 37 project quote", "tax_rate": "0", "line_items": line_items},
    )
    assert resp.status_code == 201, f"Quote creation failed: {resp.text}"
    return resp.json()


async def _mark_ai_origin(
    company_id: str, line_item_id: str, basis: str = "Priced from last 90 days of company history"
) -> None:
    """Seed AI provenance directly — no suggestion endpoint exists yet in this plan.

    Copies the test_phase_36_e2e.py SET LOCAL convention: PostgreSQL rejects a
    parameterized SET LOCAL, so the company id is inlined as an f-string.
    """
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(_MARK_AI_ORIGIN_SQL), {"id": line_item_id, "basis": basis})
        await session.commit()


async def _line_item_rows(company_id: str, quote_id: str) -> list[dict]:
    """Read a quote's line items directly off the DB, bypassing the finance scrub.

    Used to prove the revision copy actually persisted AI provenance columns —
    the API response for a non-finance-view caller would null them out.
    """
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(text(_LINE_ITEM_ROWS_SQL), {"quote_id": quote_id})
        return [dict(row._mapping) for row in result]


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


# ---------------------------------------------------------------------------
# Task 2 — id-keyed reconcile and server-side edited derivation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_line_item_ids_stable_across_patch(tenant_a_client: AsyncClient):
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(
        tenant_a_client,
        job_id,
        [_line_item("First item", sort_order=0), _line_item("Second item", sort_order=1)],
    )
    first_id, second_id = (item["id"] for item in created["line_items"])

    patched = await _patch_quote(
        tenant_a_client,
        created["id"],
        [
            _line_item("First item — revised", sort_order=0, item_id=first_id),
            _line_item("Second item", sort_order=1, item_id=second_id),
        ],
    )

    by_id = {item["id"]: item for item in patched["line_items"]}
    assert set(by_id) == {first_id, second_id}
    assert by_id[first_id]["description"] == "First item — revised"
    assert by_id[second_id]["description"] == "Second item"


@pytest.mark.asyncio
async def test_line_item_field_survives_patch(tenant_a_client: AsyncClient):
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item()])
    item_id = created["line_items"][0]["id"]

    line_item = _line_item("Wired item", item_id=item_id)
    line_item["field"] = "Electrical"
    patched = await _patch_quote(tenant_a_client, created["id"], [line_item])
    assert patched["line_items"][0]["field"] == "Electrical"

    fetched = await _get_quote(tenant_a_client, created["id"])
    assert fetched["line_items"][0]["field"] == "Electrical"


@pytest.mark.asyncio
async def test_line_item_without_id_is_inserted_and_absent_is_deleted(tenant_a_client: AsyncClient):
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(
        tenant_a_client,
        job_id,
        [_line_item("Keep me", sort_order=0), _line_item("Drop me", sort_order=1)],
    )
    keep_id = created["line_items"][0]["id"]

    patched = await _patch_quote(
        tenant_a_client,
        created["id"],
        [
            _line_item("Keep me", sort_order=0, item_id=keep_id),
            _line_item("Brand new", sort_order=1),
        ],
    )

    descriptions = {item["description"] for item in patched["line_items"]}
    assert descriptions == {"Keep me", "Brand new"}
    ids = {item["id"] for item in patched["line_items"]}
    assert keep_id in ids
    assert len(ids) == 2


@pytest.mark.asyncio
async def test_edited_ai_line_is_marked_edited_server_side(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="50.00")])
    item_id = created["line_items"][0]["id"]
    await _mark_ai_origin(company_id, item_id)

    patched = await _patch_quote(
        tenant_a_client,
        created["id"],
        [
            {
                **_line_item(unit_price="65.00", item_id=item_id),
                "review_state": "unreviewed",
            }
        ],
    )

    line = patched["line_items"][0]
    assert line["ai_origin"] is True
    assert line["review_state"] == "edited"


@pytest.mark.asyncio
async def test_accepted_ai_line_records_acceptance(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="50.00")])
    item_id = created["line_items"][0]["id"]
    await _mark_ai_origin(company_id, item_id)

    patched = await _patch_quote(
        tenant_a_client,
        created["id"],
        [
            {
                **_line_item(unit_price="50.00", item_id=item_id),
                "review_state": "accepted",
            }
        ],
    )

    line = patched["line_items"][0]
    assert line["ai_origin"] is True
    assert line["review_state"] == "accepted"


@pytest.mark.asyncio
async def test_non_ai_line_cannot_claim_review_state(tenant_a_client: AsyncClient):
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="50.00")])
    item_id = created["line_items"][0]["id"]

    patched = await _patch_quote(
        tenant_a_client,
        created["id"],
        [
            {
                **_line_item(unit_price="50.00", item_id=item_id),
                "review_state": "accepted",
            }
        ],
    )

    line = patched["line_items"][0]
    assert line["ai_origin"] is False
    assert line["review_state"] == "unreviewed"


# ---------------------------------------------------------------------------
# Task 3 — D-07 send gate, revision provenance, finance scrub
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_send_blocked_by_unreviewed_ai_line(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """KEYSTONE 1: an unreviewed AI line 409s the send, and the quote stays draft."""
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item()])
    item_id = created["line_items"][0]["id"]
    await _mark_ai_origin(company_id, item_id)

    send = await tenant_a_client.post(f"{_QUOTES_URL}{created['id']}/send")
    assert send.status_code == 409, send.text
    assert send.json()["detail"] == UNREVIEWED_AI_LINES_DETAIL

    fetched = await _get_quote(tenant_a_client, created["id"])
    assert fetched["status"] == "draft"


@pytest.mark.asyncio
async def test_send_succeeds_after_every_ai_line_reviewed(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="50.00")])
    item_id = created["line_items"][0]["id"]
    await _mark_ai_origin(company_id, item_id)

    await _patch_quote(
        tenant_a_client,
        created["id"],
        [{**_line_item(unit_price="50.00", item_id=item_id), "review_state": "accepted"}],
    )

    send = await tenant_a_client.post(f"{_QUOTES_URL}{created['id']}/send")
    assert send.status_code == 200, send.text
    assert send.json()["status"] == "sent"


@pytest.mark.asyncio
async def test_send_unchanged_for_hand_built_quote(tenant_a_client: AsyncClient):
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item()])
    send = await tenant_a_client.post(f"{_QUOTES_URL}{created['id']}/send")
    assert send.status_code == 200, send.text
    assert send.json()["status"] == "sent"

    project_quote = await _create_project_quote(tenant_a_client, [_line_item()])
    send_project = await tenant_a_client.post(f"{_QUOTES_URL}{project_quote['id']}/send")
    assert send_project.status_code == 200, send_project.text
    assert send_project.json()["status"] == "sent"
    assert send_project.json()["job_id"] is None


@pytest.mark.asyncio
async def test_revision_copies_ai_provenance_and_resets_review_state(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="50.00")])
    item_id = created["line_items"][0]["id"]
    await _mark_ai_origin(company_id, item_id, basis="Priced from company history")

    await _patch_quote(
        tenant_a_client,
        created["id"],
        [{**_line_item(unit_price="50.00", item_id=item_id), "review_state": "accepted"}],
    )
    send = await tenant_a_client.post(f"{_QUOTES_URL}{created['id']}/send")
    assert send.status_code == 200, send.text

    revise = await tenant_a_client.post(f"{_QUOTES_URL}{created['id']}/revise", json={})
    assert revise.status_code == 201, revise.text

    # Read the new revision's line item off the DB directly — the admin caller
    # in this test has no finance.view, so the API response itself nulls
    # confidence_band/basis (that scrub is proven separately, below).
    rows = await _line_item_rows(company_id, revise.json()["id"])
    assert len(rows) == 1
    new_row = rows[0]
    assert new_row["ai_origin"] is True
    assert new_row["confidence_band"] == "high"
    assert new_row["basis"] == "Priced from company history"
    assert new_row["review_state"] == "unreviewed"


@pytest.mark.asyncio
async def test_line_item_finance_fields_withheld_without_finance_view(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """An admin token holds quotes.view but not finance.view (Phase 30 exclusion)."""
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(
        tenant_a_client, job_id, [_line_item(description="Wired panel", unit_price="50.00")]
    )
    item_id = created["line_items"][0]["id"]
    await _mark_ai_origin(company_id, item_id, basis="Priced from company history")

    fetched = await _get_quote(tenant_a_client, created["id"])
    line = fetched["line_items"][0]
    assert line["confidence_band"] is None
    assert line["basis"] is None
    assert line["description"] == "Wired panel"
    assert line["unit_price"] == "50.00"
