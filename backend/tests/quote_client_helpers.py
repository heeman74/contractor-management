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


async def client_headers_for_quote(_client: AsyncClient, quote_id: str, company_id: str) -> dict:
    """Authorization header for the client a quote is actually addressed to.

    Approving, declining and viewing are restricted to that client — before, any
    client of the company could approve a quote priced for somebody else. Tests
    that minted a synthetic client token were relying on that, so they need the
    real recipient.

    Read from the database rather than over HTTP: call sites pass whichever
    client is to hand, and some of those are unauthenticated, which would make
    the lookup silently return nothing. Resolves the quote's own client first and
    falls back to the job's, matching the ladder the service uses.
    """
    from uuid import UUID

    from sqlalchemy import text

    from app.core.database import async_session_factory
    from app.core.security import create_access_token

    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        row = (
            await session.execute(
                text(
                    "SELECT COALESCE(q.client_id, j.client_id) AS client_id "
                    "FROM quotes q LEFT JOIN jobs j ON j.id = q.job_id "
                    "WHERE q.id = CAST(:qid AS uuid)"
                ),
                {"qid": quote_id},
            )
        ).first()

    client_id = row[0] if row is not None else None
    assert client_id is not None, f"quote {quote_id} names no client, so no one can approve it"
    token = create_access_token(UUID(str(client_id)), UUID(company_id), ["client"])
    return {"Authorization": f"Bearer {token}"}
