"""Phase 29 — contract generation from an approved quote (29-01).

WeasyPrint is not installed in this environment, so PDF rendering is patched; the Jinja
template still renders (so template errors surface), only the HTML->PDF step is stubbed.
"""

import re

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
    assert "HOME IMPROVEMENT CONTRACT" in body
    assert "{{client_name}}" in body


# ---------------------------------------------------------------------------
# The CSLB sample contract
#
# The template follows the Contractors State License Board's published sample,
# which is the structure California expects. The statutory notices are the part
# a contractor may not paraphrase, so their presence is asserted rather than
# assumed: a contract that quietly lost the mechanics lien warning or the
# downpayment cap is worse than one that was never generated.
# ---------------------------------------------------------------------------

_REQUIRED_STATUTORY_TEXT = [
    "THE DOWNPAYMENT MAY NOT EXCEED $1,000 OR 10 PERCENT",
    "IT IS AGAINST THE LAW FOR A CONTRACTOR TO COLLECT PAYMENT",
    "MECHANICS LIEN WARNING",
    "YOU ARE ENTITLED TO A COMPLETELY FILLED IN COPY",
    "THREE-DAY RIGHT TO CANCEL",
    "NOTICE OF CANCELLATION",
    "CONTRACTORS STATE LICENSE BOARD",
    "800-321-CSLB",
    "Sections 8400 and 8404 of the Civil Code",
    "Sections 1689.5 to 1689.14",
]


@pytest.mark.parametrize("required", _REQUIRED_STATUTORY_TEXT)
async def test_generated_contract_carries_the_statutory_notices(
    tenant_a_client, seed_two_tenants, required
):
    quote = await _approved_quote(tenant_a_client, seed_two_tenants)
    gen = await tenant_a_client.post("/api/v1/contracts", json={"quote_id": quote["id"]})
    assert gen.status_code == 201, gen.text

    assert required in gen.json()["terms_snapshot"]


async def test_generated_contract_resolves_every_merge_field(tenant_a_client, seed_two_tenants):
    """An unresolved {{field}} would be printed to a client as-is."""
    quote = await _approved_quote(tenant_a_client, seed_two_tenants)
    gen = await tenant_a_client.post("/api/v1/contracts", json={"quote_id": quote["id"]})
    assert gen.status_code == 201, gen.text

    terms = gen.json()["terms_snapshot"]
    assert "{{" not in terms, "a placeholder reached the contract"
    assert "}}" not in terms


async def test_the_contract_cites_a_quote_number_a_person_can_look_up(
    tenant_a_client, seed_two_tenants
):
    """It cited the row id, so the contract referred to a quote nobody could find."""
    quote = await _approved_quote(tenant_a_client, seed_two_tenants)
    gen = await tenant_a_client.post("/api/v1/contracts", json={"quote_id": quote["id"]})
    assert gen.status_code == 201, gen.text

    terms = gen.json()["terms_snapshot"]
    assert f"Quote #{quote['quote_number']}" in terms
    assert quote["id"] not in terms, "the uuid is not a reference a client can use"


async def test_the_contract_gives_an_address_a_cancellation_can_be_sent_to(
    tenant_a_client, seed_two_tenants
):
    """CSLB requires one: the notice of cancellation may be emailed to it."""
    company_id = seed_two_tenants["tenant_a_id"]
    await tenant_a_client.patch(
        f"/api/v1/companies/{company_id}",
        json={"email_from_address": "cancel@acme.com"},
    )
    quote = await _approved_quote(tenant_a_client, seed_two_tenants)

    gen = await tenant_a_client.post("/api/v1/contracts", json={"quote_id": quote["id"]})
    assert gen.status_code == 201, gen.text

    assert "cancel@acme.com" in gen.json()["terms_snapshot"]


async def test_an_unconfigured_email_shows_a_blank_not_an_empty_space(
    tenant_a_client, seed_two_tenants
):
    """A missing required field has to look missing, so it gets filled in by hand."""
    quote = await _approved_quote(tenant_a_client, seed_two_tenants)
    gen = await tenant_a_client.post("/api/v1/contracts", json={"quote_id": quote["id"]})
    assert gen.status_code == 201, gen.text

    terms = gen.json()["terms_snapshot"]
    # Whitespace-tolerant: the template wraps, so the value may begin a new line.
    assert re.search(r"email:\s*_{4,}", terms), "the blank should be visible"


async def test_the_three_cancellation_periods_are_each_labelled_with_when_to_use_them(
    tenant_a_client, seed_two_tenants
):
    """Only one applies to a given contract, so the conditions stay attached."""
    quote = await _approved_quote(tenant_a_client, seed_two_tenants)
    gen = await tenant_a_client.post("/api/v1/contracts", json={"quote_id": quote["id"]})
    terms = gen.json()["terms_snapshot"]

    assert "USE THESE NOTICES IF EITHER CONTRACTING OWNER IS\n65 YEARS OR OLDER" in terms or (
        "USE THESE NOTICES IF EITHER CONTRACTING OWNER IS" in terms
    )
    assert "FIVE-DAY RIGHT TO CANCEL" in terms
    assert "SEVEN-DAY RIGHT TO CANCEL" in terms
    assert "STATE OF EMERGENCY HAS BEEN DECLARED" in terms
