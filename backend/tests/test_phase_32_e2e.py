"""Phase 32 — Labor Rates and Cost Rollup.

Covers COST-04 (append-only effective-dated rates + history + gating), COST-05
(labor derivation, added in 32-02), COST-06 (itemized category breakdown, added
in 32-02).

Rate endpoints are gated finance.rates.manage on BOTH read and write
(zero-exception posture: workers and admin get 403 on their own rate too).
Helpers mirror test_phase_31_e2e.py so 32-02 can extend this file.
"""

from datetime import UTC, date, datetime, timedelta
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
_MISSING_VIEW_PERMISSION = "Missing permission: finance.view"

_TIME_ENTRY_SEED_SQL = (
    "INSERT INTO time_entries (company_id, job_id, contractor_id, clocked_in_at, "
    "clocked_out_at, duration_seconds, session_status, deleted_at) "
    "VALUES (CAST(:company_id AS uuid), CAST(:job_id AS uuid), "
    "CAST(:contractor_id AS uuid), :clocked_in_at, :clocked_out_at, "
    ":duration_seconds, :session_status, :deleted_at)"
)

_COST_ENTRY_SEED_SQL = (
    "INSERT INTO cost_entries (company_id, job_id, category_id, amount, incurred_date) "
    "VALUES (CAST(:company_id AS uuid), CAST(:job_id AS uuid), "
    "CAST(:category_id AS uuid), :amount, :incurred_date)"
)


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


async def _seed_time_entry(
    company_id: str,
    job_id: str,
    contractor_id: str,
    clocked_in_at: datetime,
    duration_seconds: int | None,
    session_status: str = "completed",
    deleted: bool = False,
) -> None:
    """Insert a tracked-time row directly, so tests control the exact work day."""
    clocked_out_at = (
        clocked_in_at + timedelta(seconds=duration_seconds)
        if duration_seconds is not None
        else None
    )
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(
            text(_TIME_ENTRY_SEED_SQL),
            {
                "company_id": company_id,
                "job_id": job_id,
                "contractor_id": contractor_id,
                "clocked_in_at": clocked_in_at,
                "clocked_out_at": clocked_out_at,
                "duration_seconds": duration_seconds,
                "session_status": session_status,
                "deleted_at": datetime.now(UTC) if deleted else None,
            },
        )
        await session.commit()


def _cost_entry_payload(
    category_id: str,
    *,
    job_id: str | None = None,
    trade_scope_id: str | None = None,
    amount: str = "100.00",
) -> dict:
    payload: dict = {
        "category_id": category_id,
        "amount": amount,
        "incurred_date": date(2026, 6, 1).isoformat(),
    }
    if job_id is not None:
        payload["job_id"] = job_id
    if trade_scope_id is not None:
        payload["trade_scope_id"] = trade_scope_id
    return payload


