"""Logging in correctly must never lock you out.

The limit used to count every login request, successful ones included, keyed on
the caller. Someone who logged in once, stepped away for an hour and came back
was refused — by their own successful logins, on a key shared with every other
user because every browser reaches this API through the web app.

What brute force actually targets is an account, and that is knowable from the
request. So failures against an account are counted, successes are not, and a
correct password clears the record.
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.core.login_throttle import MAX_FAILURES

_LOGIN = "/api/v1/auth/login"
_PASSWORD = "TestPass123!"


async def _register(client: AsyncClient, email: str) -> None:
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": _PASSWORD, "company_name": f"Co {email}"},
    )
    assert resp.status_code == 201, resp.text


@pytest.mark.asyncio
async def test_logging_in_correctly_many_times_is_never_refused(
    async_client: AsyncClient,
):
    """The reported bug, as a test: nothing about succeeding should cost you."""
    await _register(async_client, "repeat-success@example.com")
    creds = {"email": "repeat-success@example.com", "password": _PASSWORD}

    for attempt in range(MAX_FAILURES * 3):
        resp = await async_client.post(_LOGIN, json=creds)
        assert resp.status_code == 200, f"attempt {attempt + 1}: {resp.text}"


@pytest.mark.asyncio
async def test_repeated_wrong_passwords_are_refused(async_client: AsyncClient):
    """The protection that is actually wanted."""
    await _register(async_client, "guessed@example.com")
    wrong = {"email": "guessed@example.com", "password": "WrongPass123!"}

    for _ in range(MAX_FAILURES):
        assert (await async_client.post(_LOGIN, json=wrong)).status_code == 401

    refused = await async_client.post(_LOGIN, json=wrong)
    assert refused.status_code == 429, refused.text
    assert "failed attempts for this account" in refused.json()["detail"]
    assert refused.headers.get("Retry-After") is not None


@pytest.mark.asyncio
async def test_one_account_being_guessed_does_not_lock_out_another(
    async_client: AsyncClient,
):
    """A shared bucket is what made this an outage rather than an annoyance."""
    await _register(async_client, "target@example.com")
    await _register(async_client, "bystander@example.com")

    for _ in range(MAX_FAILURES + 1):
        await async_client.post(
            _LOGIN, json={"email": "target@example.com", "password": "WrongPass123!"}
        )

    bystander = await async_client.post(
        _LOGIN, json={"email": "bystander@example.com", "password": _PASSWORD}
    )
    assert bystander.status_code == 200, bystander.text


@pytest.mark.asyncio
async def test_the_right_password_clears_what_came_before(async_client: AsyncClient):
    """Failures before a success are no longer evidence of anything."""
    await _register(async_client, "recovered@example.com")

    for _ in range(MAX_FAILURES - 1):
        await async_client.post(
            _LOGIN,
            json={"email": "recovered@example.com", "password": "WrongPass123!"},
        )

    good = await async_client.post(
        _LOGIN, json={"email": "recovered@example.com", "password": _PASSWORD}
    )
    assert good.status_code == 200, good.text

    # The budget is whole again, rather than one attempt from a lockout.
    for _ in range(MAX_FAILURES - 1):
        resp = await async_client.post(
            _LOGIN,
            json={"email": "recovered@example.com", "password": "WrongPass123!"},
        )
        assert resp.status_code == 401, resp.text


@pytest.mark.asyncio
async def test_the_account_key_ignores_case_and_padding(async_client: AsyncClient):
    """Otherwise the throttle is sidestepped by typing the address differently."""
    await _register(async_client, "casing@example.com")

    for _ in range(MAX_FAILURES):
        await async_client.post(
            _LOGIN, json={"email": "casing@example.com", "password": "WrongPass123!"}
        )

    evaded = await async_client.post(
        _LOGIN, json={"email": "CASING@example.com", "password": "WrongPass123!"}
    )
    assert evaded.status_code == 429, evaded.text
