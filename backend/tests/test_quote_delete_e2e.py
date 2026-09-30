"""Deleting a quote.

Soft delete, because `deleted_at` is the house pattern and every quote list query
already filters on it — so the row disappears from the UI with no read-path change
and survives for audit.

What may NOT be deleted is the substance: an approved quote is the origin of the
jobs or project that approval created, and an invoice, contract or later revision
is a row that points here and needs its explanation to remain. A draft, or a quote
that went nowhere, has no such dependents.
"""

import uuid

import pytest
from httpx import AsyncClient
from sqlalchemy import text

from app.core.database import async_session_factory
from tests.quote_client_helpers import ensure_client

QUOTES_URL = "/api/v1/quotes/"


async def _create_quote(client: AsyncClient, **fields) -> dict:
    payload: dict = {
        "title": "Deletable",
        "line_items": [
            {
                "item_type": "labor",
                "description": "Work",
                "quantity": "1.000",
                "unit": "hour",
                "unit_price": "100.00",
                "sort_order": 0,
            }
        ],
    }
    payload.update(fields)
    resp = await client.post(QUOTES_URL, json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _deleted_at(company_id: str, quote_id: str):
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(
            text("SELECT deleted_at FROM quotes WHERE id = CAST(:qid AS uuid)"),
            {"qid": quote_id},
        )
        return result.scalar_one()


@pytest.mark.asyncio
async def test_draft_quote_is_soft_deleted_and_disappears_from_the_list(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    quote = await _create_quote(tenant_a_client)

    resp = await tenant_a_client.delete(f"{QUOTES_URL}{quote['id']}")
    assert resp.status_code == 204, resp.text

    listed = (await tenant_a_client.get(QUOTES_URL)).json()
    assert all(q["id"] != quote["id"] for q in listed), "deleted quote still listed"

    # Soft, not gone: the row remains for audit.
    assert await _deleted_at(company_id, quote["id"]) is not None


@pytest.mark.asyncio
async def test_a_sent_quote_that_went_nowhere_can_be_deleted(tenant_a_client: AsyncClient):
    """The common cleanup case — sent, never acted on, nothing downstream."""
    client_id = await ensure_client(tenant_a_client)
    quote = await _create_quote(tenant_a_client, client_id=client_id)
    send = await tenant_a_client.post(f"{QUOTES_URL}{quote['id']}/send")
    assert send.status_code == 200, send.text

    resp = await tenant_a_client.delete(f"{QUOTES_URL}{quote['id']}")
    assert resp.status_code == 204, resp.text


@pytest.mark.asyncio
async def test_a_later_revision_blocks_deleting_its_parent(tenant_a_client: AsyncClient):
    """The parent is what the revision is a revision OF."""
    client_id = await ensure_client(tenant_a_client)
    quote = await _create_quote(tenant_a_client, client_id=client_id)
    await tenant_a_client.post(f"{QUOTES_URL}{quote['id']}/send")
    revision = await tenant_a_client.post(f"{QUOTES_URL}{quote['id']}/revise", json={})
    assert revision.status_code in (200, 201), revision.text

    resp = await tenant_a_client.delete(f"{QUOTES_URL}{quote['id']}")
    assert resp.status_code == 409, resp.text
    assert "later revision" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_deleting_a_missing_quote_is_404(tenant_a_client: AsyncClient):
    resp = await tenant_a_client.delete(f"{QUOTES_URL}{uuid.uuid4()}")
    assert resp.status_code == 404, resp.text


@pytest.mark.asyncio
async def test_a_deleted_quote_is_gone_for_reads_too(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """Hiding it from the list but still serving it by id would be a half-delete."""
    quote = await _create_quote(tenant_a_client)
    await tenant_a_client.delete(f"{QUOTES_URL}{quote['id']}")

    fetched = await tenant_a_client.get(f"{QUOTES_URL}{quote['id']}")
    assert fetched.status_code == 404, fetched.text


@pytest.mark.asyncio
async def test_another_tenant_cannot_delete_this_quote(
    tenant_a_client: AsyncClient, tenant_b_client: AsyncClient
):
    quote = await _create_quote(tenant_a_client)

    resp = await tenant_b_client.delete(f"{QUOTES_URL}{quote['id']}")
    assert resp.status_code == 404, resp.text
