"""Phase 16 — Quotes & Invoices: Integration tests for list endpoints and amount_paid.

Tests cover:
- GET /api/v1/quotes/       — list all active quotes (admin only)
- GET /api/v1/invoices/     — list all invoices (admin only)
- status query param filtering for both endpoints
- amount_paid field present in InvoiceResponse
- PATCH /api/v1/invoices/{id}/payment with amount_paid

Strategy:
- Uses tenant_a_client fixture (admin JWT Bearer token pre-set).
- Uses seed_two_tenants fixture where user_id is needed to assign roles.
- Creates real DB state via API calls (no fixture injection).
- All tests are @pytest.mark.anyio async tests — NO @pytest.mark.skip stubs.
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient

# Side-effect: register all mappers before tests run.
import app.features.scheduling.models  # noqa: F401


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _create_job(client: AsyncClient) -> dict:
    """Create a minimal job in 'quote' status."""
    resp = await client.post(
        "/api/v1/jobs/",
        json={
            "description": "Phase 16 E2E Test Job",
            "trade_type": "plumbing",
            "priority": "medium",
        },
    )
    assert resp.status_code == 201, f"Job creation failed: {resp.text}"
    return resp.json()


async def _create_quote(client: AsyncClient, job_id: str) -> dict:
    """Create a draft quote for the given job."""
    resp = await client.post(
        "/api/v1/quotes/",
        json={
            "job_id": job_id,
            "tax_rate": "10.00",
            "line_items": [
                {
                    "item_type": "labor",
                    "description": "Test work",
                    "quantity": "1.000",
                    "unit": "hr",
                    "unit_price": "100.00",
                    "sort_order": 0,
                }
            ],
        },
    )
    assert resp.status_code == 201, f"Quote creation failed: {resp.text}"
    return resp.json()


async def _add_client_role(client: AsyncClient, user_id: str) -> None:
    """Assign 'client' role so admin can also approve quotes in tests."""
    resp = await client.post(
        f"/api/v1/users/{user_id}/roles",
        json={"user_id": user_id, "role": "client"},
    )
    assert resp.status_code in (200, 201, 409), f"Role assign failed: {resp.text}"


async def _transition_job(client: AsyncClient, job_id: str, new_status: str, version: int) -> dict:
    """Transition a job to the given status."""
    resp = await client.patch(
        f"/api/v1/jobs/{job_id}/transition",
        json={"new_status": new_status, "version": version},
    )
    assert resp.status_code == 200, f"Transition to {new_status} failed: {resp.text}"
    return resp.json()


async def _setup_invoice(client: AsyncClient, user_id: str) -> dict:
    """Full flow: create job → quote → approve → complete → generate invoice.

    Returns the generated invoice dict.
    Re-logins after adding client role to get a token that includes it.
    """
    from httpx import ASGITransport, AsyncClient as _AsyncClient

    from app.main import app as _fastapi_app

    # Assign client role so admin user can also approve quotes
    await _add_client_role(client, user_id)

    # Re-login to get a fresh token that includes the 'client' role
    login_resp = await client.post(
        "/api/v1/auth/login",
        json={"email": "admin@tenant-a.com", "password": "TestPass123!"},
    )
    assert login_resp.status_code == 200, f"Re-login failed: {login_resp.text}"
    new_token = login_resp.json()["access_token"]

    # Create job in 'quote' status (still using admin client — admin role required)
    job = await _create_job(client)
    job_id = job["id"]

    # Create draft quote
    quote = await _create_quote(client, job_id)
    quote_id = quote["id"]

    # Send quote to client (admin operation)
    resp = await client.post(f"/api/v1/quotes/{quote_id}/send")
    assert resp.status_code == 200, f"Send quote failed: {resp.text}"

    # Approve quote using fresh token (which now includes client role)
    async with _AsyncClient(
        transport=ASGITransport(app=_fastapi_app),
        base_url="http://test",
        headers={"Authorization": f"Bearer {new_token}"},
    ) as client_with_client_role:
        resp = await client_with_client_role.post(f"/api/v1/quotes/{quote_id}/approve")
        assert resp.status_code == 200, f"Approve quote failed: {resp.text}"

    # Transition job: quote → scheduled → in_progress → complete (admin operation)
    job = await _transition_job(client, job_id, "scheduled", job["version"])
    job = await _transition_job(client, job_id, "in_progress", job["version"])
    job = await _transition_job(client, job_id, "complete", job["version"])

    # Generate invoice from approved quote (admin operation)
    resp = await client.post(f"/api/v1/invoices/generate/{job_id}")
    assert resp.status_code == 201, f"Invoice generation failed: {resp.text}"
    return resp.json()


# ---------------------------------------------------------------------------
# List endpoint tests
# ---------------------------------------------------------------------------


@pytest.mark.anyio
async def test_list_quotes_returns_200(tenant_a_client: AsyncClient) -> None:
    """GET /api/v1/quotes/ returns 200 with a list (may be empty)."""
    resp = await tenant_a_client.get("/api/v1/quotes/")
    assert resp.status_code == 200, resp.text
    assert isinstance(resp.json(), list)


@pytest.mark.anyio
async def test_list_invoices_returns_200(tenant_a_client: AsyncClient) -> None:
    """GET /api/v1/invoices/ returns 200 with a list (may be empty)."""
    resp = await tenant_a_client.get("/api/v1/invoices/")
    assert resp.status_code == 200, resp.text
    assert isinstance(resp.json(), list)


@pytest.mark.anyio
async def test_list_quotes_with_status_filter(tenant_a_client: AsyncClient) -> None:
    """Create a draft quote; verify ?status=draft returns it and ?status=approved returns empty."""
    job = await _create_job(tenant_a_client)
    quote = await _create_quote(tenant_a_client, job["id"])

    # Filter by draft — should find the created quote
    resp = await tenant_a_client.get("/api/v1/quotes/?status=draft")
    assert resp.status_code == 200, resp.text
    quotes = resp.json()
    assert isinstance(quotes, list)
    ids = [q["id"] for q in quotes]
    assert quote["id"] in ids, f"Expected quote {quote['id']} in draft list, got: {ids}"

    # Filter by approved — should be empty (quote is still draft)
    resp = await tenant_a_client.get("/api/v1/quotes/?status=approved")
    assert resp.status_code == 200, resp.text
    assert resp.json() == [], f"Expected empty approved list, got: {resp.json()}"


@pytest.mark.anyio
async def test_list_invoices_with_status_filter(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Create an invoice; verify ?status=unpaid returns it and ?status=paid returns empty."""
    user_id = seed_two_tenants["tenant_a_user_id"]
    invoice = await _setup_invoice(tenant_a_client, user_id)

    # Filter by unpaid — should find the created invoice
    resp = await tenant_a_client.get("/api/v1/invoices/?status=unpaid")
    assert resp.status_code == 200, resp.text
    invoices = resp.json()
    assert isinstance(invoices, list)
    ids = [i["id"] for i in invoices]
    assert invoice["id"] in ids, f"Expected invoice {invoice['id']} in unpaid list, got: {ids}"

    # Filter by paid — should be empty (invoice is still unpaid)
    resp = await tenant_a_client.get("/api/v1/invoices/?status=paid")
    assert resp.status_code == 200, resp.text
    assert resp.json() == [], f"Expected empty paid list, got: {resp.json()}"


