"""Phase 32 — Labor Rates and Cost Rollup.

Covers COST-04 (append-only effective-dated rates + history + gating), COST-05
(labor derivation, added in 32-02), COST-06 (itemized category breakdown, added
in 32-02).

Rate endpoints are gated finance.rates.manage on BOTH read and write
(zero-exception posture: workers and admin get 403 on their own rate too).
Helpers mirror test_phase_31_e2e.py so 32-02 can extend this file.
"""

from datetime import date, timedelta
from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import select, text

from app.core.database import async_session_factory
from app.core.security import create_access_token
from app.features.finance.models import CostCategory

_COST_CATEGORY_SEED_SQL = (
    "INSERT INTO cost_categories (company_id, name, is_system) "
    "SELECT CAST(:company_id AS uuid), v.name, true "
    "FROM (VALUES ('labor'),('materials'),('subcontractor'),('other')) AS v(name) "
    "ON CONFLICT (company_id, name) DO NOTHING"
)

_MISSING_RATES_PERMISSION = "Missing permission: finance.rates.manage"


def _token(company_id: str, roles: list[str]) -> str:
    """Mint an access token for a synthetic user with the given roles."""
    return create_access_token(uuid4(), UUID(company_id), roles)


def _pm_headers(company_id: str) -> dict:
    """Authorization header for a project_manager token (finance.view + finance.manage)."""
    return {"Authorization": f"Bearer {_token(company_id, ['project_manager'])}"}


def _admin_headers(company_id: str) -> dict:
    """Authorization header for an admin token (excluded from finance.* by default)."""
    return {"Authorization": f"Bearer {_token(company_id, ['admin'])}"}


async def _seed_cost_categories(company_id: str) -> None:
    """Seed the 4 protected system cost categories for a company (mirrors migration 0032)."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(_COST_CATEGORY_SEED_SQL), {"company_id": company_id})
        await session.commit()


async def _category_id(company_id: str, name: str) -> str:
    """Look up a seeded cost category's id by name."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(
            select(CostCategory).where(
                CostCategory.company_id == company_id, CostCategory.name == name
            )
        )
        return str(result.scalar_one().id)


