"""Phase 34 — Budgeting and Overrun Alerts.

Covers BUDG-01 (budget CRUD: create/edit/soft-delete gated finance.manage,
409 on a duplicate active anchor, D-03 re-arm on a raise) and BUDG-02
(budget-vs-actual block embedded on the trade-scope cost breakdown and the
project cost rollup, with spent == grand_total by construction).

Helpers mirror test_phase_32_e2e.py/test_phase_33_e2e.py. The seed helpers
(_create_project, _create_trade_scope, _create_budget, _add_cost_entry) drive
real endpoints — never raw SQL — so later Phase 34 plans reuse them as-is.
Threshold-fire state (budgets.warning_fired_at/overrun_fired_at) is read and
seeded via direct SQL because no endpoint exposes it by design.
"""

from datetime import UTC, date, datetime
from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import select, text

from app.core.database import async_session_factory
from app.core.security import create_access_token
from app.features.finance.models import CostCategory

_BUDGETS_URL = "/api/v1/budgets/"
_SECONDS_PER_HOUR = 3600
_MISSING_MANAGE_PERMISSION = "Missing permission: finance.manage"
_MISSING_VIEW_PERMISSION = "Missing permission: finance.view"
_PROJECT_DUPLICATE_DETAIL = "A budget already exists for this project"
_SCOPE_DUPLICATE_DETAIL = "A budget already exists for this trade scope"
_BREAKDOWNS_DORMANT_DETAIL = "Per-category budget allocation is not available yet"

_COST_CATEGORY_SEED_SQL = (
    "INSERT INTO cost_categories (company_id, name, is_system) "
    "SELECT CAST(:company_id AS uuid), v.name, true "
    "FROM (VALUES ('labor'),('materials'),('subcontractor'),('other')) AS v(name) "
    "ON CONFLICT (company_id, name) DO NOTHING"
)

_SET_FIRED_THRESHOLDS_SQL = (
    "UPDATE budgets SET warning_fired_at = now(), overrun_fired_at = now() "
    "WHERE id = CAST(:budget_id AS uuid)"
)

_FIRED_STATE_SQL = (
    "SELECT warning_fired_at, overrun_fired_at FROM budgets WHERE id = CAST(:budget_id AS uuid)"
)

