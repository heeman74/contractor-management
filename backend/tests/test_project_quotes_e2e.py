"""E2E: project-level quotes.

A quote with neither job_id nor trade_scope_id is a project-level quote. On client
approval it creates a Project (named by the quote title) plus one Job per line-item
`field`, then links the quote to that project.
"""

from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app as fastapi_app

_ADMIN_EMAIL = "admin@tenant-a.com"
_ADMIN_PASSWORD = "TestPass123!"

_PROJECT_QUOTE_BODY = {
    "title": "Kitchen Remodel",
    "tax_rate": "0.00",
    "line_items": [
        {
            "item_type": "labor",
            "description": "Install sub-panel",
            "quantity": "8.000",
            "unit": "hr",
            "unit_price": "75.00",
            "sort_order": 0,
            "field": "Electrical",
        },
        {
            "item_type": "material",
            "description": "100A sub-panel",
            "quantity": "1.000",
            "unit": "ea",
            "unit_price": "400.00",
            "sort_order": 1,
            "field": "Electrical",
        },
        {
            "item_type": "labor",
            "description": "Run supply lines",
            "quantity": "6.000",
            "unit": "hr",
            "unit_price": "70.00",
            "sort_order": 2,
            "field": "Plumbing",
        },
    ],
}


async def _client_role_token(admin_client: AsyncClient, user_id: str) -> str:
    """Grant the admin user the 'client' role and re-login so it can approve quotes."""
    await admin_client.post(
        f"/api/v1/users/{user_id}/roles",
        json={"user_id": user_id, "role": "client"},
    )
    resp = await admin_client.post(
        "/api/v1/auth/login",
        json={"email": _ADMIN_EMAIL, "password": _ADMIN_PASSWORD},
    )
    assert resp.status_code == 200, resp.text
    return resp.json()["access_token"]


@pytest.mark.asyncio
async def test_project_quote_converts_to_project_with_per_field_jobs(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    user_id = seed_two_tenants["tenant_a_user_id"]

    # Draft a project-level quote (no job_id, no trade_scope_id).
    create = await tenant_a_client.post("/api/v1/quotes/", json=_PROJECT_QUOTE_BODY)
    assert create.status_code == 201, create.text
    quote_id = create.json()["id"]

    # Send, then approve as the client.
    send = await tenant_a_client.post(f"/api/v1/quotes/{quote_id}/send")
    assert send.status_code == 200, send.text

    token = await _client_role_token(tenant_a_client, user_id)
    async with AsyncClient(
        transport=ASGITransport(app=fastapi_app),
        base_url="http://test",
        headers={"Authorization": f"Bearer {token}"},
    ) as client:
        approve = await client.post(f"/api/v1/quotes/{quote_id}/approve")
    assert approve.status_code == 200, approve.text

    approved = approve.json()
    assert approved["status"] == "approved"
    project_id = approved["project_id"]
    assert project_id, "approval should have created and linked a project"

    # The project is named from the quote title.
    project = await tenant_a_client.get(f"/api/v1/projects/{project_id}")
    assert project.status_code == 200, project.text
    assert project.json()["name"] == "Kitchen Remodel"

    # One job per field, with the field as trade_type.
    jobs_resp = await tenant_a_client.get(f"/api/v1/jobs/?project_id={project_id}")
    assert jobs_resp.status_code == 200, jobs_resp.text
    jobs = jobs_resp.json()
    by_trade = {j["trade_type"]: j for j in jobs}
    assert set(by_trade) == {"Electrical", "Plumbing"}

    electrical = by_trade["Electrical"]
    assert electrical["description"] == "Install sub-panel"
    assert electrical["project_id"] == project_id
    # Material items land in the job notes, along with the quoted total.
    assert "100A sub-panel" in (electrical["notes"] or "")
    assert "Quoted total" in (electrical["notes"] or "")

    plumbing = by_trade["Plumbing"]
    assert plumbing["description"] == "Run supply lines"


@pytest.mark.asyncio
async def test_project_quote_can_be_created_without_job_or_scope(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    resp = await tenant_a_client.post(
        "/api/v1/quotes/",
        json={"title": "Standalone", "line_items": []},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["job_id"] is None
    assert body["trade_scope_id"] is None
    assert body["project_id"] is None  # not converted until approved


@pytest.mark.asyncio
async def test_quote_cannot_attach_to_both_job_and_scope(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    import uuid

    resp = await tenant_a_client.post(
        "/api/v1/quotes/",
        json={
            "job_id": str(uuid.uuid4()),
            "trade_scope_id": str(uuid.uuid4()),
            "line_items": [],
        },
    )
    assert resp.status_code == 422, resp.text
