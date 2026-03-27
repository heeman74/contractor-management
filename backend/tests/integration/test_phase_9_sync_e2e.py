"""Phase 9 — Sync Engine Gap Closure: Integration tests for sync endpoint completeness.

Tests prove:
- INFRA-04: sync endpoint returns all 15 entity type keys including quote_line_items
  and invoice_line_items as flat arrays
- BIZ-01: quote_line_items are flat arrays with quote_id FK, not nested inside quotes
- BIZ-03: invoice_line_items are flat arrays with invoice_id FK, not nested inside invoices
- FIELD-02: job response includes GPS fields (gps_latitude, gps_longitude, gps_address)

Strategy:
- Use tenant_a_client fixture (authenticated admin) and seed_two_tenants for data.
- GET /api/v1/sync and verify response keys and structure.
- Create quotes/invoices via API to verify flat line item arrays.
"""

from __future__ import annotations

import uuid

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app as _fastapi_app

# isort: split
# Side-effect: register all mappers before tests run
import app.features.invoices.models
import app.features.quotes.models
import app.features.scheduling.models  # noqa: F401

TRANSPORT = ASGITransport(app=_fastapi_app)

# All 15 expected entity type keys plus server_timestamp
_EXPECTED_KEYS = {
    "companies",
    "users",
    "user_roles",
    "jobs",
    "bookings",
    "job_sites",
    "job_notes",
    "time_entries",
    "attachments",
    "client_profiles",
    "job_requests",
    "quotes",
    "quote_line_items",
    "invoices",
    "invoice_line_items",
    "server_timestamp",
}

