"""Integration tests for scripts/provision.py.

Exercises the real code path: the CLI handlers open their own session against the
test database and commit, then we verify the provisioned users can authenticate
through the live /api/v1/auth/login endpoint.
"""

import argparse

import pytest
from httpx import AsyncClient

from scripts.provision import add_user, create_company, set_password

pytestmark = pytest.mark.asyncio


def _ns(**kwargs) -> argparse.Namespace:
    return argparse.Namespace(**kwargs)


async def _login(client: AsyncClient, email: str, password: str):
    return await client.post("/api/v1/auth/login", json={"email": email, "password": password})


async def test_create_company_admin_can_login(async_client: AsyncClient):
    await create_company(
        _ns(
            name="Provision Co",
            admin_email="prov-admin@example.com",
            admin_first="Ada",
            admin_last="Admin",
            phone="+61 400 000 000",
            password="provpass123",
        )
    )

    resp = await _login(async_client, "prov-admin@example.com", "provpass123")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["roles"] == ["admin"]
    assert body["access_token"]


async def test_add_user_with_role_can_login(async_client: AsyncClient):
    await create_company(
        _ns(
            name="Provision Co",
            admin_email="prov-admin@example.com",
            admin_first=None,
            admin_last=None,
            phone=None,
            password="provpass123",
        )
    )
    await add_user(
        _ns(
            company="Provision Co",
            email="prov-contractor@example.com",
            role="contractor",
            first="Jo",
            last="Bloggs",
            phone=None,
            password="provpass123",
        )
    )

    resp = await _login(async_client, "prov-contractor@example.com", "provpass123")
    assert resp.status_code == 200, resp.text
    assert resp.json()["roles"] == ["contractor"]


async def test_set_password_resets_login(async_client: AsyncClient):
    await create_company(
        _ns(
            name="Provision Co",
            admin_email="prov-admin@example.com",
            admin_first=None,
            admin_last=None,
            phone=None,
            password="oldpass123",
        )
    )
    await set_password(_ns(email="prov-admin@example.com", password="newpass456"))

    old = await _login(async_client, "prov-admin@example.com", "oldpass123")
    assert old.status_code == 401
    new = await _login(async_client, "prov-admin@example.com", "newpass456")
    assert new.status_code == 200, new.text


async def test_add_user_to_missing_company_exits():
    with pytest.raises(SystemExit):
        await add_user(
            _ns(
                company="No Such Company",
                email="orphan@example.com",
                role="contractor",
                first=None,
                last=None,
                phone=None,
                password="provpass123",
            )
        )