_TIME_ENTRY_SEED_SQL = (
    "INSERT INTO time_entries (company_id, job_id, contractor_id, clocked_in_at, "
    "clocked_out_at, duration_seconds, session_status, deleted_at) "
    "VALUES (CAST(:company_id AS uuid), CAST(:job_id AS uuid), "
    "CAST(:contractor_id AS uuid), :clocked_in_at, :clocked_out_at, "
    ":duration_seconds, 'completed', NULL)"
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


def _budget_url(budget_id: str) -> str:
    """URL of one budget resource."""
    return f"{_BUDGETS_URL}{budget_id}"


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


async def _create_project(client: AsyncClient, name: str = "Budget Project 34") -> str:
    """Create a project through the API and return its id."""
    resp = await client.post("/api/v1/projects/", json={"name": name, "status": "active"})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_trade_scope(
    client: AsyncClient, project_id: str, trade_name: str = "Plumbing"
) -> str:
    """Create a trade scope on a project through the API and return its id."""
    resp = await client.post(
        "/api/v1/trade-scopes/",
        json={"project_id": project_id, "trade_name": trade_name, "trade_color": "#2196F3"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_job(client: AsyncClient, project_id: str | None = None) -> str:
    """Create a job through the API, optionally linked to a project, and return its id."""
    payload: dict = {"description": "Budget test job", "trade_type": "general"}
    if project_id is not None:
        payload["project_id"] = project_id
    resp = await client.post("/api/v1/jobs/", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_budget(
    client: AsyncClient,
    headers: dict,
    *,
    project_id: str | None = None,
    trade_scope_id: str | None = None,
    total: str = "10000.00",
) -> dict:
    """Create a budget through the API at one anchor and return the response body."""
    payload: dict = {"total": total}
    if project_id is not None:
        payload["project_id"] = project_id
    if trade_scope_id is not None:
        payload["trade_scope_id"] = trade_scope_id
    resp = await client.post(_BUDGETS_URL, headers=headers, json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _add_cost_entry(
    client: AsyncClient,
    headers: dict,
    *,
    job_id: str | None = None,
    trade_scope_id: str | None = None,
    category_id: str,
    amount: str,
) -> str:
    """Create a cost entry through the API at one anchor and return its id."""
    payload: dict = {
        "category_id": category_id,
        "amount": amount,
        "incurred_date": date(2026, 6, 1).isoformat(),
    }
    if job_id is not None:
        payload["job_id"] = job_id
    if trade_scope_id is not None:
        payload["trade_scope_id"] = trade_scope_id
    resp = await client.post("/api/v1/cost-entries/", headers=headers, json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _set_fired_thresholds(company_id: str, budget_id: str) -> None:
    """Force both threshold-fired timestamps on a budget via SQL (no endpoint sets them yet)."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(_SET_FIRED_THRESHOLDS_SQL), {"budget_id": budget_id})
        await session.commit()


async def _fired_state(company_id: str, budget_id: str) -> tuple:
    """Read (warning_fired_at, overrun_fired_at) for a budget via SQL."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(text(_FIRED_STATE_SQL), {"budget_id": budget_id})
        return result.one()


async def _create_user(client: AsyncClient, email: str) -> str:
    """Create a company user via the users API and return its id."""
    resp = await client.post("/api/v1/users/", json={"email": email})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _post_rate(
    client: AsyncClient, headers: dict, user_id: str, hourly_cost: str, effective_from: date
) -> None:
    """Append an effective-dated labor rate for a worker (finance.rates.manage caller)."""
    resp = await client.post(
        "/api/v1/labor-rates/",
        headers=headers,
        json={
            "user_id": user_id,
            "hourly_cost": hourly_cost,
            "effective_from": effective_from.isoformat(),
        },
    )
    assert resp.status_code == 201, resp.text


async def _seed_time_entry(
    company_id: str,
    job_id: str,
    contractor_id: str,
    hours: int,
    *,
    clocked_in_at: datetime,
) -> None:
    """Insert a completed tracked-time row directly, so tests control the work day."""
    duration_seconds = hours * _SECONDS_PER_HOUR
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(
            text(_TIME_ENTRY_SEED_SQL),
            {
                "company_id": company_id,
                "job_id": job_id,
                "contractor_id": contractor_id,
                "clocked_in_at": clocked_in_at,
                "clocked_out_at": clocked_in_at,
                "duration_seconds": duration_seconds,
            },
        )
        await session.commit()


async def _job_breakdown(client: AsyncClient, headers: dict, job_id: str) -> dict:
    """GET a job's cost breakdown as a finance.view holder."""
    resp = await client.get(f"/api/v1/jobs/{job_id}/cost-breakdown", headers=headers)
    assert resp.status_code == 200, resp.text
    return resp.json()


async def _scope_breakdown(client: AsyncClient, headers: dict, scope_id: str) -> dict:
    """GET a trade scope's cost breakdown as a finance.view holder."""
    resp = await client.get(f"/api/v1/trade-scopes/{scope_id}/cost-breakdown", headers=headers)
    assert resp.status_code == 200, resp.text
    return resp.json()


async def _project_rollup(client: AsyncClient, headers: dict, project_id: str) -> dict:
    """GET a project's cost rollup as a finance.view holder."""
    resp = await client.get(f"/api/v1/projects/{project_id}/cost-entries", headers=headers)
    assert resp.status_code == 200, resp.text
    return resp.json()


# ---------------------------------------------------------------------------
# BUDG-01: budget CRUD
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_budget_crud_create_project_budget(async_client, tenant_a_client, seed_two_tenants):
    """POST /budgets/ with a project anchor returns 201 with id, project_id and total."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)

    body = await _create_budget(async_client, _pm_headers(company_id), project_id=project_id)

    assert body["id"]
    assert body["project_id"] == project_id
    assert body["trade_scope_id"] is None
    assert body["total"] == "10000.00"


@pytest.mark.asyncio
async def test_budget_crud_project_and_scope_budgets_coexist(
    async_client, tenant_a_client, seed_two_tenants
):
    """A project budget and a trade-scope budget on the same project coexist independently."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    headers = _pm_headers(company_id)

    project_budget = await _create_budget(async_client, headers, project_id=project_id)
    scope_budget = await _create_budget(
        async_client, headers, trade_scope_id=scope_id, total="4000.00"
    )

    assert project_budget["project_id"] == project_id
    assert scope_budget["trade_scope_id"] == scope_id
    assert scope_budget["project_id"] is None
    assert scope_budget["total"] == "4000.00"


@pytest.mark.asyncio
async def test_budget_crud_rejects_both_or_neither_anchor(
    async_client, tenant_a_client, seed_two_tenants
):
    """POST /budgets/ with both anchors or neither returns 422 (XOR validator)."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    headers = _pm_headers(company_id)

    neither = await async_client.post(_BUDGETS_URL, headers=headers, json={"total": "100.00"})
    assert neither.status_code == 422, neither.text

    both = await async_client.post(
        _BUDGETS_URL,
        headers=headers,
        json={"project_id": project_id, "trade_scope_id": scope_id, "total": "100.00"},
    )
    assert both.status_code == 422, both.text


@pytest.mark.asyncio
async def test_budget_crud_rejects_zero_total(async_client, tenant_a_client, seed_two_tenants):
    """POST /budgets/ with total 0 returns 422 — any positive amount only (D-10)."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)

    resp = await async_client.post(
        _BUDGETS_URL,
        headers=_pm_headers(company_id),
        json={"project_id": project_id, "total": "0"},
    )
    assert resp.status_code == 422, resp.text


@pytest.mark.asyncio
async def test_budget_crud_rejects_dormant_category_breakdowns(
    async_client, tenant_a_client, seed_two_tenants
):
    """A non-empty category_breakdowns list is rejected loudly, never silently dropped (D-11)."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)

    resp = await async_client.post(
        _BUDGETS_URL,
        headers=_pm_headers(company_id),
        json={
            "project_id": project_id,
            "total": "100.00",
            "category_breakdowns": [{"category_id": str(uuid4()), "amount": "50.00"}],
        },
    )
    assert resp.status_code == 422, resp.text
    assert resp.json()["detail"] == _BREAKDOWNS_DORMANT_DETAIL


@pytest.mark.asyncio
async def test_budget_crud_duplicate_project_anchor_conflicts(
    async_client, tenant_a_client, seed_two_tenants
):
    """A second active budget at the same project anchor is refused with 409."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    headers = _pm_headers(company_id)
    await _create_budget(async_client, headers, project_id=project_id)

    resp = await async_client.post(
        _BUDGETS_URL, headers=headers, json={"project_id": project_id, "total": "5000.00"}
    )
    assert resp.status_code == 409, resp.text
    assert resp.json()["detail"] == _PROJECT_DUPLICATE_DETAIL


@pytest.mark.asyncio
async def test_budget_crud_duplicate_scope_anchor_conflicts(
    async_client, tenant_a_client, seed_two_tenants
):
    """A second active budget at the same trade-scope anchor is refused with 409."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    headers = _pm_headers(company_id)
    await _create_budget(async_client, headers, trade_scope_id=scope_id)

    resp = await async_client.post(
        _BUDGETS_URL, headers=headers, json={"trade_scope_id": scope_id, "total": "5000.00"}
    )
    assert resp.status_code == 409, resp.text
    assert resp.json()["detail"] == _SCOPE_DUPLICATE_DETAIL


@pytest.mark.asyncio
async def test_budget_crud_soft_deleted_budget_does_not_block_recreation(
    async_client, tenant_a_client, seed_two_tenants
):
    """After a soft delete, a fresh budget at the same anchor is accepted with 201."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    headers = _pm_headers(company_id)
    first = await _create_budget(async_client, headers, project_id=project_id)

    delete_resp = await async_client.delete(_budget_url(first["id"]), headers=headers)
    assert delete_resp.status_code == 204, delete_resp.text

    second = await _create_budget(async_client, headers, project_id=project_id, total="7500.00")
    assert second["id"] != first["id"]
    assert second["total"] == "7500.00"


@pytest.mark.asyncio
async def test_budget_crud_raising_total_rearms_fired_thresholds(
    async_client, tenant_a_client, seed_two_tenants
):
    """PATCH to a higher total returns 200 and nulls both fired timestamps (D-03 re-arm)."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    headers = _pm_headers(company_id)
    budget = await _create_budget(async_client, headers, project_id=project_id)
    await _set_fired_thresholds(company_id, budget["id"])

    resp = await async_client.patch(
        _budget_url(budget["id"]), headers=headers, json={"total": "20000.00"}
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["total"] == "20000.00"

    warning_fired_at, overrun_fired_at = await _fired_state(company_id, budget["id"])
    assert warning_fired_at is None
    assert overrun_fired_at is None


@pytest.mark.asyncio
async def test_budget_crud_lowering_total_keeps_fired_thresholds(
    async_client, tenant_a_client, seed_two_tenants
):
    """PATCH to a lower total keeps fired timestamps — already-fired thresholds stay deduped."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    headers = _pm_headers(company_id)
    budget = await _create_budget(async_client, headers, project_id=project_id)
    await _set_fired_thresholds(company_id, budget["id"])

    resp = await async_client.patch(
        _budget_url(budget["id"]), headers=headers, json={"total": "500.00"}
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["total"] == "500.00"

    warning_fired_at, overrun_fired_at = await _fired_state(company_id, budget["id"])
    assert warning_fired_at is not None
    assert overrun_fired_at is not None


@pytest.mark.asyncio
async def test_budget_crud_delete_hides_budget_from_lookups(
    async_client, tenant_a_client, seed_two_tenants
):
    """DELETE returns 204; the soft-deleted budget then 404s on PATCH and DELETE."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    headers = _pm_headers(company_id)
    budget = await _create_budget(async_client, headers, project_id=project_id)

    delete_resp = await async_client.delete(_budget_url(budget["id"]), headers=headers)
    assert delete_resp.status_code == 204, delete_resp.text

    patch_resp = await async_client.patch(
        _budget_url(budget["id"]), headers=headers, json={"total": "9000.00"}
    )
    assert patch_resp.status_code == 404, patch_resp.text

    second_delete = await async_client.delete(_budget_url(budget["id"]), headers=headers)
    assert second_delete.status_code == 404, second_delete.text


@pytest.mark.asyncio
async def test_budget_crud_unknown_id_returns_404(async_client, seed_two_tenants):
    """PATCH/DELETE on a never-existing budget id return 404."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    unknown_url = _budget_url(str(uuid4()))

    patch_resp = await async_client.patch(unknown_url, headers=headers, json={"total": "100.00"})
    assert patch_resp.status_code == 404, patch_resp.text

    delete_resp = await async_client.delete(unknown_url, headers=headers)
    assert delete_resp.status_code == 404, delete_resp.text


@pytest.mark.asyncio
async def test_budget_crud_forbidden_without_finance_manage(
    async_client, tenant_a_client, seed_two_tenants
):
    """Admin lacks finance.manage — POST, PATCH and DELETE all 403 before any data changes."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    admin_headers = _admin_headers(company_id)
    some_budget_url = _budget_url(str(uuid4()))

    post_resp = await async_client.post(
        _BUDGETS_URL, headers=admin_headers, json={"project_id": project_id, "total": "100.00"}
    )
    assert post_resp.status_code == 403, post_resp.text
    assert post_resp.json()["detail"] == _MISSING_MANAGE_PERMISSION

    patch_resp = await async_client.patch(
        some_budget_url, headers=admin_headers, json={"total": "100.00"}
    )
    assert patch_resp.status_code == 403, patch_resp.text

    delete_resp = await async_client.delete(some_budget_url, headers=admin_headers)
    assert delete_resp.status_code == 403, delete_resp.text


# ---------------------------------------------------------------------------
# BUDG-02: budget-vs-actual block on the breakdown/rollup responses
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_budget_vs_actual_scope_breakdown_spent_equals_grand_total(
    async_client, tenant_a_client, seed_two_tenants
):
    """The scope breakdown's budget block reuses the response's own grand_total as spent."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    subcontractor_id = await _category_id(company_id, "subcontractor")
    headers = _pm_headers(company_id)

    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="2000.00"
    )
    await _add_cost_entry(
        async_client,
        headers,
        trade_scope_id=scope_id,
        category_id=subcontractor_id,
        amount="1500.00",
    )
    await _create_budget(async_client, headers, trade_scope_id=scope_id, total="10000.00")

    body = await _scope_breakdown(async_client, headers, scope_id)
    budget = body["budget"]
    assert budget is not None, body
    assert budget["total"] == "10000.00"
    assert body["grand_total"] == "3500.00"
    assert budget["spent"] == body["grand_total"]
    assert budget["remaining"] == "6500.00"
    assert budget["percent_used"] == "35.0"


@pytest.mark.asyncio
async def test_budget_vs_actual_project_rollup_spent_includes_derived_labor(
    async_client, tenant_a_client, seed_two_tenants
):
    """The project rollup's budget block counts cost entries plus derived labor as spent."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    worker_id = await _create_user(tenant_a_client, "worker-budget-34@tenant-a.com")
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    job_id = await _create_job(tenant_a_client, project_id=project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)

    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="300.00"
    )
    await _add_cost_entry(
        async_client, headers, job_id=job_id, category_id=materials_id, amount="100.00"
    )
    await _post_rate(async_client, headers, worker_id, "50.00", date(2026, 1, 1))
    await _seed_time_entry(
        company_id, job_id, worker_id, 1, clocked_in_at=datetime(2026, 6, 10, 15, 0, tzinfo=UTC)
    )
    await _create_budget(async_client, headers, project_id=project_id, total="1000.00")

    body = await _project_rollup(async_client, headers, project_id)
    budget = body["budget"]
    assert budget is not None, body
    assert body["grand_total"] == "450.00"
    assert budget["spent"] == body["grand_total"]
    assert budget["total"] == "1000.00"
    assert budget["remaining"] == "550.00"
    assert budget["percent_used"] == "45.0"


@pytest.mark.asyncio
async def test_budget_vs_actual_over_budget_is_never_clamped(
    async_client, tenant_a_client, seed_two_tenants
):
    """Spend above total yields a negative remaining and a percent over 100 — honest (D-10)."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)

    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="1200.00"
    )
    await _create_budget(async_client, headers, trade_scope_id=scope_id, total="1000.00")

    body = await _scope_breakdown(async_client, headers, scope_id)
    budget = body["budget"]
    assert budget is not None, body
    assert budget["spent"] == body["grand_total"] == "1200.00"
    assert budget["remaining"] == "-200.00"
    assert budget["percent_used"] == "120.0"


@pytest.mark.asyncio
async def test_budget_vs_actual_key_is_present_and_null_without_budget(
    async_client, tenant_a_client, seed_two_tenants
):
    """With no budget at the anchor the budget key is present and null on both responses."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    headers = _pm_headers(company_id)

    scope_body = await _scope_breakdown(async_client, headers, scope_id)
    assert "budget" in scope_body
    assert scope_body["budget"] is None

    rollup_body = await _project_rollup(async_client, headers, project_id)
    assert "budget" in rollup_body
    assert rollup_body["budget"] is None


@pytest.mark.asyncio
async def test_budget_vs_actual_soft_deleted_budget_behaves_like_none(
    async_client, tenant_a_client, seed_two_tenants
):
    """A soft-deleted budget disappears from the breakdown exactly like no budget."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    headers = _pm_headers(company_id)
    budget = await _create_budget(async_client, headers, trade_scope_id=scope_id)

    with_budget = await _scope_breakdown(async_client, headers, scope_id)
    assert with_budget["budget"] is not None

    delete_resp = await async_client.delete(_budget_url(budget["id"]), headers=headers)
    assert delete_resp.status_code == 204, delete_resp.text

    after_delete = await _scope_breakdown(async_client, headers, scope_id)
    assert after_delete["budget"] is None


@pytest.mark.asyncio
async def test_budget_vs_actual_job_breakdown_never_carries_budget(
    async_client, tenant_a_client, seed_two_tenants
):
    """The job breakdown never carries a non-null budget block — budgets anchor project/scope."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    job_id = await _create_job(tenant_a_client, project_id=project_id)
    headers = _pm_headers(company_id)
    await _create_budget(async_client, headers, project_id=project_id)
    await _create_budget(async_client, headers, trade_scope_id=scope_id, total="4000.00")

    body = await _job_breakdown(async_client, headers, job_id)
    assert body.get("budget") is None


@pytest.mark.asyncio
async def test_budget_vs_actual_forbidden_without_finance_view(
    async_client, tenant_a_client, seed_two_tenants
):
    """Admin lacks finance.view — the budget-bearing reads still 403 (unchanged gating)."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    admin_headers = _admin_headers(company_id)

    scope_resp = await async_client.get(
        f"/api/v1/trade-scopes/{scope_id}/cost-breakdown", headers=admin_headers
    )
    assert scope_resp.status_code == 403, scope_resp.text
    assert scope_resp.json()["detail"] == _MISSING_VIEW_PERMISSION

    rollup_resp = await async_client.get(
        f"/api/v1/projects/{project_id}/cost-entries", headers=admin_headers
    )
    assert rollup_resp.status_code == 403, rollup_resp.text