async def _create_project(client: AsyncClient, name: str = "Test Project 32") -> str:
    resp = await client.post("/api/v1/projects/", json={"name": name, "status": "active"})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_trade_scope(
    client: AsyncClient, project_id: str, trade_name: str = "Plumbing"
) -> str:
    resp = await client.post(
        "/api/v1/trade-scopes/",
        json={"project_id": project_id, "trade_name": trade_name, "trade_color": "#2196F3"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_job(client: AsyncClient, project_id: str | None = None) -> str:
    payload: dict = {"description": "Test job", "trade_type": "general"}
    if project_id is not None:
        payload["project_id"] = project_id
    resp = await client.post("/api/v1/jobs/", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_user(client: AsyncClient, email: str) -> str:
    """Create a company user via the users API and return its id."""
    resp = await client.post("/api/v1/users/", json={"email": email})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


def _rate_payload(user_id: str, hourly_cost: str, effective_from: date) -> dict:
    return {
        "user_id": user_id,
        "hourly_cost": hourly_cost,
        "effective_from": effective_from.isoformat(),
    }


async def _post_rate(
    client: AsyncClient, headers: dict, user_id: str, hourly_cost: str, effective_from: date
) -> dict:
    resp = await client.post(
        "/api/v1/labor-rates/",
        headers=headers,
        json=_rate_payload(user_id, hourly_cost, effective_from),
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


# ---------------------------------------------------------------------------
# COST-04: append-only rate creation, history preservation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_rate_create_and_history_preserved(async_client, tenant_a_client, seed_two_tenants):
    """COST-04: two rates for one worker are both kept; history is effective_from DESC."""
    company_id = seed_two_tenants["tenant_a_id"]
    user_id = await _create_user(tenant_a_client, "worker-history@tenant-a.com")
    headers = _pm_headers(company_id)

    await _post_rate(async_client, headers, user_id, "30.00", date(2026, 5, 1))
    await _post_rate(async_client, headers, user_id, "40.00", date(2026, 6, 1))

    history = await async_client.get(
        "/api/v1/labor-rates/", headers=headers, params={"user_id": user_id}
    )
    assert history.status_code == 200, history.text
    rows = history.json()
    assert [row["effective_from"] for row in rows] == ["2026-06-01", "2026-05-01"]
    assert [row["hourly_cost"] for row in rows] == ["40.00", "30.00"]


@pytest.mark.asyncio
async def test_rate_backdated_is_accepted(async_client, tenant_a_client, seed_two_tenants):
    """COST-04: a rate effective well in the past is accepted and appears in history."""
    company_id = seed_two_tenants["tenant_a_id"]
    user_id = await _create_user(tenant_a_client, "worker-backdated@tenant-a.com")
    headers = _pm_headers(company_id)

    created = await _post_rate(async_client, headers, user_id, "25.00", date(2026, 1, 1))
    assert created["effective_from"] == "2026-01-01"

    history = await async_client.get(
        "/api/v1/labor-rates/", headers=headers, params={"user_id": user_id}
    )
    assert history.status_code == 200, history.text
    assert [row["id"] for row in history.json()] == [created["id"]]


@pytest.mark.asyncio
async def test_rate_future_dated_excluded_from_current_but_kept_in_history(
    async_client, tenant_a_client, seed_two_tenants
):
    """A scheduled raise stays out of the current listing but shows in history."""
    company_id = seed_two_tenants["tenant_a_id"]
    user_id = await _create_user(tenant_a_client, "worker-future@tenant-a.com")
    headers = _pm_headers(company_id)

    await _post_rate(async_client, headers, user_id, "30.00", date(2026, 1, 1))
    await _post_rate(async_client, headers, user_id, "50.00", date.today() + timedelta(days=30))

    current = await async_client.get("/api/v1/labor-rates/", headers=headers)
    assert current.status_code == 200, current.text
    current_rows = [row for row in current.json() if row["user_id"] == user_id]
    assert [row["hourly_cost"] for row in current_rows] == ["30.00"]

    history = await async_client.get(
        "/api/v1/labor-rates/", headers=headers, params={"user_id": user_id}
    )
    assert history.status_code == 200, history.text
    assert len(history.json()) == 2


@pytest.mark.asyncio
async def test_rate_duplicate_effective_from_tie_break_uses_latest_created(
    async_client, tenant_a_client, seed_two_tenants
):
    """Same-day correction: the row entered last (latest created_at) wins as current."""
    company_id = seed_two_tenants["tenant_a_id"]
    user_id = await _create_user(tenant_a_client, "worker-tiebreak@tenant-a.com")
    headers = _pm_headers(company_id)

    await _post_rate(async_client, headers, user_id, "30.00", date(2026, 5, 1))
    await _post_rate(async_client, headers, user_id, "35.00", date(2026, 5, 1))

    current = await async_client.get("/api/v1/labor-rates/", headers=headers)
    assert current.status_code == 200, current.text
    current_rows = [row for row in current.json() if row["user_id"] == user_id]
    assert [row["hourly_cost"] for row in current_rows] == ["35.00"]

    history = await async_client.get(
        "/api/v1/labor-rates/", headers=headers, params={"user_id": user_id}
    )
    assert history.status_code == 200, history.text
    assert len(history.json()) == 2


@pytest.mark.asyncio
async def test_rate_current_list_returns_one_row_per_user(
    async_client, tenant_a_client, seed_two_tenants
):
    """The no-user_id GET resolves exactly one current row per rated worker."""
    company_id = seed_two_tenants["tenant_a_id"]
    first_user = await _create_user(tenant_a_client, "worker-one@tenant-a.com")
    second_user = await _create_user(tenant_a_client, "worker-two@tenant-a.com")
    headers = _pm_headers(company_id)

    for user_id in (first_user, second_user):
        await _post_rate(async_client, headers, user_id, "30.00", date(2026, 1, 1))
        await _post_rate(async_client, headers, user_id, "40.00", date(2026, 6, 1))

    current = await async_client.get("/api/v1/labor-rates/", headers=headers)
    assert current.status_code == 200, current.text
    rows = current.json()
    assert len(rows) == 2
    assert {row["user_id"] for row in rows} == {first_user, second_user}
    assert all(row["hourly_cost"] == "40.00" for row in rows)


# ---------------------------------------------------------------------------
# 403 matrix: admin and worker are both denied on read AND write
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_rate_endpoints_403_for_admin(async_client, tenant_a_client, seed_two_tenants):
    """Admin is excluded from finance.* — 403 on both the rate POST and GET."""
    company_id = seed_two_tenants["tenant_a_id"]
    user_id = await _create_user(tenant_a_client, "worker-admin403@tenant-a.com")
    admin_headers = _admin_headers(company_id)

    post_resp = await async_client.post(
        "/api/v1/labor-rates/",
        headers=admin_headers,
        json=_rate_payload(user_id, "30.00", date(2026, 5, 1)),
    )
    assert post_resp.status_code == 403, post_resp.text
    assert post_resp.json()["detail"] == _MISSING_RATES_PERMISSION

    get_resp = await async_client.get("/api/v1/labor-rates/", headers=admin_headers)
    assert get_resp.status_code == 403, get_resp.text
    assert get_resp.json()["detail"] == _MISSING_RATES_PERMISSION


@pytest.mark.asyncio
async def test_rate_endpoints_403_for_worker(async_client, tenant_a_client, seed_two_tenants):
    """A worker cannot read or write rates — not even their own (zero-exception posture)."""
    company_id = seed_two_tenants["tenant_a_id"]
    user_id = await _create_user(tenant_a_client, "worker-worker403@tenant-a.com")
    worker_headers = {"Authorization": f"Bearer {_token(company_id, ['worker'])}"}

    post_resp = await async_client.post(
        "/api/v1/labor-rates/",
        headers=worker_headers,
        json=_rate_payload(user_id, "30.00", date(2026, 5, 1)),
    )
    assert post_resp.status_code == 403, post_resp.text
    assert post_resp.json()["detail"] == _MISSING_RATES_PERMISSION

    get_resp = await async_client.get(
        "/api/v1/labor-rates/", headers=worker_headers, params={"user_id": user_id}
    )
    assert get_resp.status_code == 403, get_resp.text
    assert get_resp.json()["detail"] == _MISSING_RATES_PERMISSION


# ---------------------------------------------------------------------------
# Validation and soft-FK integrity
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_rate_create_404_for_unknown_user(async_client, seed_two_tenants):
    """A rate for a user id that does not exist in the tenant is rejected with 404."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)

    resp = await async_client.post(
        "/api/v1/labor-rates/",
        headers=headers,
        json=_rate_payload(str(uuid4()), "30.00", date(2026, 5, 1)),
    )
    assert resp.status_code == 404, resp.text
    assert resp.json()["detail"] == "User not found"


@pytest.mark.asyncio
async def test_rate_validation_rejects_non_positive_amount(
    async_client, tenant_a_client, seed_two_tenants
):
    """hourly_cost must be > 0 — zero and negative amounts are 422."""
    company_id = seed_two_tenants["tenant_a_id"]
    user_id = await _create_user(tenant_a_client, "worker-validation@tenant-a.com")
    headers = _pm_headers(company_id)

    for bad_amount in ("0", "-5"):
        resp = await async_client.post(
            "/api/v1/labor-rates/",
            headers=headers,
            json=_rate_payload(user_id, bad_amount, date(2026, 5, 1)),
        )
        assert resp.status_code == 422, resp.text


# ---------------------------------------------------------------------------
# RLS isolation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_rate_rls_isolation_between_tenants(
    async_client, tenant_a_client, tenant_b_client, seed_two_tenants
):
    """A rate created in tenant A is invisible to tenant B's history and current listings."""
    tenant_a_id = seed_two_tenants["tenant_a_id"]
    tenant_b_id = seed_two_tenants["tenant_b_id"]
    user_id = await _create_user(tenant_a_client, "worker-rls@tenant-a.com")
    a_headers = _pm_headers(tenant_a_id)

    await _post_rate(async_client, a_headers, user_id, "30.00", date(2026, 5, 1))

    b_headers = _pm_headers(tenant_b_id)
    b_history = await async_client.get(
        "/api/v1/labor-rates/", headers=b_headers, params={"user_id": user_id}
    )
    assert b_history.status_code == 200, b_history.text
    assert b_history.json() == []

    b_current = await async_client.get("/api/v1/labor-rates/", headers=b_headers)
    assert b_current.status_code == 200, b_current.text
    assert b_current.json() == []
