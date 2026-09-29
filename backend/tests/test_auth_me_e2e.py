"""GET /auth/me — recovering identity after a page reload.

The browser holds the session in httpOnly cookies it can send but not read, so
a reloaded page knew it was authenticated and nothing else: the UI fell back to
a generic label, and because its permission gate keyed off that same state,
every permission-gated control silently vanished.

Roles here come from the database rather than the access token, so a role change
takes effect on the next load instead of waiting for the token to rotate.
"""

import pytest
from httpx import AsyncClient

ME_URL = "/api/v1/auth/me"


@pytest.mark.asyncio
async def test_me_returns_the_signed_in_identity(async_client: AsyncClient):
    email = "me-identity@example.com"
    register = await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "MePassw0rd!",
            "company_name": "Identity Co",
            "first_name": "Ada",
            "last_name": "Lovelace",
        },
    )
    assert register.status_code == 201, register.text
    token = register.json()["access_token"]

    resp = await async_client.get(ME_URL, headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["email"] == email
    assert body["display_name"] == "Ada Lovelace"
    assert body["company_name"] == "Identity Co"
    assert body["roles"] == ["admin"]
    assert body["user_id"]
    assert body["company_id"]


@pytest.mark.asyncio
async def test_display_name_falls_back_to_email_when_unnamed(async_client: AsyncClient):
    """A user who registered without a name must still get a usable label —
    the generic placeholder is what this endpoint exists to remove."""
    email = "me-nameless@example.com"
    register = await async_client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": "MePassw0rd!", "company_name": "Nameless Co"},
    )
    assert register.status_code == 201, register.text
    token = register.json()["access_token"]

    body = (await async_client.get(ME_URL, headers={"Authorization": f"Bearer {token}"})).json()
    assert body["display_name"] == email


@pytest.mark.asyncio
async def test_me_matches_what_login_reported(async_client: AsyncClient):
    """Login and /me must agree. They shared no code before this endpoint
    existed, and a refreshed page rendering a different name than the one login
    set would be the failure nobody notices until a user mentions it."""
    email = "me-agrees@example.com"
    await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "MePassw0rd!",
            "company_name": "Agreement Co",
            "first_name": "Grace",
            "last_name": "Hopper",
        },
    )
    login = await async_client.post(
        "/api/v1/auth/login", json={"email": email, "password": "MePassw0rd!"}
    )
    assert login.status_code == 200, login.text
    login_body = login.json()

    me = (
        await async_client.get(
            ME_URL, headers={"Authorization": f"Bearer {login_body['access_token']}"}
        )
    ).json()

    assert me["display_name"] == login_body["display_name"]
    assert me["company_name"] == login_body["company_name"]
    assert me["roles"] == login_body["roles"]


@pytest.mark.asyncio
async def test_me_requires_authentication(async_client: AsyncClient):
    resp = await async_client.get(ME_URL)
    assert resp.status_code in (401, 403), resp.text