async def _post_cost_entry(client: AsyncClient, headers: dict, payload: dict) -> dict:
    resp = await client.post("/api/v1/cost-entries/", headers=headers, json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _job_breakdown(client: AsyncClient, headers: dict, job_id: str) -> dict:
    resp = await client.get(f"/api/v1/jobs/{job_id}/cost-breakdown", headers=headers)
    assert resp.status_code == 200, resp.text
    return resp.json()


async def _seed_cost_entry_directly(
    company_id: str, job_id: str, category_id: str, amount: str
) -> None:
    """Insert a cost entry via SQL, bypassing the service-layer labor-category guard."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(
            text(_COST_ENTRY_SEED_SQL),
            {
                "company_id": company_id,
                "job_id": job_id,
                "category_id": category_id,
                "amount": amount,
                "incurred_date": date(2026, 6, 1),
            },
        )
        await session.commit()


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


# ---------------------------------------------------------------------------
# COST-05: labor derivation from tracked time x effective-dated rates
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_derivation_later_rate_change_does_not_rewrite_history(
    async_client, tenant_a_client, seed_two_tenants
):
    """ROADMAP success criterion 2: a new rate effective today leaves past labor unchanged."""
    company_id = seed_two_tenants["tenant_a_id"]
    worker_id = await _create_user(tenant_a_client, "worker-derive-history@tenant-a.com")
    job_id = await _create_job(tenant_a_client)
    headers = _pm_headers(company_id)

    await _post_rate(async_client, headers, worker_id, "30.00", date(2026, 6, 1))
    await _seed_time_entry(
        company_id, job_id, worker_id, datetime(2026, 6, 10, 15, 0, tzinfo=UTC), 28800
    )

    body = await _job_breakdown(async_client, headers, job_id)
    assert body["labor"]["total"] == "240.00"
    assert body["labor"]["unrated_seconds"] == 0

    await _post_rate(async_client, headers, worker_id, "40.00", date.today())

    body_after = await _job_breakdown(async_client, headers, job_id)
    assert body_after["labor"]["total"] == "240.00"


@pytest.mark.asyncio
async def test_derivation_backdated_rate_fills_unrated_days(
    async_client, tenant_a_client, seed_two_tenants
):
    """Unrated seconds are reported honestly, then become rated after a backdated rate."""
    company_id = seed_two_tenants["tenant_a_id"]
    worker_id = await _create_user(tenant_a_client, "worker-derive-backdate@tenant-a.com")
    job_id = await _create_job(tenant_a_client)
    headers = _pm_headers(company_id)

    await _seed_time_entry(
        company_id, job_id, worker_id, datetime(2026, 5, 5, 16, 0, tzinfo=UTC), 14400
    )

    body = await _job_breakdown(async_client, headers, job_id)
    assert body["labor"]["total"] == "0.00"
    assert body["labor"]["unrated_seconds"] == 14400

    await _post_rate(async_client, headers, worker_id, "25.00", date(2026, 5, 1))

    body_after = await _job_breakdown(async_client, headers, job_id)
    assert body_after["labor"]["total"] == "100.00"
    assert body_after["labor"]["unrated_seconds"] == 0


@pytest.mark.asyncio
async def test_derivation_excludes_active_and_deleted_sessions(
    async_client, tenant_a_client, seed_two_tenants
):
    """Active (no duration) and soft-deleted sessions contribute zero labor (D-03)."""
    company_id = seed_two_tenants["tenant_a_id"]
    worker_id = await _create_user(tenant_a_client, "worker-derive-excluded@tenant-a.com")
    job_id = await _create_job(tenant_a_client)
    headers = _pm_headers(company_id)

    await _post_rate(async_client, headers, worker_id, "30.00", date(2026, 1, 1))
    work_day = datetime(2026, 6, 10, 9, 0, tzinfo=UTC)
    await _seed_time_entry(company_id, job_id, worker_id, work_day, None, session_status="active")
    await _seed_time_entry(company_id, job_id, worker_id, work_day, 7200, deleted=True)
    await _seed_time_entry(company_id, job_id, worker_id, work_day, 3600)

    body = await _job_breakdown(async_client, headers, job_id)
    assert body["labor"]["total"] == "30.00"
    assert body["labor"]["rated_seconds"] == 3600
    assert body["labor"]["unrated_seconds"] == 0


@pytest.mark.asyncio
async def test_derivation_uses_rate_effective_on_work_day_not_today(
    async_client, tenant_a_client, seed_two_tenants
):
    """Each session is costed at the rate effective on ITS work day, not the latest rate."""
    company_id = seed_two_tenants["tenant_a_id"]
    worker_id = await _create_user(tenant_a_client, "worker-derive-workday@tenant-a.com")
    job_id = await _create_job(tenant_a_client)
    headers = _pm_headers(company_id)

    await _post_rate(async_client, headers, worker_id, "20.00", date(2026, 1, 1))
    await _post_rate(async_client, headers, worker_id, "50.00", date(2026, 7, 1))
    await _seed_time_entry(
        company_id, job_id, worker_id, datetime(2026, 2, 10, 12, 0, tzinfo=UTC), 3600
    )
    await _seed_time_entry(
        company_id, job_id, worker_id, datetime(2026, 7, 10, 12, 0, tzinfo=UTC), 3600
    )

    body = await _job_breakdown(async_client, headers, job_id)
    assert body["labor"]["total"] == "70.00"
    assert body["labor"]["rated_seconds"] == 7200


@pytest.mark.asyncio
async def test_derivation_basis_is_unburdened(async_client, tenant_a_client, seed_two_tenants):
    """The labor summary carries the D-06 wage-only marker for downstream consumers."""
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    headers = _pm_headers(company_id)

    body = await _job_breakdown(async_client, headers, job_id)
    assert body["labor"]["basis"] == "unburdened"


@pytest.mark.asyncio
async def test_derivation_project_labor_rolls_up_through_job_project_link(
    async_client, tenant_a_client, seed_two_tenants
):
    """Project labor equals the job breakdown's labor via jobs.project_id (D-07)."""
    company_id = seed_two_tenants["tenant_a_id"]
    worker_id = await _create_user(tenant_a_client, "worker-derive-project@tenant-a.com")
    project_id = await _create_project(tenant_a_client)
    job_id = await _create_job(tenant_a_client, project_id=project_id)
    headers = _pm_headers(company_id)

    await _post_rate(async_client, headers, worker_id, "30.00", date(2026, 1, 1))
    await _seed_time_entry(
        company_id, job_id, worker_id, datetime(2026, 6, 10, 15, 0, tzinfo=UTC), 28800
    )

    job_body = await _job_breakdown(async_client, headers, job_id)
    rollup = await async_client.get(f"/api/v1/projects/{project_id}/cost-entries", headers=headers)
    assert rollup.status_code == 200, rollup.text
    assert rollup.json()["labor"]["total"] == job_body["labor"]["total"] == "240.00"


# ---------------------------------------------------------------------------
# COST-06: itemized category breakdowns for job / trade scope / project
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_breakdown_job_category_totals_and_grand_total(
    async_client, tenant_a_client, seed_two_tenants
):
    """Category totals sum per category (ordered by name) and grand_total adds labor."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    worker_id = await _create_user(tenant_a_client, "worker-breakdown-job@tenant-a.com")
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(company_id, "materials")
    subcontractor_id = await _category_id(company_id, "subcontractor")
    headers = _pm_headers(company_id)

    await _post_rate(async_client, headers, worker_id, "30.00", date(2026, 1, 1))
    await _seed_time_entry(
        company_id, job_id, worker_id, datetime(2026, 6, 10, 15, 0, tzinfo=UTC), 28800
    )
    for category_id, amount in (
        (materials_id, "100.00"),
        (materials_id, "50.00"),
        (subcontractor_id, "200.00"),
    ):
        await _post_cost_entry(
            async_client, headers, _cost_entry_payload(category_id, job_id=job_id, amount=amount)
        )

    body = await _job_breakdown(async_client, headers, job_id)
    assert [(row["category_name"], row["total"]) for row in body["categories"]] == [
        ("materials", "150.00"),
        ("subcontractor", "200.00"),
    ]
    assert body["labor"]["total"] == "240.00"
    assert body["grand_total"] == "590.00"


@pytest.mark.asyncio
async def test_breakdown_trade_scope_has_no_labor_figure(
    async_client, tenant_a_client, seed_two_tenants
):
    """Trade-scope breakdowns report labor_tracked_at_job_level, never a labor number (D-08)."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)

    await _post_cost_entry(
        async_client,
        headers,
        _cost_entry_payload(materials_id, trade_scope_id=scope_id, amount="120.00"),
    )

    resp = await async_client.get(
        f"/api/v1/trade-scopes/{scope_id}/cost-breakdown", headers=headers
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["labor"] is None
    assert body["labor_tracked_at_job_level"] is True
    assert body["grand_total"] == "120.00"


@pytest.mark.asyncio
async def test_breakdown_project_rollup_keeps_total_and_entries_backward_compatible(
    async_client, tenant_a_client, seed_two_tenants
):
    """total keeps its pre-Phase-32 meaning (cost-entry sum) while new fields are additive."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    worker_id = await _create_user(tenant_a_client, "worker-breakdown-rollup@tenant-a.com")
    project_id = await _create_project(tenant_a_client)
    job_id = await _create_job(tenant_a_client, project_id=project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)

    await _post_rate(async_client, headers, worker_id, "30.00", date(2026, 1, 1))
    await _seed_time_entry(
        company_id, job_id, worker_id, datetime(2026, 6, 10, 15, 0, tzinfo=UTC), 28800
    )
    await _post_cost_entry(
        async_client, headers, _cost_entry_payload(materials_id, job_id=job_id, amount="50.25")
    )

    resp = await async_client.get(f"/api/v1/projects/{project_id}/cost-entries", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert isinstance(body["total"], str)
    assert isinstance(body["entries"], list)
    assert body["total"] == "50.25"
    assert body["labor"]["total"] == "240.00"
    assert body["grand_total"] == "290.25"


@pytest.mark.asyncio
async def test_breakdown_403_for_admin_on_job_and_trade_scope(
    async_client, tenant_a_client, seed_two_tenants
):
    """Admin is excluded from finance.view — 403 on both breakdown endpoints."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    job_id = await _create_job(tenant_a_client)
    admin_headers = _admin_headers(company_id)

    job_resp = await async_client.get(
        f"/api/v1/jobs/{job_id}/cost-breakdown", headers=admin_headers
    )
    assert job_resp.status_code == 403, job_resp.text
    assert job_resp.json()["detail"] == _MISSING_VIEW_PERMISSION

    scope_resp = await async_client.get(
        f"/api/v1/trade-scopes/{scope_id}/cost-breakdown", headers=admin_headers
    )
    assert scope_resp.status_code == 403, scope_resp.text
    assert scope_resp.json()["detail"] == _MISSING_VIEW_PERMISSION


@pytest.mark.asyncio
async def test_breakdown_rls_isolation_between_tenants(
    async_client, tenant_a_client, seed_two_tenants
):
    """Tenant A's costs and labor never appear in a tenant-B-scoped breakdown request."""
    tenant_a_id = seed_two_tenants["tenant_a_id"]
    tenant_b_id = seed_two_tenants["tenant_b_id"]
    await _seed_cost_categories(tenant_a_id)
    worker_id = await _create_user(tenant_a_client, "worker-breakdown-rls@tenant-a.com")
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(tenant_a_id, "materials")
    a_headers = _pm_headers(tenant_a_id)

    await _post_rate(async_client, a_headers, worker_id, "30.00", date(2026, 1, 1))
    await _seed_time_entry(
        tenant_a_id, job_id, worker_id, datetime(2026, 6, 10, 15, 0, tzinfo=UTC), 28800
    )
    await _post_cost_entry(
        async_client, a_headers, _cost_entry_payload(materials_id, job_id=job_id, amount="150.00")
    )

    b_body = await _job_breakdown(async_client, _pm_headers(tenant_b_id), job_id)
    assert b_body["categories"] == []
    assert b_body["labor"]["total"] == "0.00"
    assert b_body["labor"]["rated_seconds"] == 0
    assert b_body["grand_total"] == "0.00"


@pytest.mark.asyncio
async def test_breakdown_empty_job_returns_zero_totals(
    async_client, tenant_a_client, seed_two_tenants
):
    """A job with no costs and no tracked time returns an all-zero breakdown."""
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    headers = _pm_headers(company_id)

    body = await _job_breakdown(async_client, headers, job_id)
    assert body["categories"] == []
    assert body["labor"]["total"] == "0.00"
    assert body["labor"]["unrated_seconds"] == 0
    assert body["grand_total"] == "0.00"


# ---------------------------------------------------------------------------
# Pitfall 1: reserved labor category guard on manual cost entries
# ---------------------------------------------------------------------------

_LABOR_GUARD_DETAIL = "Labor cost is derived from tracked time."


@pytest.mark.asyncio
async def test_labor_category_rejected_on_cost_entry_create(
    async_client, tenant_a_client, seed_two_tenants
):
    """A manual cost entry targeting the reserved labor category is a 422."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    labor_id = await _category_id(company_id, "labor")
    headers = _pm_headers(company_id)

    resp = await async_client.post(
        "/api/v1/cost-entries/",
        headers=headers,
        json=_cost_entry_payload(labor_id, job_id=job_id),
    )
    assert resp.status_code == 422, resp.text
    assert resp.json()["detail"] == _LABOR_GUARD_DETAIL


@pytest.mark.asyncio
async def test_labor_category_rejected_on_cost_entry_update(
    async_client, tenant_a_client, seed_two_tenants
):
    """PATCHing an existing entry over to the labor category is also a 422."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(company_id, "materials")
    labor_id = await _category_id(company_id, "labor")
    headers = _pm_headers(company_id)

    entry = await _post_cost_entry(
        async_client, headers, _cost_entry_payload(materials_id, job_id=job_id)
    )

    resp = await async_client.patch(
        f"/api/v1/cost-entries/{entry['id']}",
        headers=headers,
        json={"category_id": labor_id},
    )
    assert resp.status_code == 422, resp.text
    assert resp.json()["detail"] == _LABOR_GUARD_DETAIL


@pytest.mark.asyncio
async def test_labor_category_update_without_category_still_succeeds(
    async_client, tenant_a_client, seed_two_tenants
):
    """A PATCH that does not touch category_id passes the guard's None early-return."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)

    entry = await _post_cost_entry(
        async_client, headers, _cost_entry_payload(materials_id, job_id=job_id)
    )

    resp = await async_client.patch(
        f"/api/v1/cost-entries/{entry['id']}",
        headers=headers,
        json={"amount": "175.00"},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["amount"] == "175.00"


@pytest.mark.asyncio
async def test_labor_category_legacy_entry_folds_into_labor_row(
    async_client, tenant_a_client, seed_two_tenants
):
    """A pre-guard labor-categorized entry folds into the single labor row, counted once."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    worker_id = await _create_user(tenant_a_client, "worker-labor-legacy@tenant-a.com")
    job_id = await _create_job(tenant_a_client)
    labor_id = await _category_id(company_id, "labor")
    headers = _pm_headers(company_id)

    await _post_rate(async_client, headers, worker_id, "30.00", date(2026, 1, 1))
    await _seed_time_entry(
        company_id, job_id, worker_id, datetime(2026, 6, 10, 15, 0, tzinfo=UTC), 28800
    )
    await _seed_cost_entry_directly(company_id, job_id, labor_id, "100.00")

    body = await _job_breakdown(async_client, headers, job_id)
    assert all(row["category_name"] != "labor" for row in body["categories"])
    assert body["labor"]["total"] == "340.00"
    assert body["grand_total"] == "340.00"


@pytest.mark.asyncio
async def test_labor_category_still_listed_in_cost_categories(
    async_client, tenant_a_client, seed_two_tenants
):
    """GET /cost-categories/ keeps the labor category — pickers filter client-side."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    headers = _pm_headers(company_id)

    resp = await async_client.get("/api/v1/cost-categories/", headers=headers)
    assert resp.status_code == 200, resp.text
    assert "labor" in {category["name"] for category in resp.json()}
