"""Caller-keyed limits must count one caller at a time.

Every browser request reaches this API through the web app, so keying on the
connecting socket made a single bucket for the whole world: one person's burst
refused everybody. The web app forwards the browser's address and the limiter
counts against that.

Exercised on forgot-password rather than login: it has a small caller-keyed
limit and costs no password hashing, and login's own protection is per-account
rather than per-caller (see test_login_throttle_e2e.py).

The fix must not be "stop limiting", so every test here also shows the limit
still biting the caller that earned it.
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient

_ENDPOINT = "/api/v1/auth/forgot-password"
_LIMIT_PER_MINUTE = 3  # matches @limiter.limit on the endpoint
_BODY = {"email": "someone@example.com"}


@pytest.mark.asyncio
async def test_one_caller_burning_the_limit_does_not_refuse_everyone_else(
    async_client: AsyncClient,
):
    for attempt in range(_LIMIT_PER_MINUTE + 1):
        resp = await async_client.post(
            _ENDPOINT, json=_BODY, headers={"X-Client-IP": "198.51.100.7"}
        )
        expected = 202 if attempt < _LIMIT_PER_MINUTE else 429
        assert resp.status_code == expected, f"attempt {attempt + 1}: {resp.text}"

    other = await async_client.post(_ENDPOINT, json=_BODY, headers={"X-Client-IP": "198.51.100.8"})
    assert other.status_code == 202, other.text


@pytest.mark.asyncio
async def test_many_separate_callers_are_each_counted_on_their_own(
    async_client: AsyncClient,
):
    """More callers than the limit, none of them over it."""
    for index in range(_LIMIT_PER_MINUTE * 4):
        resp = await async_client.post(
            _ENDPOINT, json=_BODY, headers={"X-Client-IP": f"192.0.2.{index + 1}"}
        )
        assert resp.status_code == 202, f"caller {index + 1}: {resp.text}"


@pytest.mark.asyncio
async def test_a_caller_that_sends_no_address_is_still_limited(
    async_client: AsyncClient,
):
    """The mobile app reaches this API directly, so the fallback has to work."""
    for _ in range(_LIMIT_PER_MINUTE):
        assert (await async_client.post(_ENDPOINT, json=_BODY)).status_code == 202

    refused = await async_client.post(_ENDPOINT, json=_BODY)
    assert refused.status_code == 429, refused.text


@pytest.mark.asyncio
async def test_a_refusal_says_how_long_to_wait(async_client: AsyncClient):
    """ "Try again later" is not actionable: a minute and an hour look the same."""
    headers = {"X-Client-IP": "203.0.113.99"}

    refused = None
    for _ in range(_LIMIT_PER_MINUTE + 2):
        resp = await async_client.post(_ENDPOINT, json=_BODY, headers=headers)
        if resp.status_code == 429:
            refused = resp
            break

    assert refused is not None, "the limit should still bite"
    assert refused.headers.get("Retry-After") == "60", refused.headers
    assert "Try again in 60 seconds" in refused.json()["detail"]