@pytest.mark.anyio
async def test_amount_paid_in_invoice_response(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Invoice response includes amount_paid field with default value 0."""
    user_id = seed_two_tenants["tenant_a_user_id"]
    invoice = await _setup_invoice(tenant_a_client, user_id)

    # amount_paid field must be present
    assert "amount_paid" in invoice, f"amount_paid missing from invoice response: {invoice}"

    # Default value should be 0 (may be string "0" or "0.00" depending on Decimal serialization)
    amount_paid_str = str(invoice["amount_paid"])
    assert float(amount_paid_str) == 0.0, f"Expected amount_paid=0, got: {invoice['amount_paid']}"


@pytest.mark.anyio
async def test_mark_paid_with_amount(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """PATCH /invoices/{id}/payment with amount_paid stores value in response."""
    user_id = seed_two_tenants["tenant_a_user_id"]
    invoice = await _setup_invoice(tenant_a_client, user_id)
    invoice_id = invoice["id"]

    # Mark as partially_paid with a specific amount
    resp = await tenant_a_client.patch(
        f"/api/v1/invoices/{invoice_id}/payment",
        json={"status": "partially_paid", "amount_paid": 500.00},
    )
    assert resp.status_code == 200, f"Payment update failed: {resp.text}"

    data = resp.json()
    assert data["status"] == "partially_paid", f"Expected partially_paid, got: {data['status']}"
    assert "amount_paid" in data, f"amount_paid missing from payment response: {data}"
    assert float(data["amount_paid"]) == 500.0, (
        f"Expected amount_paid=500.0, got: {data['amount_paid']}"
    )
