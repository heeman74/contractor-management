"""Rate limiting tests — verify slowapi limits on auth endpoints.

These tests send rapid requests to trigger the rate limiter.
Note: slowapi uses the client IP as the key. In ASGI test transport,
all requests come from the same "client", so the limiter applies.
"""

import pytest
from httpx import AsyncClient

# Matches @limiter.limit on /auth/login. Raised from five, which refused a person
# who mistyped a password twice and reloaded the page — the limit is there to slow
# credential stuffing, which needs orders of magnitude more than that.
_LOGIN_ATTEMPTS_PER_MINUTE = 10


@pytest.mark.asyncio
async def test_login_rate_limit_429(async_client: AsyncClient):
    """One attempt past the limit, within a minute, is refused."""
    for i in range(_LOGIN_ATTEMPTS_PER_MINUTE):
        resp = await async_client.post(
            "/api/v1/auth/login",
            json={"email": f"user{i}@test.com", "password": "WrongPass1!"},
        )
        assert resp.status_code != 429, f"refused early, on attempt {i + 1}"

    resp = await async_client.post(
        "/api/v1/auth/login",
        json={"email": "over@test.com", "password": "WrongPass1!"},
    )
    assert resp.status_code == 429
    assert resp.headers.get("Retry-After") == "60", resp.headers


@pytest.mark.asyncio
async def test_register_rate_limit_429(async_client: AsyncClient):
    """The 4th rapid register attempt within a minute returns 429.

    Rate limit: 3/minute on /auth/register.
    """
    for i in range(3):
        await async_client.post(
            "/api/v1/auth/register",
            json={
                "email": f"ratelimit{i}@test.com",
                "password": "TestPass123!",
                "company_name": f"RateLimit Co {i}",
            },
        )

    # 4th attempt should be rate-limited
    resp = await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "ratelimit3@test.com",
            "password": "TestPass123!",
            "company_name": "RateLimit Co 3",
        },
    )
    assert resp.status_code == 429
