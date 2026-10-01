"""Rate limits must count one person at a time.

Every browser request reaches this API through the web app, so keying the limit
on the connecting socket made a single bucket for the whole world: `5/minute` on
login was five logins a minute across all users combined, and a person testing
collected 429s earned by somebody else. The web app forwards the browser's
address and the limiter counts against that.

The fix must not be "stop limiting": a burst from one client still has to be
refused, which is the second half of every test here.
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient

_LOGIN = "/api/v1/auth/login"
_LOGIN_LIMIT_PER_MINUTE = 5


async def _register(client: AsyncClient, email: str, company: str) -> dict:
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": "TestPass123!", "company_name": company},
    )
    assert resp.status_code == 201, resp.text
    return {"email": email, "password": "TestPass123!"}


@pytest.mark.asyncio
async def test_one_client_burning_the_limit_does_not_lock_out_everyone_else(
    async_client: AsyncClient,
):
    creds = await _register(async_client, "burst@example.com", "Burst Co")

    for attempt in range(_LOGIN_LIMIT_PER_MINUTE + 1):
        resp = await async_client.post(_LOGIN, json=creds, headers={"X-Client-IP": "198.51.100.7"})
        expected = 200 if attempt < _LOGIN_LIMIT_PER_MINUTE else 429
        assert resp.status_code == expected, f"attempt {attempt + 1}: {resp.text}"

    # The whole point: somebody else is unaffected.
    other = await async_client.post(_LOGIN, json=creds, headers={"X-Client-IP": "198.51.100.8"})
    assert other.status_code == 200, other.text


@pytest.mark.asyncio
async def test_the_limit_still_bites_the_client_that_earned_it(
    async_client: AsyncClient,
):
    """A fix that stopped limiting would be worse than the bug."""
    creds = await _register(async_client, "repeat@example.com", "Repeat Co")
    headers = {"X-Client-IP": "203.0.113.42"}

    for _ in range(_LOGIN_LIMIT_PER_MINUTE):
        assert (await async_client.post(_LOGIN, json=creds, headers=headers)).status_code == 200

    refused = await async_client.post(_LOGIN, json=creds, headers=headers)
    assert refused.status_code == 429, refused.text


@pytest.mark.asyncio
async def test_many_separate_clients_are_each_counted_on_their_own(
    async_client: AsyncClient,
):
    """More callers than the limit, none of them over it."""
    creds = await _register(async_client, "many@example.com", "Many Co")

    for index in range(_LOGIN_LIMIT_PER_MINUTE * 3):
        resp = await async_client.post(
            _LOGIN, json=creds, headers={"X-Client-IP": f"192.0.2.{index + 1}"}
        )
        assert resp.status_code == 200, f"client {index + 1}: {resp.text}"


@pytest.mark.asyncio
async def test_a_caller_that_sends_no_address_is_still_limited(
    async_client: AsyncClient,
):
    """The mobile app reaches this API directly, so the fallback has to work."""
    creds = await _register(async_client, "direct@example.com", "Direct Co")

    for _ in range(_LOGIN_LIMIT_PER_MINUTE):
        assert (await async_client.post(_LOGIN, json=creds)).status_code == 200

    refused = await async_client.post(_LOGIN, json=creds)
    assert refused.status_code == 429, refused.text