_LIST_KEYS = _EXPECTED_KEYS - {"server_timestamp"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _create_job(client: AsyncClient) -> dict:
    """Create a minimal job via the jobs API."""
    resp = await client.post(
        "/api/v1/jobs/",
        json={
            "description": f"Phase 9 sync test job {uuid.uuid4().hex[:6]}",
            "trade_type": "plumbing",
            "priority": "medium",
        },
    )
    assert resp.status_code == 201, f"Job create failed: {resp.text}"
    return resp.json()


async def _create_quote_with_line_items(client: AsyncClient, job_id: str) -> dict:
    """Create a quote with 2 line items via the quotes API."""
    resp = await client.post(
        "/api/v1/quotes/",
        json={
            "job_id": job_id,
            "tax_rate": "10.00",
            "line_items": [
                {
                    "item_type": "labor",
                    "description": "Installation work",
                    "quantity": "2.000",
                    "unit": "hours",
                    "unit_price": "75.00",
                    "sort_order": 0,
                },
                {
                    "item_type": "material",
                    "description": "Copper pipe",
                    "quantity": "5.000",
                    "unit": "meters",
                    "unit_price": "12.50",
                    "sort_order": 1,
                },
            ],
        },
    )
    assert resp.status_code == 201, f"Quote create failed: {resp.text}"
    return resp.json()


async def _transition_job(client: AsyncClient, job_id: str, new_status: str) -> dict:
    """Transition a job to a new status."""
    job_resp = await client.get(f"/api/v1/jobs/{job_id}")
    assert job_resp.status_code == 200, f"Job fetch failed: {job_resp.text}"
    version = job_resp.json().get("version", 1)
    tr = await client.patch(
        f"/api/v1/jobs/{job_id}/transition",
        json={"new_status": new_status, "version": version},
    )
    assert tr.status_code == 200, f"Transition to {new_status} failed: {tr.text}"
    return tr.json()


async def _create_invoice_via_generate(
    admin_token: str, user_id: str, job_id: str, quote_id: str
) -> dict:
    """Generate an invoice from a completed job with an approved quote.

    Flow: send quote -> add client role to admin user -> re-login -> approve quote
    -> transition job to in_progress -> complete -> generate invoice.
    Returns the generated invoice dict.
    """
    async with AsyncClient(
        transport=TRANSPORT,
        base_url="http://test",
        headers={"Authorization": f"Bearer {admin_token}"},
    ) as ac:
        # Send the quote
        send_resp = await ac.post(f"/api/v1/quotes/{quote_id}/send")
        assert send_resp.status_code == 200, f"Quote send failed: {send_resp.text}"

        # Add client role to admin user so they can approve the quote
        role_resp = await ac.post(
            f"/api/v1/users/{user_id}/roles",
            json={"user_id": user_id, "role": "client"},
        )
        assert role_resp.status_code in (200, 201, 409), f"Role assign failed: {role_resp.text}"

        # Re-login to get token with both admin + client roles
        login_resp = await ac.post(
            "/api/v1/auth/login",
            json={"email": "admin@tenant-a.com", "password": "TestPass123!"},
        )
        assert login_resp.status_code == 200, f"Login failed: {login_resp.text}"
        new_token = login_resp.json()["access_token"]

    # Approve the quote + complete the job using refreshed token
    async with AsyncClient(
        transport=TRANSPORT,
        base_url="http://test",
        headers={"Authorization": f"Bearer {new_token}"},
    ) as new_client:
        approve_resp = await new_client.post(f"/api/v1/quotes/{quote_id}/approve")
        assert approve_resp.status_code == 200, f"Quote approve failed: {approve_resp.text}"

        # Transition job: scheduled/quote -> in_progress -> complete
        await _transition_job(new_client, job_id, "in_progress")
        await _transition_job(new_client, job_id, "complete")

        # Generate invoice
        gen_resp = await new_client.post(f"/api/v1/invoices/generate/{job_id}")
        assert gen_resp.status_code == 201, f"Invoice generate failed: {gen_resp.text}"
        return gen_resp.json()


# ---------------------------------------------------------------------------
# Test 1: Sync response contains all 15 entity type keys
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_sync_response_contains_all_entity_type_keys(seed_two_tenants: dict) -> None:
    """GET /api/v1/sync returns all 15 entity type keys as lists plus server_timestamp.

    Covers: INFRA-04 — sync endpoint completeness.
    """
    token = seed_two_tenants["tenant_a_token"]
    async with AsyncClient(
        transport=TRANSPORT,
        base_url="http://test",
        headers={"Authorization": f"Bearer {token}"},
    ) as ac:
        resp = await ac.get("/api/v1/sync")

    assert resp.status_code == 200, f"Sync failed: {resp.text}"
    data = resp.json()

    # All 15 entity keys + server_timestamp must be present
    assert _EXPECTED_KEYS.issubset(data.keys()), (
        f"Missing keys: {_EXPECTED_KEYS - set(data.keys())}"
    )

    # All entity type values must be lists (even if empty)
    for key in _LIST_KEYS:
        assert isinstance(data[key], list), (
            f"Expected '{key}' to be a list, got {type(data[key]).__name__}"
        )

    # server_timestamp must be a non-empty string
    assert isinstance(data["server_timestamp"], str)
    assert len(data["server_timestamp"]) > 0


# ---------------------------------------------------------------------------
# Test 2: quote_line_items returned as flat arrays (BIZ-01)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_sync_quote_line_items_are_flat_arrays(seed_two_tenants: dict) -> None:
    """quote_line_items in sync response is a flat list with quote_id FK.

    Covers: BIZ-01 — quote line items are flat (not nested inside quotes).
    Each line item must have a quote_id field matching its parent quote.
    """
    token = seed_two_tenants["tenant_a_token"]
    async with AsyncClient(
        transport=TRANSPORT,
        base_url="http://test",
        headers={"Authorization": f"Bearer {token}"},
    ) as ac:
        # Create a job and quote with 2 line items
        job = await _create_job(ac)
        quote = await _create_quote_with_line_items(ac, job["id"])
        quote_id = quote["id"]

        resp = await ac.get("/api/v1/sync")

    assert resp.status_code == 200, f"Sync failed: {resp.text}"
    data = resp.json()

    # quote_line_items must be a flat list
    assert isinstance(data["quote_line_items"], list), (
        f"Expected 'quote_line_items' to be a list, got {type(data['quote_line_items']).__name__}"
    )

    # Filter line items belonging to our test quote
    test_quote_items = [li for li in data["quote_line_items"] if li.get("quote_id") == quote_id]
    assert len(test_quote_items) >= 2, (
        f"Expected at least 2 line items for quote {quote_id}, got {len(test_quote_items)}"
    )

    # Each line item must have quote_id as a field
    for item in test_quote_items:
        assert "quote_id" in item, f"Line item missing 'quote_id' field: {item}"
        assert item["quote_id"] == quote_id, (
            f"Line item quote_id {item['quote_id']} doesn't match parent {quote_id}"
        )


# ---------------------------------------------------------------------------
# Test 3: invoice_line_items returned as flat arrays (BIZ-03)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_sync_invoice_line_items_are_flat_arrays(seed_two_tenants: dict) -> None:
    """invoice_line_items in sync response is a flat list with invoice_id FK.

    Covers: BIZ-03 — invoice line items are flat (not nested inside invoices).
    Each line item must have an invoice_id field matching its parent invoice.

    Flow: create job -> quote with 2 line items -> send -> approve -> complete job
    -> generate invoice from approved quote -> sync.
    """
    token = seed_two_tenants["tenant_a_token"]
    user_id = seed_two_tenants["tenant_a_user_id"]

    async with AsyncClient(
        transport=TRANSPORT,
        base_url="http://test",
        headers={"Authorization": f"Bearer {token}"},
    ) as ac:
        # Create a job and a quote (the quote's line items will be copied to invoice)
        job = await _create_job(ac)
        quote = await _create_quote_with_line_items(ac, job["id"])

    invoice = await _create_invoice_via_generate(token, user_id, job["id"], quote["id"])
    invoice_id = invoice["id"]

    # Sync as admin
    async with AsyncClient(
        transport=TRANSPORT,
        base_url="http://test",
        headers={"Authorization": f"Bearer {token}"},
    ) as ac:
        resp = await ac.get("/api/v1/sync")

    assert resp.status_code == 200, f"Sync failed: {resp.text}"
    data = resp.json()

    # invoice_line_items must be a flat list
    assert isinstance(data["invoice_line_items"], list), (
        f"Expected 'invoice_line_items' to be a list, "
        f"got {type(data['invoice_line_items']).__name__}"
    )

    # Filter line items belonging to our test invoice
    test_invoice_items = [
        li for li in data["invoice_line_items"] if li.get("invoice_id") == invoice_id
    ]
    assert len(test_invoice_items) >= 1, (
        f"Expected at least 1 line item for invoice {invoice_id}, "
        f"got {len(test_invoice_items)}. "
        f"All invoice_line_items: {data['invoice_line_items']}"
    )

    # Each line item must have invoice_id as a field
    for item in test_invoice_items:
        assert "invoice_id" in item, f"Line item missing 'invoice_id' field: {item}"
        assert item["invoice_id"] == invoice_id, (
            f"Line item invoice_id {item['invoice_id']} doesn't match parent {invoice_id}"
        )


# ---------------------------------------------------------------------------
# Test 4: Job response includes GPS fields in sync endpoint (FIELD-02)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_sync_jobs_include_gps_fields(seed_two_tenants: dict) -> None:
    """Jobs in the sync response include gps_latitude, gps_longitude, gps_address keys.

    Covers: FIELD-02 — GPS field mapping from backend to mobile.
    GPS values may be null if not set, but the keys must be present in the response.
    """
    token = seed_two_tenants["tenant_a_token"]
    async with AsyncClient(
        transport=TRANSPORT,
        base_url="http://test",
        headers={"Authorization": f"Bearer {token}"},
    ) as ac:
        # Create a job (GPS will be null — key presence is what matters)
        job = await _create_job(ac)
        job_id = job["id"]

        resp = await ac.get("/api/v1/sync")

    assert resp.status_code == 200, f"Sync failed: {resp.text}"
    data = resp.json()

    # Find our test job in the response
    test_jobs = [j for j in data["jobs"] if j.get("id") == job_id]
    assert len(test_jobs) == 1, f"Expected job {job_id} in sync response"
    job_data = test_jobs[0]

    # GPS fields must be present as keys (values may be null)
    assert "gps_latitude" in job_data, (
        f"'gps_latitude' missing from job response. Keys: {list(job_data.keys())}"
    )
    assert "gps_longitude" in job_data, (
        f"'gps_longitude' missing from job response. Keys: {list(job_data.keys())}"
    )
    assert "gps_address" in job_data, (
        f"'gps_address' missing from job response. Keys: {list(job_data.keys())}"
    )
