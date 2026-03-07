"""Rate limiting tests — verify slowapi limits on auth endpoints.

These tests send rapid requests to trigger the rate limiter.
Note: slowapi uses the client IP as the key. In ASGI test transport,
all requests come from the same "client", so the limiter applies.
"""

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_login_rate_limit_429(async_client: AsyncClient):
    """The 6th rapid login attempt within a minute returns 429.

    Rate limit: 5/minute on /auth/login.
    """
    for i in range(5):
        await async_client.post(
            "/api/v1/auth/login",
            json={"email": f"user{i}@test.com", "password": "WrongPass1!"},
        )

    # 6th attempt should be rate-limited
    resp = await async_client.post(
        "/api/v1/auth/login",
        json={"email": "user5@test.com", "password": "WrongPass1!"},
    )
    assert resp.status_code == 429


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
