"""A quote cannot be sent without a client.

Before this gate, `send` checked only that the quote was a draft with no
unreviewed AI lines. Nothing asked who it was going to, so a quote moved to
`sent` addressed to nobody: the status flipped, an expiry was stamped, no client
was notified, and it read as sent.

No quote path guaranteed a recipient. A job-level quote could only reach one
through job.client_id, which is itself nullable, and a project-level quote —
including every quote the AI interview creates — has no job at all.
"""

import uuid

import pytest
from httpx import AsyncClient


async def _create_job(client: AsyncClient, *, client_id: str | None = None) -> str:
    payload: dict = {
        "description": "Client gate test job",
        "trade_type": "electrical",
        "priority": "medium",
    }
    if client_id is not None:
        payload["client_id"] = client_id
    resp = await client.post("/api/v1/jobs/", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_quote(client: AsyncClient, **fields) -> dict:
    payload: dict = {
        "line_items": [
            {
                "item_type": "labor",
                "description": "Work",
                "quantity": "1.000",
                "unit": "hour",
                "unit_price": "100.00",
                "sort_order": 0,
            }
        ]
    }
    payload.update(fields)
    resp = await client.post("/api/v1/quotes/", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


def _send_url(quote_id: str) -> str:
    return f"/api/v1/quotes/{quote_id}/send"


@pytest.mark.asyncio
async def test_project_level_quote_without_a_client_cannot_be_sent(
    tenant_a_client: AsyncClient,
):
    """The shape the AI quote interview produces: no job, no client."""
    quote = await _create_quote(tenant_a_client, title="No client here")
    assert quote["client_id"] is None

    resp = await tenant_a_client.post(_send_url(quote["id"]))

    assert resp.status_code == 400, resp.text
    assert "client" in resp.json()["detail"].lower()

    after = (await tenant_a_client.get(f"/api/v1/quotes/{quote['id']}")).json()
    assert after["status"] == "draft", "a refused send must not change status"
    assert after["sent_at"] is None


@pytest.mark.asyncio
async def test_job_quote_whose_job_has_no_client_cannot_be_sent(
    tenant_a_client: AsyncClient,
):
    """job.client_id is nullable, so a job quote was never a guarantee either."""
    job_id = await _create_job(tenant_a_client)
    quote = await _create_quote(tenant_a_client, job_id=job_id)

    resp = await tenant_a_client.post(_send_url(quote["id"]))

    assert resp.status_code == 400, resp.text


@pytest.mark.asyncio
async def test_quote_with_a_client_sends(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """The gate must not block the legitimate path."""
    me = (await tenant_a_client.get("/api/v1/auth/me")).json()
    quote = await _create_quote(tenant_a_client, title="Addressed", client_id=me["user_id"])
    assert quote["client_id"] == me["user_id"]

    resp = await tenant_a_client.post(_send_url(quote["id"]))

    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "sent"


@pytest.mark.asyncio
async def test_a_client_can_be_attached_to_an_existing_draft(tenant_a_client: AsyncClient):
    """A draft legitimately starts before the client is known, so the column is
    nullable and settable afterwards rather than required at creation."""
    me = (await tenant_a_client.get("/api/v1/auth/me")).json()
    quote = await _create_quote(tenant_a_client, title="Client added later")

    patched = await tenant_a_client.patch(
        f"/api/v1/quotes/{quote['id']}", json={"client_id": me["user_id"]}
    )
    assert patched.status_code == 200, patched.text
    assert patched.json()["client_id"] == me["user_id"]

    resp = await tenant_a_client.post(_send_url(quote["id"]))
    assert resp.status_code == 200, resp.text


@pytest.mark.asyncio
async def test_unknown_client_is_rejected(tenant_a_client: AsyncClient):
    """A foreign key means a made-up client cannot be stored."""
    resp = await tenant_a_client.post(
        "/api/v1/quotes/",
        json={"client_id": str(uuid.uuid4()), "line_items": []},
    )
    assert resp.status_code >= 400, resp.text


# ---------------------------------------------------------------------------
# Creating a client — until now there was no way to make one from the app, so
# the send gate would have been unsatisfiable for a new company.
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_client_then_address_a_quote_to_them(tenant_a_client: AsyncClient):
    created = await tenant_a_client.post(
        "/api/v1/crm/clients",
        json={
            "email": "new-client@example.com",
            "first_name": "Nora",
            "last_name": "Client",
            "phone": "555-0100",
        },
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["email"] == "new-client@example.com"
    assert body["first_name"] == "Nora"

    listed = (await tenant_a_client.get("/api/v1/crm/clients")).json()
    assert any(c["user_id"] == body["user_id"] for c in listed)

    quote = await _create_quote(tenant_a_client, title="For Nora", client_id=body["user_id"])
    resp = await tenant_a_client.post(_send_url(quote["id"]))
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "sent"


@pytest.mark.asyncio
async def test_creating_the_same_client_twice_is_idempotent(tenant_a_client: AsyncClient):
    """users.email is globally unique, so a repeat add must return the existing
    client rather than surfacing an integrity error."""
    payload = {"email": "repeat-client@example.com", "first_name": "Repeat"}
    first = await tenant_a_client.post("/api/v1/crm/clients", json=payload)
    assert first.status_code == 201, first.text
    second = await tenant_a_client.post("/api/v1/crm/clients", json=payload)
    assert second.status_code == 201, second.text
    assert second.json()["user_id"] == first.json()["user_id"]


@pytest.mark.asyncio
async def test_a_created_client_cannot_sign_in(tenant_a_client: AsyncClient):
    """Adding a client to quote them is not inviting them to log in. No password
    is set, and login rejects a null hash."""
    email = "no-login-client@example.com"
    created = await tenant_a_client.post(
        "/api/v1/crm/clients", json={"email": email, "first_name": "Silent"}
    )
    assert created.status_code == 201, created.text

    attempt = await tenant_a_client.post(
        "/api/v1/auth/login", json={"email": email, "password": "anything-at-all"}
    )
    assert attempt.status_code == 401, attempt.text


@pytest.mark.asyncio
async def test_email_owned_by_another_company_is_refused_cleanly(
    tenant_a_client: AsyncClient, tenant_b_client: AsyncClient, seed_two_tenants: dict
):
    """A 409, not a 500.

    users.email is unique globally, but the existence check runs under row level
    security and cannot see a user owned by another company. The address is
    therefore takeable by someone invisible to the query, and only the constraint
    knows — so the integrity error has to be translated rather than escaping.
    """
    shared = "contested-address@example.com"
    first = await tenant_a_client.post(
        "/api/v1/crm/clients", json={"email": shared, "first_name": "First"}
    )
    assert first.status_code == 201, first.text

    second = await tenant_b_client.post(
        "/api/v1/crm/clients", json={"email": shared, "first_name": "Second"}
    )
    assert second.status_code == 409, second.text
    assert "another account" in second.json()["detail"]
