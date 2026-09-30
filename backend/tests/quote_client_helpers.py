"""Shared helper for tests that send a quote.

A quote cannot be sent without a client. Tests written before that gate existed
create a job and a quote with no client at all, which is precisely the defect the
gate closes — so their setup, not the gate, is what needed correcting.

`ensure_client` is idempotent: POST /crm/clients returns the existing client for
an address already on the roster, so a helper may call it freely without tracking
whether this test has one yet.
"""

from httpx import AsyncClient


async def ensure_client(client: AsyncClient, email: str | None = None) -> str:
    """The user_id of a client on this company's roster, creating it if needed.

    The address is derived from the caller's company when not given, because
    users.email is unique globally: a fixed address would be claimed by whichever
    tenant ran first, and every other tenant would collide with a user that row
    level security hides from them.
    """
    if email is None:
        me = await client.get("/api/v1/auth/me")
        assert me.status_code == 200, f"identity lookup failed: {me.text}"
        email = f"test-recipient-{me.json()['company_id']}@example.com"

    resp = await client.post(
        "/api/v1/crm/clients",
        json={"email": email, "first_name": "Test", "last_name": "Recipient"},
    )
    assert resp.status_code == 201, f"client setup failed: {resp.text}"
    return resp.json()["user_id"]
