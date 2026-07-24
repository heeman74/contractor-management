"""Phase 29-02 E2E — contract e-signature with a mocked provider.

A fake SignatureProvider is injected via dependency override so no network calls
occur. Covers send, the HMAC-verified webhook (signed-PDF persistence), tokenized
public access, and signed-PDF download authorization.
"""

import json
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.security import create_access_token
from app.features.contracts.providers import get_signature_provider
from app.features.contracts.providers.base import ProviderRequest, WebhookEvent
from app.features.pdf.service import PdfService
from app.main import app as _app

# isort: split
import app.features.scheduling.models  # noqa: F401  register mappers

pytestmark = pytest.mark.asyncio

_TRANSPORT = ASGITransport(app=_app)
_LINE_ITEM = {
    "item_type": "labor",
    "description": "Install fixtures",
    "quantity": "2",
    "unit": "hour",
    "unit_price": "150",
}


class _FakeProvider:
    """Deterministic in-memory e-sign provider for tests."""

    async def create_embedded_request(self, **_kwargs) -> ProviderRequest:
        return ProviderRequest(
            request_id="req_test", signature_id="sig_test", sign_url="https://sign.test/embed"
        )

    async def get_sign_url(self, signature_id: str) -> str:
        return f"https://sign.test/embed/{signature_id}"

    async def get_signed_pdf(self, request_id: str) -> bytes:
        return b"%PDF-1.4 signed"

    def verify_and_parse_webhook(self, headers, raw_body):
        body = json.loads(raw_body)
        if not body.get("valid"):
            return None
        return WebhookEvent(
            event_type=body["event_type"],
            request_id=body["request_id"],
            metadata=body.get("metadata", {}),
        )


@pytest.fixture(autouse=True)
def _stub_pdf_and_provider(monkeypatch):
    monkeypatch.setattr(PdfService, "_html_to_pdf", staticmethod(lambda html: b"%PDF-1.4 test"))
    _app.dependency_overrides[get_signature_provider] = lambda: _FakeProvider()
    yield
    _app.dependency_overrides.pop(get_signature_provider, None)


async def _create_quote(client, job_id: str) -> dict:
    resp = await client.post(
        "/api/v1/quotes/",
        json={"job_id": job_id, "tax_rate": "0", "line_items": [_LINE_ITEM]},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _sent_contract(tenant_a_client, seed_two_tenants) -> dict:
    """Approve a quote, generate a contract, send it. Returns the send response."""
    user_id = seed_two_tenants["tenant_a_user_id"]
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
    quote = await _create_quote(tenant_a_client, job.json()["id"])
    await tenant_a_client.post(f"/api/v1/quotes/{quote['id']}/send")
    async with AsyncClient(
        transport=_TRANSPORT,
        base_url="http://test",
        headers={"Authorization": f"Bearer {client_token}"},
    ) as client_ac:
        await client_ac.get(f"/api/v1/quotes/{quote['id']}")
        await client_ac.post(f"/api/v1/quotes/{quote['id']}/approve")

    gen = await tenant_a_client.post("/api/v1/contracts", json={"quote_id": quote["id"]})
    assert gen.status_code == 201, gen.text
    contract_id = gen.json()["id"]

    send = await tenant_a_client.post(f"/api/v1/contracts/{contract_id}/send")
    assert send.status_code == 200, send.text
    return send.json()


async def test_send_creates_signature_request(tenant_a_client, seed_two_tenants):
    result = await _sent_contract(tenant_a_client, seed_two_tenants)
    assert result["sign_url"] == "https://sign.test/embed"
    assert "/sign/" in result["magic_link"]
    assert result["contract"]["status"] == "sent"
    assert result["contract"]["provider_request_id"] == "req_test"


async def test_webhook_signed_persists_pdf_and_marks_signed(
    async_client, tenant_a_client, seed_two_tenants
):
    result = await _sent_contract(tenant_a_client, seed_two_tenants)
    contract_id = result["contract"]["id"]
    company_id = seed_two_tenants["tenant_a_id"]

    body = json.dumps(
        {
            "valid": True,
            "event_type": "signature_request_all_signed",
            "request_id": "req_test",
            "metadata": {"company_id": company_id, "contract_id": contract_id},
        }
    )
    hook = await async_client.post("/api/v1/contracts/webhook/dropbox-sign", content=body)
    assert hook.status_code == 200, hook.text

    got = await tenant_a_client.get(f"/api/v1/contracts/{contract_id}")
    assert got.json()["status"] == "signed"
    assert got.json()["signed_pdf_url"] is not None


async def test_webhook_invalid_signature_rejected(async_client, tenant_a_client, seed_two_tenants):
    result = await _sent_contract(tenant_a_client, seed_two_tenants)
    contract_id = result["contract"]["id"]
    body = json.dumps({"valid": False, "event_type": "signature_request_all_signed"})
    hook = await async_client.post("/api/v1/contracts/webhook/dropbox-sign", content=body)
    assert hook.status_code == 400, hook.text

    got = await tenant_a_client.get(f"/api/v1/contracts/{contract_id}")
    assert got.json()["status"] == "sent"  # unchanged


async def test_public_view_with_token(async_client, tenant_a_client, seed_two_tenants):
    result = await _sent_contract(tenant_a_client, seed_two_tenants)
    token = result["magic_link"].rsplit("/sign/", 1)[1]

    resp = await async_client.get(f"/api/v1/public/contracts/{token}")
    assert resp.status_code == 200, resp.text
    view = resp.json()
    assert view["contract_id"] == result["contract"]["id"]
    assert "ATTORNEY REVIEW REQUIRED" in view["terms_snapshot"]
    assert view["sign_url"]

    bad = await async_client.get("/api/v1/public/contracts/not-a-valid-token")
    assert bad.status_code == 401


async def test_signed_pdf_download_authorization(async_client, tenant_a_client, seed_two_tenants):
    result = await _sent_contract(tenant_a_client, seed_two_tenants)
    contract_id = result["contract"]["id"]
    company_id = seed_two_tenants["tenant_a_id"]

    body = json.dumps(
        {
            "valid": True,
            "event_type": "signature_request_all_signed",
            "request_id": "req_test",
            "metadata": {"company_id": company_id, "contract_id": contract_id},
        }
    )
    await async_client.post("/api/v1/contracts/webhook/dropbox-sign", content=body)

    # Admin (contracts.manage) can download.
    admin_dl = await tenant_a_client.get(f"/api/v1/contracts/{contract_id}/signed.pdf")
    assert admin_dl.status_code == 200
    assert admin_dl.headers["content-type"] == "application/pdf"

    # An unrelated contractor (no contracts.manage, not the signer) cannot.
    contractor_token = create_access_token(uuid4(), UUID(company_id), ["contractor"])
    other = await async_client.get(
        f"/api/v1/contracts/{contract_id}/signed.pdf",
        headers={"Authorization": f"Bearer {contractor_token}"},
    )
    assert other.status_code == 403
