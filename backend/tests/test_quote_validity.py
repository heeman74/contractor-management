"""Phase 29 — quote 'valid today only' behavior + validity statement."""

from datetime import UTC, date, datetime
from types import SimpleNamespace

import pytest

from app.features.pdf.service import pdf_service

_LINE_ITEM = {
    "item_type": "labor",
    "description": "Work",
    "quantity": "1",
    "unit": "hour",
    "unit_price": "100",
}


async def _create_job(client) -> str:
    resp = await client.post(
        "/api/v1/jobs/", json={"description": "Validity job", "trade_type": "plumbing"}
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_quote(client, job_id: str) -> dict:
    resp = await client.post(
        "/api/v1/quotes/",
        json={"job_id": job_id, "tax_rate": "0", "line_items": [_LINE_ITEM]},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


@pytest.mark.asyncio
async def test_send_quote_defaults_expiry_to_today(tenant_a_client, seed_two_tenants):
    """Sending a quote with no expiry defaults it to today (valid today only)."""
    job_id = await _create_job(tenant_a_client)
    quote = await _create_quote(tenant_a_client, job_id)
    assert quote["expiry_date"] is None

    send = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert send.status_code == 200, send.text

    got = await tenant_a_client.get(f"/api/v1/quotes/{quote['id']}")
    assert got.status_code == 200
    # Service uses UTC (matches the codebase) — compare on the same basis.
    assert got.json()["expiry_date"] == datetime.now(UTC).date().isoformat()


def test_validity_statement_mentions_the_expiry_date():
    quote = SimpleNamespace(expiry_date=date(2026, 7, 24))
    statement = pdf_service.quote_validity_statement(quote)
    assert "July 24, 2026" in statement
    assert "day it was issued" in statement


def test_validity_statement_without_expiry():
    quote = SimpleNamespace(expiry_date=None)
    assert "day it was issued" in pdf_service.quote_validity_statement(quote)
