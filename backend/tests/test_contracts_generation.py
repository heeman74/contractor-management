"""Phase 29 — contract generation from an approved quote (29-01).

WeasyPrint is not installed in this environment, so PDF rendering is patched; the Jinja
template still renders (so template errors surface), only the HTML->PDF step is stubbed.
"""

import pytest
from httpx import ASGITransport, AsyncClient

from app.features.pdf.service import PdfService
from app.main import app as _app

# isort: split
import app.features.scheduling.models  # noqa: F401  register mappers before tests

pytestmark = pytest.mark.asyncio

_TRANSPORT = ASGITransport(app=_app)
_LINE_ITEM = {
    "item_type": "labor",
    "description": "Install fixtures",
    "quantity": "2",
    "unit": "hour",
    "unit_price": "150",
}


@pytest.fixture(autouse=True)
def _stub_pdf(monkeypatch):
    """Stub the HTML->PDF step (no libpango in this env)."""
    monkeypatch.setattr(PdfService, "_html_to_pdf", staticmethod(lambda html: b"%PDF-1.4 test"))


async def _create_quote(client, job_id: str) -> dict:
    resp = await client.post(
        "/api/v1/quotes/",
        json={"job_id": job_id, "tax_rate": "0", "line_items": [_LINE_ITEM]},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _approved_quote(tenant_a_client, seed_two_tenants) -> dict:
    """Set up an approved quote whose job is owned by a client, and return it."""
    user_id = seed_two_tenants["tenant_a_user_id"]
    # Give the admin the client role so a second token can approve.
    await tenant_a_client.post(
        f"/api/v1/users/{user_id}/roles", json={"user_id": user_id, "role": "client"}
    )
    login = await tenant_a_client.post(
        "/api/v1/auth/login",
        json={"email": "admin@tenant-a.com", "password": "TestPass123!"},
    )
    client_token = login.json()["access_token"]

    job = await tenant_a_client.post(
        "/api/v1/jobs/",
        json={"description": "Kitchen remodel", "trade_type": "plumbing", "client_id": user_id},
    )
    assert job.status_code == 201, job.text
    quote = await _create_quote(tenant_a_client, job.json()["id"])
    send = await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    assert send.status_code == 200, send.text

    async with AsyncClient(
        transport=_TRANSPORT,
        base_url="http://test",
        headers={"Authorization": f"Bearer {client_token}"},
    ) as client_ac:
        await client_ac.get(f"/api/v1/quotes/{quote['id']}")  # record view
        approve = await client_ac.post(f"/api/v1/quotes/{quote['id']}/approve")
        assert approve.status_code == 200, approve.text
    return quote


async def test_generate_contract_from_approved_quote(tenant_a_client, seed_two_tenants):
    quote = await _approved_quote(tenant_a_client, seed_two_tenants)

    gen = await tenant_a_client.post("/api/v1/contracts", json={"quote_id": quote["id"]})
    assert gen.status_code == 201, gen.text
    contract = gen.json()

    assert contract["status"] == "draft"
    assert contract["quote_id"] == quote["id"]
    assert contract["unsigned_pdf_url"] is not None
    assert "/files/contracts/" in contract["unsigned_pdf_url"]
    # Terms were merged from the CA-structured default template + the client identity.
    terms = contract["terms_snapshot"].lower()
    assert "right to cancel" in terms
    assert "admin@tenant-a.com" in contract["terms_snapshot"]  # client name (email fallback)
    assert contract["validity_statement"]


async def test_generate_requires_approved_quote(tenant_a_client, seed_two_tenants):
    """A draft (non-approved) quote cannot be turned into a contract."""
    job = await tenant_a_client.post(
        "/api/v1/jobs/", json={"description": "x", "trade_type": "plumbing"}
    )
    quote = await _create_quote(tenant_a_client, job.json()["id"])
    gen = await tenant_a_client.post("/api/v1/contracts", json={"quote_id": quote["id"]})
    assert gen.status_code == 409, gen.text


async def test_new_company_gets_default_terms_template(tenant_a_client, seed_two_tenants):
    resp = await tenant_a_client.get("/api/v1/contract-template")
    assert resp.status_code == 200, resp.text
    body = resp.json()["body"]
    assert "ATTORNEY REVIEW REQUIRED" in body
    assert "{{client_name}}" in body
